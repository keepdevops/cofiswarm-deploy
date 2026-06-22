"""Observer configuration: declares the services to watch.

Edit SERVICES to match your stack. Each entry may declare a docker container
name, a TCP port to probe, and/or a ZMQ endpoint to ping. Any field may be
omitted; the collector simply reports that signal as N/A for that service.

Environment overrides (so you don't have to edit code in containers):
  OBSERVER_HOST   bind host           (default 127.0.0.1)
  OBSERVER_PORT   bind port           (default 8800)
  OBSERVER_POLL   poll interval secs  (default 2.0)
  OBSERVER_ZMQ_TIMEOUT  zmq ping timeout ms (default 400)
"""
import os

HOST = os.environ.get("OBSERVER_HOST", "127.0.0.1")
PORT = int(os.environ.get("OBSERVER_PORT", "8800"))
POLL_INTERVAL = float(os.environ.get("OBSERVER_POLL", "2.0"))
ZMQ_TIMEOUT_MS = int(os.environ.get("OBSERVER_ZMQ_TIMEOUT", "400"))

# Host used when probing TCP ports / connecting ZMQ from the observer.
PROBE_HOST = os.environ.get("OBSERVER_PROBE_HOST", "127.0.0.1")

# Declared services. `port` is the HOST-published port (left side of docker's
# "0.0.0.0:HOST->CONTAINER/tcp" mapping), probed on PROBE_HOST.
#
# `zmq` endpoints are REQ-pinged (expect a REP reply); set "type": "sub" to
# instead treat the endpoint as a PUB and check for any recent message. Omit
# "zmq" entirely to skip the ZMQ signal (shown as n/a). None of the services
# below speak ZMQ today — add a "zmq" block to any entry once one does, e.g.:
#   "zmq": {"endpoint": "tcp://%s:5570" % PROBE_HOST, "type": "req"},
SERVICES = [
    {
        "name": "pgvector",
        "label": "Postgres / pgvector",
        "container": "matrix-pgvector",
        "port": 5433,  # host 5433 -> container 5432
    },
    {
        "name": "qdrant",
        "label": "Qdrant Vector DB",
        "container": "qdrant",
        "port": 6333,
    },
    {
        "name": "searxng",
        "label": "SearXNG",
        "container": "trusting_gould",  # searxng/searxng image
        "port": 8080,
    },
    {
        "name": "plantuml",
        "label": "PlantUML Server",
        "container": "plantuml-airgap",
        "port": 8079,  # host 127.0.0.1:8079 -> container 8080
    },
    {
        "name": "observer",
        "label": "Observer (self)",
        "container": "cofiswarm-observer",
        "port": 8810,  # host 8810 -> container 8800 (this dashboard)
    },
]


def service_names():
    return [s["name"] for s in SERVICES]
