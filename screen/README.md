# Cofiswarm Observer

A status dashboard for the swarm stack — shows **Docker container state**,
**TCP port reachability**, and **ZMQ socket health** for each declared service,
styled to match the Cofiswarm brewlate (light) theme.

## Run

```bash
./run.sh                 # creates .venv, installs pyzmq, serves on :8800
open http://127.0.0.1:8800
```

Or directly (ZMQ signals report "unavailable" without pyzmq):

```bash
python3 -m observer.server
```

### In Docker

```bash
docker compose up --build -d     # serves on http://127.0.0.1:8810
docker compose logs -f           # follow
docker compose down              # stop
```

The container mounts the Docker socket (read-only) so `docker ps` sees host
containers, and probes ports via `host.docker.internal`. Caveats:

* **Mounting `/var/run/docker.sock` grants the container visibility/control of
  your daemon** — only run it where that is acceptable.
* `host.docker.internal` reaches ports **published to the host** (the left side
  of docker's `HOST->CONTAINER` mapping). Ports only reachable inside a private
  container network won't be seen — put the Observer on that network instead.
* On Linux, `host.docker.internal` is wired via the `host-gateway` entry in
  `docker-compose.yml`; on Docker Desktop (macOS/Windows) it resolves natively.
* `--network host` is **not** a working alternative on Docker Desktop, which is
  why this image probes via `host.docker.internal` rather than host networking.

## Configure

Edit `observer/config.py` → `SERVICES`. Each entry may declare any of:

| field       | meaning                                                       |
|-------------|---------------------------------------------------------------|
| `container` | Docker container name (matched against `docker ps -a`)        |
| `port`      | TCP port probed on `OBSERVER_PROBE_HOST`                      |
| `zmq`       | `{endpoint, type}` — `req` (ping/reply) or `sub` (recent msg) |

Omit any field to skip that signal (rendered as `n/a`).

### Environment overrides

| var                   | default     | purpose                  |
|-----------------------|-------------|--------------------------|
| `OBSERVER_HOST`       | `127.0.0.1` | bind host                |
| `OBSERVER_PORT`       | `8800`      | bind port                |
| `OBSERVER_POLL`       | `2.0`       | SSE poll interval (secs) |
| `OBSERVER_PROBE_HOST` | `127.0.0.1` | host for port/zmq probes |
| `OBSERVER_ZMQ_TIMEOUT`| `400`       | zmq ping timeout (ms)    |

## How it works

`observer/collectors.py` builds a snapshot (docker via `docker ps`, ports via
`socket.connect`, ZMQ via pyzmq). `observer/server.py` pushes that snapshot over
Server-Sent Events (`/api/stream`) every poll interval; the frontend in
`static/` renders one card per service with a per-signal LED and an aggregate
health badge.
