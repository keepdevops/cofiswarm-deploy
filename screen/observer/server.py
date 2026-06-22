"""Observer HTTP server: serves the static UI and streams status via SSE.

Routes:
  GET /                -> static/index.html
  GET /static/<file>  -> static assets
  GET /api/status     -> one-shot JSON snapshot
  GET /api/stream     -> text/event-stream, pushes a snapshot every POLL secs

Stdlib only (ThreadingHTTPServer). No silent failures: every handler logs on
error and returns an explicit status code.
"""
import json
import logging
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import collectors, config

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("observer.server")

STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static")
_CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # route access logs through logging
        logger.info("%s - %s", self.address_string(), fmt % args)

    def _send(self, code, body, content_type, extra_headers=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra_headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        try:
            if path == "/" or path == "/index.html":
                return self._serve_static("index.html")
            if path.startswith("/static/"):
                return self._serve_static(path[len("/static/"):])
            if path == "/api/status":
                return self._serve_snapshot()
            if path == "/api/stream":
                return self._serve_stream()
            self._send(404, "not found", "text/plain; charset=utf-8")
        except BrokenPipeError:
            logger.info("client disconnected: %s", path)
        except Exception as exc:  # fail loudly, keep server alive
            logger.error("handler error for %s: %s", path, exc, exc_info=True)
            try:
                self._send(500, "internal error", "text/plain; charset=utf-8")
            except OSError:
                pass

    def _serve_static(self, rel):
        # Prevent path traversal outside STATIC_DIR.
        full = os.path.normpath(os.path.join(STATIC_DIR, rel))
        if not full.startswith(STATIC_DIR) or not os.path.isfile(full):
            logger.error("static not found or rejected: %s", rel)
            return self._send(404, "not found", "text/plain; charset=utf-8")
        ext = os.path.splitext(full)[1]
        with open(full, "rb") as fh:
            body = fh.read()
        self._send(200, body, _CONTENT_TYPES.get(ext, "application/octet-stream"))

    def _serve_snapshot(self):
        snap = collectors.collect()
        self._send(200, json.dumps(snap), "application/json")

    def _serve_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        logger.info("SSE client connected")
        try:
            while True:
                snap = collectors.collect()
                payload = "data: %s\n\n" % json.dumps(snap)
                self.wfile.write(payload.encode("utf-8"))
                self.wfile.flush()
                time.sleep(config.POLL_INTERVAL)
        except (BrokenPipeError, ConnectionResetError):
            logger.info("SSE client disconnected")


def main():
    server = ThreadingHTTPServer((config.HOST, config.PORT), Handler)
    logger.info("Observer listening on http://%s:%d (poll %.1fs)",
                config.HOST, config.PORT, config.POLL_INTERVAL)
    logger.info("Watching %d services: %s",
                len(config.SERVICES), ", ".join(config.service_names()))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("shutting down")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
