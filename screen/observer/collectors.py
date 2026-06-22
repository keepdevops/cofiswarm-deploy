"""Status collectors for Docker containers, TCP ports, and ZMQ endpoints.

Each collector fails loudly into a structured status dict — never silently.
A signal that cannot be determined returns state "unknown" with an `error`
field rather than raising, so one broken probe never blocks the others.
"""
import json
import logging
import socket
import subprocess

from . import config

logger = logging.getLogger("observer.collectors")

# pyzmq is optional. If absent, ZMQ signals degrade to state "unavailable"
# with a clear message rather than crashing the server.
try:
    import zmq
    _ZMQ = True
except ImportError:  # logged once at import; reported per-probe below
    zmq = None
    _ZMQ = False
    logger.warning("pyzmq not installed; ZMQ signals will report 'unavailable'")


def collect_docker():
    """Return {container_name: {state, status, health, uptime}} from `docker ps`."""
    try:
        proc = subprocess.run(
            ["docker", "ps", "-a", "--no-trunc", "--format", "{{json .}}"],
            capture_output=True, text=True, timeout=8,
        )
    except FileNotFoundError:
        logger.error("docker CLI not found on PATH")
        return {"__error__": "docker CLI not found"}
    except subprocess.TimeoutExpired:
        logger.error("docker ps timed out")
        return {"__error__": "docker ps timed out"}

    if proc.returncode != 0:
        msg = proc.stderr.strip() or "docker ps failed"
        logger.error("docker ps failed: %s", msg)
        return {"__error__": msg}

    out = {}
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            logger.error("could not parse docker line: %s (%s)", line, exc)
            continue
        names = row.get("Names", "")
        state = row.get("State", "").lower()
        status = row.get("Status", "")
        health = "none"
        # docker encodes health inside Status, e.g. "Up 3 hours (healthy)"
        for h in ("healthy", "unhealthy", "starting"):
            if "(%s)" % h in status:
                health = h
                break
        for name in names.split(","):
            name = name.strip()
            if name:
                out[name] = {"state": state, "status": status, "health": health}
    return out


def probe_port(host, port, timeout=0.6):
    """Return ('open'|'closed', detail) for a TCP port via connect()."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect((host, port))
        return "open", "connected"
    except (ConnectionRefusedError, OSError) as exc:
        return "closed", str(exc)
    finally:
        sock.close()


def probe_zmq(spec):
    """Ping a ZMQ endpoint. REQ: send/recv a ping. SUB: poll for any message.

    Returns (state, detail) where state is 'up' | 'down' | 'unavailable'.
    """
    if not _ZMQ:
        return "unavailable", "pyzmq not installed"

    endpoint = spec["endpoint"]
    kind = spec.get("type", "req")
    ctx = zmq.Context.instance()
    timeout = config.ZMQ_TIMEOUT_MS

    if kind == "sub":
        sock = ctx.socket(zmq.SUB)
        sock.setsockopt(zmq.RCVTIMEO, timeout)
        sock.setsockopt(zmq.LINGER, 0)
        sock.setsockopt_string(zmq.SUBSCRIBE, "")
        try:
            sock.connect(endpoint)
            poller = zmq.Poller()
            poller.register(sock, zmq.POLLIN)
            if poller.poll(timeout):
                sock.recv()
                return "up", "message received"
            return "down", "no message within %dms" % timeout
        except zmq.ZMQError as exc:
            logger.error("zmq sub probe failed for %s: %s", endpoint, exc)
            return "down", str(exc)
        finally:
            sock.close(0)

    # REQ ping
    sock = ctx.socket(zmq.REQ)
    sock.setsockopt(zmq.RCVTIMEO, timeout)
    sock.setsockopt(zmq.SNDTIMEO, timeout)
    sock.setsockopt(zmq.LINGER, 0)
    try:
        sock.connect(endpoint)
        sock.send(b"ping")
        sock.recv()
        return "up", "reply received"
    except zmq.ZMQError as exc:
        logger.error("zmq req probe failed for %s: %s", endpoint, exc)
        return "down", str(exc)
    finally:
        sock.close(0)


def collect():
    """Build the full snapshot for all declared services."""
    docker_map = collect_docker()
    docker_error = docker_map.pop("__error__", None)

    services = []
    for svc in config.SERVICES:
        row = {"name": svc["name"], "label": svc.get("label", svc["name"])}

        # Docker signal
        cname = svc.get("container")
        if cname is None:
            row["docker"] = {"state": "n/a"}
        elif docker_error:
            row["docker"] = {"state": "unknown", "error": docker_error}
        else:
            d = docker_map.get(cname)
            row["docker"] = d if d else {"state": "absent"}
        row["container"] = cname

        # Port signal
        port = svc.get("port")
        if port is None:
            row["port"] = {"state": "n/a"}
        else:
            state, detail = probe_port(config.PROBE_HOST, port)
            row["port"] = {"state": state, "number": port, "detail": detail}

        # ZMQ signal
        zspec = svc.get("zmq")
        if zspec is None:
            row["zmq"] = {"state": "n/a"}
        else:
            state, detail = probe_zmq(zspec)
            row["zmq"] = {"state": state, "endpoint": zspec["endpoint"],
                          "kind": zspec.get("type", "req"), "detail": detail}

        services.append(row)

    return {"services": services, "docker_error": docker_error}
