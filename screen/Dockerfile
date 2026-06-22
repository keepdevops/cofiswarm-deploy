# Cofiswarm Observer image.
#
# The Observer needs the `docker` CLI (to run `docker ps` against the host
# daemon via a mounted socket) and pyzmq. We copy just the static docker
# client binary from the official docker:cli image — no daemon, small layer.
FROM docker:27-cli AS dockercli

FROM python:3.12-slim AS app

# docker client binary (talks to the host daemon over the mounted socket)
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker

WORKDIR /app

# Dependencies first for layer caching.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application code.
COPY observer ./observer
COPY static ./static

# Inside the container the server must bind all interfaces, and probes must
# target the host (overridden in compose for Linux via host-gateway).
ENV OBSERVER_HOST=0.0.0.0 \
    OBSERVER_PORT=8800 \
    OBSERVER_PROBE_HOST=host.docker.internal \
    PYTHONUNBUFFERED=1

EXPOSE 8800

# Simple liveness check against the snapshot endpoint.
HEALTHCHECK --interval=30s --timeout=4s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; \
    sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8800/api/status', timeout=3).status==200 else 1)"

CMD ["python", "-m", "observer.server"]
