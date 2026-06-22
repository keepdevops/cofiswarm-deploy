/* Observer frontend: subscribe to /api/stream (SSE) and render service cards.
   Fails loudly — connection drops flip the header to "offline" and a banner
   surfaces any docker-level error, so problems are never silent in the UI. */
(function () {
  "use strict";

  var grid = document.getElementById("grid");
  var summary = document.getElementById("summary");
  var conn = document.getElementById("conn");
  var connLabel = document.getElementById("conn-label");
  var banner = document.getElementById("banner");
  var updated = document.getElementById("updated");

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  // Map a service's three signals to an aggregate card state.
  function cardState(svc) {
    var sig = [svc.docker.state, svc.port.state, svc.zmq.state];
    var bad = 0, good = 0, considered = 0;
    sig.forEach(function (s) {
      if (s === "n/a" || s === "unknown" || s === "unavailable") return;
      considered++;
      if (s === "running" || s === "open" || s === "up") good++;
      else bad++;
    });
    if (considered === 0) return "unknown";
    if (bad === 0) return "up";
    if (good === 0) return "down";
    return "partial";
  }

  function dockerText(d) {
    if (d.state === "n/a") return ["n/a", ""];
    if (d.state === "unknown") return ["unknown", d.error || ""];
    if (d.state === "absent") return ["not created", ""];
    var det = d.health && d.health !== "none" ? d.health : (d.status || "");
    return [d.state, det];
  }

  function sigRow(key, stateClass, value, detail) {
    var row = el("div", "sig s-" + stateClass);
    row.appendChild(el("span", "led"));
    row.appendChild(el("span", "k", key));
    var v = el("span", "v");
    v.appendChild(document.createTextNode(value));
    if (detail) {
      var d = el("span", "det", "  " + detail);
      v.appendChild(d);
    }
    row.appendChild(v);
    return row;
  }

  function renderCard(svc) {
    var state = cardState(svc);
    var card = el("div", "card " + state);

    var head = el("div", "card-head");
    var left = el("div");
    left.appendChild(el("div", "card-name", svc.label));
    if (svc.container) left.appendChild(el("div", "card-container", svc.container));
    head.appendChild(left);
    head.appendChild(el("span", "badge " + state, state));
    card.appendChild(head);

    var sigs = el("div", "signals");
    var dt = dockerText(svc.docker);
    sigs.appendChild(sigRow("docker", svc.docker.state, dt[0], dt[1]));

    var p = svc.port;
    var pVal = p.state === "n/a" ? "n/a" :
      (p.state + (p.number ? " :" + p.number : ""));
    sigs.appendChild(sigRow("port", p.state, pVal, p.state === "n/a" ? "" : p.detail));

    var z = svc.zmq;
    var zVal = z.state === "n/a" ? "n/a" : z.state;
    var zDet = z.state === "n/a" ? "" :
      ((z.kind ? z.kind.toUpperCase() + " " : "") + (z.endpoint || ""));
    sigs.appendChild(sigRow("zmq", z.state, zVal, zDet));

    card.appendChild(sigs);
    return card;
  }

  function renderSummary(services) {
    var up = 0, down = 0, partial = 0;
    services.forEach(function (s) {
      var st = cardState(s);
      if (st === "up") up++;
      else if (st === "down" || st === "unknown") down++;
      else partial++;
    });
    summary.innerHTML = "";
    [["ok", up, "Healthy"], ["warn", partial, "Degraded"],
     ["crit", down, "Down"], ["", services.length, "Total"]]
      .forEach(function (c) {
        var chip = el("div", "chip " + c[0]);
        chip.appendChild(el("div", "n", String(c[1])));
        chip.appendChild(el("div", "l", c[2]));
        summary.appendChild(chip);
      });
  }

  function render(snap) {
    if (snap.docker_error) {
      banner.textContent = "Docker error: " + snap.docker_error;
      banner.classList.remove("hidden");
    } else {
      banner.classList.add("hidden");
    }
    renderSummary(snap.services);
    grid.innerHTML = "";
    snap.services.forEach(function (s) { grid.appendChild(renderCard(s)); });
    updated.textContent = "last update: " + new Date().toLocaleTimeString();
  }

  function setConn(state, label) {
    conn.className = "obs-conn " + state;
    connLabel.textContent = label;
  }

  function connect() {
    var es = new EventSource("/api/stream");
    es.onopen = function () { setConn("live", "live"); };
    es.onmessage = function (ev) {
      try {
        render(JSON.parse(ev.data));
      } catch (err) {
        console.error("failed to parse snapshot", err, ev.data);
        banner.textContent = "Malformed snapshot from server — see console.";
        banner.classList.remove("hidden");
      }
    };
    es.onerror = function () {
      setConn("dead", "offline — retrying");
      console.error("SSE connection error; EventSource will auto-retry");
    };
  }

  // Static mockup mode: if a snapshot is baked into the page, render it and
  // skip the live SSE connection (used for offline previews / screenshots).
  if (window.__OBSERVER_SNAPSHOT__) {
    setConn("live", "preview");
    render(window.__OBSERVER_SNAPSHOT__);
  } else {
    connect();
  }
})();
