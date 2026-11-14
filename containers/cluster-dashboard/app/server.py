#!/usr/bin/env python3
"""Cluster dashboard: polls the collector agent and serves the UI and /api/state.

The container has no access to the host besides the agent's Unix socket. It keeps
one hour of samples in memory and turns the agent's cumulative counters into rates.
Nothing is persisted; a restart starts with an empty history.
"""

from __future__ import annotations

import collections
import gzip
import http.client
import http.server
import json
import os
import socket
import socketserver
import threading
import time
from pathlib import Path

AGENT_SOCKET = os.environ.get("DASHBOARD_AGENT_SOCKET", "/run/cluster-dashboard/agent.sock")
LISTEN = os.environ.get("DASHBOARD_LISTEN", "0.0.0.0:8080")
INTERVAL = float(os.environ.get("DASHBOARD_INTERVAL", "10"))
HISTORY = int(os.environ.get("DASHBOARD_HISTORY", "360"))
STATIC = Path(__file__).with_name("index.html")


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path: str, timeout: float) -> None:
        super().__init__("localhost", timeout=timeout)
        self.unix_path = path

    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.unix_path)


def fetch_cluster() -> dict:
    conn = UnixHTTPConnection(AGENT_SOCKET, timeout=60)
    try:
        conn.request("GET", "/v1/cluster")
        response = conn.getresponse()
        body = response.read()
        if response.status != 200:
            raise RuntimeError(f"agent returned HTTP {response.status}")
        return json.loads(body)
    finally:
        conn.close()


def rate(cur: float | None, prev: float | None, dt: float) -> float | None:
    """Per-second rate of a cumulative counter; None across resets or gaps."""
    if cur is None or prev is None or dt <= 0 or cur < prev:
        return None
    return (cur - prev) / dt


def net_totals(net) -> tuple[int, int] | None:
    if not isinstance(net, dict) or "shared_with" in net:
        return None
    return (sum(i["rx"] for i in net.values()), sum(i["tx"] for i in net.values()))


def compact(value: float | None) -> float | None:
    if value is None:
        return None
    return round(value, 4) if abs(value) < 100 else round(value)


class State:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.previous: dict[str, tuple[float, dict]] = {}
        self.history: dict[str, collections.deque] = {}
        self.seen: dict[str, float] = {}
        self.current: dict = {"updated": None, "error": "waiting for the first sample", "nodes": []}

    def push(self, key: str, value: float | None, now: float) -> list:
        series = self.history.get(key)
        if series is None:
            series = self.history[key] = collections.deque(maxlen=HISTORY)
        series.append(compact(value))
        self.seen[key] = now
        return list(series)

    def delta(self, key: str, sample: dict, now: float) -> tuple[dict | None, float]:
        prev = self.previous.get(key)
        self.previous[key] = (now, sample)
        if prev is None:
            return None, 0.0
        return prev[1], now - prev[0]

    def node_view(self, node: dict, now: float) -> dict:
        name = node["name"]
        view = {k: node.get(k) for k in ("name", "address", "ok", "error", "tailnet")}
        data = node.get("data")
        if not node.get("ok") or not data:
            return view
        at = data.get("at") or now
        prev, dt = self.delta(f"node:{name}", data, at)
        cpu = data["cpu"]
        cpu_pct = None
        if prev:
            busy = rate(cpu["busy"], prev["cpu"]["busy"], 1)
            total = rate(cpu["total"], prev["cpu"]["total"], 1)
            cpu_pct = 100 * busy / total if busy is not None and total else None
        mem = data["memory"]
        used = mem["total"] - mem["available"]
        interfaces = []
        rx_total = tx_total = None
        for ifname, counters in sorted(data["interfaces"].items()):
            old = (prev or {}).get("interfaces", {}).get(ifname, {})
            rx = rate(counters["rx"], old.get("rx"), dt)
            tx = rate(counters["tx"], old.get("tx"), dt)
            if rx is not None:
                rx_total = (rx_total or 0) + rx
                tx_total = (tx_total or 0) + (tx or 0)
            interfaces.append({"name": ifname, "rx": counters["rx"], "tx": counters["tx"],
                               "rx_rate": rx, "tx_rate": tx})
        view.update({
            "system": data["system"],
            "errors": data.get("errors", []),
            "storage_at": data.get("storage_at"),
            "cpu": {"percent": cpu_pct, "history": self.push(f"{name}:cpu", cpu_pct, now)},
            "memory": {**mem, "used": used,
                       "history": self.push(f"{name}:mem", 100 * used / mem["total"] if mem["total"] else None, now)},
            "filesystems": data["filesystems"],
            "interfaces": interfaces,
            "network": {"rx_rate": rx_total, "tx_rate": tx_total,
                        "rx_history": self.push(f"{name}:rx", rx_total, now),
                        "tx_history": self.push(f"{name}:tx", tx_total, now)},
            "containers": [self.workload_view(name, c, "container", at, now) for c in data.get("containers", [])],
            "services": [self.workload_view(name, s, "service", at, now) for s in data.get("services", [])],
        })
        return view

    def workload_view(self, node: str, item: dict, kind: str, at: float, now: float) -> dict:
        """Rates use the agent's sample time `at`; history slots use the poll time `now`."""
        ident = item.get("id") or item.get("unit")
        key = f"{node}:{kind}:{ident}"
        prev, dt = self.delta(key, item, at)
        prev = prev or {}
        cpu = rate(item.get("cpu_usec"), prev.get("cpu_usec"), dt)
        cpu = cpu / 1e6 if cpu is not None else None
        view = dict(item)
        view["node"] = node
        view["cpu"] = cpu
        view["io_read_rate"] = rate(item.get("io_read"), prev.get("io_read"), dt)
        view["io_write_rate"] = rate(item.get("io_write"), prev.get("io_write"), dt)
        totals, old_totals = net_totals(item.get("net")), net_totals(prev.get("net"))
        if totals:
            view["net_rx"], view["net_tx"] = totals
            view["net_rx_rate"] = rate(totals[0], old_totals and old_totals[0], dt)
            view["net_tx_rate"] = rate(totals[1], old_totals and old_totals[1], dt)
        view["history"] = {
            "cpu": self.push(f"{key}:cpu", cpu, now),
            "memory": self.push(f"{key}:mem", item.get("memory"), now),
        }
        if totals:
            view["history"]["rx"] = self.push(f"{key}:rx", view["net_rx_rate"], now)
            view["history"]["tx"] = self.push(f"{key}:tx", view["net_tx_rate"], now)
        return view

    def update(self) -> None:
        now = time.time()
        try:
            raw = fetch_cluster()
        except Exception as exc:  # keep serving the last good state
            with self.lock:
                self.current = {**self.current, "error": f"collector agent: {exc}", "checked": now}
            return
        nodes = [self.node_view(n, now) for n in raw.get("nodes", [])]
        # Forget series of containers and nodes that disappeared an hour ago.
        horizon = now - HISTORY * INTERVAL
        for key in [k for k, t in self.seen.items() if t < horizon]:
            self.seen.pop(key, None)
            self.history.pop(key, None)
        for key in [k for k, v in self.previous.items() if v[0] < horizon]:
            self.previous.pop(key, None)
        state = {
            "updated": now,
            "checked": now,
            "interval": INTERVAL,
            "collector": raw.get("collector"),
            "error": "; ".join(raw.get("errors", [])) or None,
            "nodes": nodes,
        }
        with self.lock:
            self.current = state

    def loop(self) -> None:
        while True:
            start = time.monotonic()
            self.update()
            time.sleep(max(1.0, INTERVAL - (time.monotonic() - start)))

    def json(self) -> bytes:
        with self.lock:
            return json.dumps(self.current, separators=(",", ":")).encode()


STATE = State()


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "cluster-dashboard"

    def send_body(self, body: bytes, content_type: str, cache: str = "no-store") -> None:
        if "gzip" in self.headers.get("Accept-Encoding", "") and len(body) > 1024:
            body = gzip.compress(body, 6)
            encoding = "gzip"
        else:
            encoding = None
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; style-src 'self' 'unsafe-inline'; "
                         "script-src 'self' 'unsafe-inline'; img-src 'self' data:; "
                         "frame-ancestors 'none'")
        if encoding:
            self.send_header("Content-Encoding", encoding)
            self.send_header("Vary", "Accept-Encoding")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/":
            self.send_body(STATIC.read_bytes(), "text/html; charset=utf-8")
        elif path == "/api/state":
            self.send_body(STATE.json(), "application/json")
        elif path == "/healthz":
            self.send_body(b"OK\n", "text/plain")
        else:
            self.send_error(404)

    def log_message(self, fmt: str, *args) -> None:
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def main() -> None:
    threading.Thread(target=STATE.loop, daemon=True).start()
    host, _, port = LISTEN.rpartition(":")
    Server((host, int(port)), Handler).serve_forever()


if __name__ == "__main__":
    main()
