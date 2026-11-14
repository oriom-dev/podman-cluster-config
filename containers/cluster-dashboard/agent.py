#!/usr/bin/env python3
"""Read-only node, container and service metrics for the cluster dashboard.

Runs natively on every node (it needs root to see Podman and other users' cgroups)
and is socket-activated by systemd:

  GET /v1/node     this node: CPU, memory, filesystems, interfaces, Podman
                   containers and native systemd services, with storage sizes
  GET /v1/cluster  (collector only) every tailnet peer's /v1/node plus the
                   tailnet view of the local tailscaled

Counters are cumulative (bytes, CPU microseconds); the dashboard derives rates
from consecutive samples, so the agent keeps no history and holds no state that
matters across restarts. It never changes anything: Podman, systemctl, du and
tailscale are only invoked with read-only subcommands; Caddy's admin API is
only read (/config/ and /metrics).
"""

from __future__ import annotations

import concurrent.futures
import http.server
import json
import os
import socket
import socketserver
import subprocess
import threading
import time
import re
import urllib.request

PODMAN = os.environ.get("AGENT_PODMAN", "podman")
TAILSCALE = os.environ.get("AGENT_TAILSCALE", "tailscale")
COLLECT = os.environ.get("AGENT_COLLECT", "0") == "1"
PEER_PORT = int(os.environ.get("AGENT_PEER_PORT", "9925"))
STORAGE_INTERVAL = int(os.environ.get("AGENT_STORAGE_INTERVAL", "600"))
SNAPSHOT_TTL = 3.0
TOPOLOGY_TTL = 60.0
CADDY_ADMIN = os.environ.get("AGENT_CADDY_ADMIN", "http://127.0.0.1:2019")

CGROUP_ROOT = "/sys/fs/cgroup"
REAL_FS = {"ext4", "ext3", "xfs", "btrfs", "f2fs", "zfs", "vfat", "bcachefs"}
VIRTUAL_IF_PREFIXES = ("lo", "veth", "podman", "cni", "br-", "docker", "flannel", "cali", "virbr")
# Mount sources never worth sizing: immutable store paths, runtime and config files.
UNSIZED_PREFIXES = ("/nix/store", "/run", "/etc", "/proc", "/sys", "/dev", "/tmp")


def read_text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def read_int(path: str) -> int | None:
    """Integer cgroup/proc value; "max" and missing files are None."""
    text = read_text(path)
    if text is None:
        return None
    text = text.strip()
    return int(text) if text.isdigit() else None


def run(args: list[str], timeout: float = 20) -> str:
    return subprocess.run(
        args, capture_output=True, text=True, timeout=timeout, check=True
    ).stdout


# ---------------------------------------------------------------------------
# Host


def cpu_seconds() -> dict:
    """Cumulative busy/total CPU seconds across all CPUs, from /proc/stat."""
    fields = (read_text("/proc/stat") or "cpu 0").splitlines()[0].split()[1:9]
    ticks = [int(x) for x in fields] + [0] * (8 - len(fields))
    hz = os.sysconf("SC_CLK_TCK")
    total = sum(ticks)
    idle = ticks[3] + ticks[4]  # idle + iowait
    return {"busy": (total - idle) / hz, "total": total / hz}


def parse_meminfo(text: str) -> dict:
    values = {}
    for line in text.splitlines():
        key, _, rest = line.partition(":")
        parts = rest.split()
        if parts:
            values[key] = int(parts[0]) * (1024 if parts[1:] == ["kB"] else 1)
    return {
        "total": values.get("MemTotal", 0),
        "available": values.get("MemAvailable", 0),
        "swap_total": values.get("SwapTotal", 0),
        "swap_free": values.get("SwapFree", 0),
    }


def parse_mounts(text: str) -> list[tuple[str, str, str]]:
    """(device, mountpoint, fstype) of real filesystems, one per device."""
    seen: dict[str, tuple[str, str, str]] = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 4 or parts[2] not in REAL_FS or "ro" in parts[3].split(","):
            continue
        device, mountpoint, fstype = parts[0], parts[1].replace("\\040", " "), parts[2]
        # Bind mounts repeat the device; keep the shortest (outermost) mountpoint.
        if device not in seen or len(mountpoint) < len(seen[device][1]):
            seen[device] = (device, mountpoint, fstype)
    return sorted(seen.values(), key=lambda m: m[1])


def filesystems() -> list[dict]:
    result = []
    for device, mountpoint, fstype in parse_mounts(read_text("/proc/mounts") or ""):
        try:
            st = os.statvfs(mountpoint)
        except OSError:
            continue
        if st.f_blocks == 0:
            continue
        result.append({
            "mount": mountpoint,
            "device": device,
            "type": fstype,
            "total": st.f_blocks * st.f_frsize,
            "used": (st.f_blocks - st.f_bfree) * st.f_frsize,
            "available": st.f_bavail * st.f_frsize,
        })
    return result


def parse_net_dev(text: str, skip_virtual: bool) -> dict[str, dict]:
    result = {}
    for line in text.splitlines()[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        fields = rest.split()
        if len(fields) < 9 or name == "lo":
            continue
        if skip_virtual and name.startswith(VIRTUAL_IF_PREFIXES):
            continue
        result[name] = {"rx": int(fields[0]), "tx": int(fields[8])}
    return result


def system_info() -> dict:
    uname = os.uname()
    uptime = (read_text("/proc/uptime") or "0").split()[0]
    load = (read_text("/proc/loadavg") or "0 0 0").split()[:3]
    info = {
        "hostname": uname.nodename,
        "kernel": uname.release,
        "uptime": float(uptime),
        "load": [float(x) for x in load],
        "cpus": os.cpu_count() or 1,
    }
    try:
        version = json.loads(run(["nixos-version", "--json"], timeout=5))
        info["revision"] = version.get("configurationRevision")
        info["nixos"] = version.get("nixosVersion")
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return info


# ---------------------------------------------------------------------------
# cgroups


def cgroup_stats(path: str) -> dict:
    base = CGROUP_ROOT + path
    stats: dict = {
        "memory": read_int(f"{base}/memory.current"),
        "memory_max": read_int(f"{base}/memory.max"),
        "memory_peak": read_int(f"{base}/memory.peak"),
        "pids": read_int(f"{base}/pids.current"),
        "pids_max": read_int(f"{base}/pids.max"),
    }
    for line in (read_text(f"{base}/cpu.stat") or "").splitlines():
        key, _, value = line.partition(" ")
        if key == "usage_usec":
            stats["cpu_usec"] = int(value)
    quota, _, period = (read_text(f"{base}/cpu.max") or "max").strip().partition(" ")
    stats["cpu_max"] = int(quota) / int(period) if quota.isdigit() and period.isdigit() else None
    rbytes = wbytes = 0
    for line in (read_text(f"{base}/io.stat") or "").splitlines():
        for field in line.split()[1:]:
            key, _, value = field.partition("=")
            if key == "rbytes":
                rbytes += int(value)
            elif key == "wbytes":
                wbytes += int(value)
    stats["io_read"] = rbytes
    stats["io_write"] = wbytes
    return stats


def container_cgroup(cgroup_file: str) -> str | None:
    """libpod-<id>.scope from a /proc/<pid>/cgroup v2 line; limits are set there."""
    for line in cgroup_file.splitlines():
        if not line.startswith("0::"):
            continue
        parts = line[3:].split("/")
        for i in range(len(parts), 0, -1):
            name = parts[i - 1]
            if name.startswith("libpod-") and name.endswith(".scope") and "conmon" not in name:
                return "/".join(parts[:i])
        return line[3:]
    return None


# ---------------------------------------------------------------------------
# Podman and systemd


class Inventory:
    """Podman/systemd lookups that are too slow for every request."""

    def __init__(self) -> None:
        self.inspect: dict[str, dict] = {}
        self.storage: dict = {"at": None, "containers": {}, "paths": {}}
        self.lock = threading.Lock()
        self.inspect_lock = threading.Lock()

    def inspect_containers(self, ids: list[str]) -> dict[str, dict]:
        with self.inspect_lock:
            return self._inspect_containers(ids)

    def _inspect_containers(self, ids: list[str]) -> dict[str, dict]:
        missing = [i for i in ids if i not in self.inspect]
        if missing:
            try:
                for item in json.loads(run([PODMAN, "inspect", "--type", "container", *missing])):
                    host = item.get("HostConfig") or {}
                    self.inspect[item["Id"]] = {
                        "network_mode": host.get("NetworkMode", ""),
                        "mounts": [
                            {"type": m.get("Type"), "source": m.get("Source"),
                             "destination": m.get("Destination"), "rw": m.get("RW", False)}
                            for m in item.get("Mounts") or []
                        ],
                    }
            except (OSError, subprocess.SubprocessError, ValueError, KeyError):
                pass
        for stale in set(self.inspect) - set(ids):
            del self.inspect[stale]
        return {i: self.inspect.get(i, {}) for i in ids}

    def refresh_storage(self) -> None:
        sizes: dict[str, int] = {}
        try:
            for c in json.loads(run([PODMAN, "ps", "-a", "--size", "--format", "json"], timeout=300)):
                size = c.get("Size") or {}
                sizes[c["Id"]] = size.get("rwSize", 0)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError):
            pass
        paths = set()
        for meta in self.inspect_containers(list(sizes)).values():
            for m in meta.get("mounts", []):
                src = m.get("source") or ""
                if m.get("rw") and src.startswith("/") and not src.startswith(UNSIZED_PREFIXES):
                    paths.add(src)
        for unit in native_units():
            paths.update(unit_state_dirs(unit))
        measured = {}
        for path in sorted(paths):
            try:
                # -D follows /var/lib/<x> -> private/<x> (DynamicUser); -x stays on one fs.
                out = run(["du", "-sxDB1", "--", path], timeout=600)
                measured[path] = int(out.split()[0])
            except (OSError, subprocess.SubprocessError, ValueError, IndexError):
                pass
        with self.lock:
            self.storage = {"at": time.time(), "containers": sizes, "paths": measured}

    def storage_loop(self) -> None:
        while True:
            start = time.monotonic()
            try:
                self.refresh_storage()
            except Exception as exc:  # keep the loop alive; sizes are best effort
                print(f"storage refresh failed: {exc}", flush=True)
            time.sleep(max(60.0, STORAGE_INTERVAL - (time.monotonic() - start)))


INVENTORY = Inventory()
_state_dirs: dict[str, list[str]] = {}


def native_units() -> list[str]:
    """Running system services, excluding Podman's conmon units (reported as containers)."""
    try:
        names = os.listdir(f"{CGROUP_ROOT}/system.slice")
    except OSError:
        return []
    return sorted(
        n for n in names
        if n.endswith(".service") and not n.startswith("podman-")
        and read_int(f"{CGROUP_ROOT}/system.slice/{n}/memory.current")
    )


def unit_state_dirs(unit: str) -> list[str]:
    if unit not in _state_dirs:
        dirs = []
        try:
            value = run(["systemctl", "show", "--value", "-p", "StateDirectory", unit], timeout=5)
            dirs = [f"/var/lib/{d.split(':')[0]}" for d in value.split()]
        except (OSError, subprocess.SubprocessError):
            pass
        _state_dirs[unit] = [d for d in dirs if os.path.isdir(d)]
    return _state_dirs[unit]


def containers(storage: dict) -> list[dict]:
    listed = json.loads(run([PODMAN, "ps", "-a", "--format", "json"]))
    meta = INVENTORY.inspect_containers([c["Id"] for c in listed])
    host_netns = os.stat("/proc/1/ns/net").st_ino
    netns_owner: dict[int, str] = {}
    result = []
    for c in sorted(listed, key=lambda c: (c.get("Names") or [""])[0]):
        name = (c.get("Names") or [c["Id"][:12]])[0]
        info = meta.get(c["Id"], {})
        entry = {
            "id": c["Id"],
            "name": name,
            "image": c.get("Image", ""),
            "state": c.get("State", ""),
            "status": c.get("Status", ""),
            "health": container_health(c.get("Status", "")),
            "exit_code": c.get("ExitCode"),
            "started": c.get("StartedAt"),
            "network_mode": info.get("network_mode", ""),
            "storage": {
                "rw": storage["containers"].get(c["Id"]),
                "mounts": [
                    {"destination": m["destination"], "source": m["source"],
                     "bytes": storage["paths"].get(m["source"])}
                    for m in info.get("mounts", [])
                    if m["source"] in storage["paths"]
                ],
            },
        }
        pid = c.get("Pid") or 0
        if c.get("State") == "running" and pid > 0:
            cgroup = container_cgroup(read_text(f"/proc/{pid}/cgroup") or "")
            if cgroup:
                entry.update(cgroup_stats(cgroup))
            try:
                netns = os.stat(f"/proc/{pid}/ns/net").st_ino
            except OSError:
                netns = None
            if netns == host_netns:
                entry["net"] = "host"
            elif netns in netns_owner:
                entry["net"] = {"shared_with": netns_owner[netns]}
            elif netns is not None:
                netns_owner[netns] = name
                entry["net"] = parse_net_dev(read_text(f"/proc/{pid}/net/dev") or "", False)
        result.append(entry)
    return result


def services(storage: dict) -> list[dict]:
    result = []
    for unit in native_units():
        entry = {"unit": unit, **cgroup_stats(f"/system.slice/{unit}")}
        dirs = unit_state_dirs(unit)
        entry["storage"] = [
            {"path": d, "bytes": storage["paths"].get(d)} for d in dirs if d in storage["paths"]
        ]
        result.append(entry)
    return result


def container_health(status: str) -> str | None:
    """healthy / unhealthy / starting from Podman's status text; None without a check."""
    match = re.search(r"\((healthy|unhealthy|starting)\)", status)
    return match.group(1) if match else None


# ---------------------------------------------------------------------------
# Topology: unit dependencies and Caddy routes, refreshed every TOPOLOGY_TTL

DEPENDENCY_PROPS = ("Requires", "Requisite", "Wants", "BindsTo", "PartOf", "Upholds")


def parse_systemctl_show(text: str) -> dict[str, dict[str, str]]:
    """Blocks of `systemctl show -p Id,...` separated by blank lines, keyed by Id."""
    units: dict[str, dict[str, str]] = {}
    for block in text.split("\n\n"):
        props = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if props.get("Id"):
            units[props["Id"]] = props
    return units


def caddy_routes(config: dict) -> dict[str, list[int]]:
    """Host -> upstream ports on this machine, from Caddy's JSON config."""
    def dials(node) -> list[str]:
        if isinstance(node, dict):
            found = [u["dial"] for u in node.get("upstreams") or [] if isinstance(u, dict) and "dial" in u]
            return found + [d for k, v in node.items() if k != "upstreams" for d in dials(v)]
        if isinstance(node, list):
            return [d for v in node for d in dials(v)]
        return []

    routes: dict[str, list[int]] = {}
    servers = (((config.get("apps") or {}).get("http") or {}).get("servers") or {})
    for server in servers.values():
        for route in server.get("routes") or []:
            hosts = [h for m in route.get("match") or [] for h in m.get("host") or []]
            ports = []
            for dial in dials(route.get("handle")):
                host, _, port = dial.rpartition(":")
                if host.strip("[]") in ("127.0.0.1", "localhost", "::1") and port.isdigit():
                    ports.append(int(port))
            for host in hosts:
                routes.setdefault(host, [])
                routes[host] += [p for p in ports if p not in routes[host]]
    return routes


def parse_ss_listeners(text: str) -> dict[int, int]:
    """Local TCP port -> owning pid from `ss -ltnpH`."""
    owners: dict[int, int] = {}
    for line in text.splitlines():
        fields = line.split()
        if len(fields) < 6:
            continue
        port = fields[3].rpartition(":")[2]
        pid = re.search(r"pid=(\d+)", line)
        if port.isdigit() and pid:
            owners.setdefault(int(port), int(pid.group(1)))
    return owners


def unit_of_pid(pid: int) -> str | None:
    for line in (read_text(f"/proc/{pid}/cgroup") or "").splitlines():
        if line.startswith("0::"):
            for part in line[3:].split("/"):
                if part.endswith(".service"):
                    return part
    return None


def parse_caddy_metrics(text: str) -> dict[str, dict[str, int]]:
    """Per host: requests, 4xx and 5xx from caddy_http_request_duration_seconds_count.

    Caddy counts a request once per instrumented handler in its chain (subroute,
    reverse_proxy, ...), so only the busiest handler of each host is used.
    """
    per: dict[tuple[str, str], dict[str, int]] = {}
    for line in text.splitlines():
        if not line.startswith("caddy_http_request_duration_seconds_count{"):
            continue
        labels_text, _, value = line[len("caddy_http_request_duration_seconds_count{"):].rpartition("} ")
        labels = dict(re.findall(r'(\w+)="((?:[^"\\]|\\.)*)"', labels_text))
        try:
            count = int(float(value))
        except ValueError:
            continue
        key = (labels.get("host", ""), labels.get("handler", ""))
        bucket = per.setdefault(key, {"requests": 0, "status4": 0, "status5": 0})
        bucket["requests"] += count
        code = labels.get("code", "")
        if code.startswith("4"):
            bucket["status4"] += count
        elif code.startswith("5"):
            bucket["status5"] += count
    hosts: dict[str, dict[str, int]] = {}
    for (host, _), bucket in per.items():
        if host and bucket["requests"] > hosts.get(host, {}).get("requests", -1):
            hosts[host] = bucket
    return hosts


class Topology:
    def __init__(self) -> None:
        self.at = 0.0
        self.key: tuple = ()
        self.related: dict[str, set[str]] = {}
        self.restarts: dict[str, int] = {}
        self.hosts: dict[str, list[str]] = {}  # unit -> Caddy hosts proxied to it
        self.caddy = False
        self.lock = threading.Lock()

    def refresh(self, units: list[str]) -> None:
        key = tuple(sorted(units))
        with self.lock:
            if key == self.key and time.time() - self.at < TOPOLOGY_TTL:
                return
            self.key, self.at = key, time.time()
            wanted = set(units)
            related: dict[str, set[str]] = {u: set() for u in units}
            restarts: dict[str, int] = {}

            def link(a: str, b: str) -> None:
                if a != b and a in wanted and b in wanted:
                    related[a].add(b)
                    related[b].add(a)

            try:
                props = ",".join(("Id", "NRestarts") + DEPENDENCY_PROPS)
                shown = parse_systemctl_show(run(["systemctl", "show", "-p", props, "--", *units], timeout=10))
            except (OSError, subprocess.SubprocessError):
                shown = {}
            for unit, values in shown.items():
                if values.get("NRestarts", "").isdigit():
                    restarts[unit] = int(values["NRestarts"])
                for prop in DEPENDENCY_PROPS:
                    for other in values.get(prop, "").split():
                        link(unit, other)

            hosts: dict[str, list[str]] = {}
            self.caddy = "caddy.service" in wanted
            if self.caddy:
                try:
                    with urllib.request.urlopen(f"{CADDY_ADMIN}/config/", timeout=3) as r:
                        routes = caddy_routes(json.load(r) or {})
                    owners = parse_ss_listeners(run(["ss", "-ltnpH"], timeout=5))
                except (OSError, subprocess.SubprocessError, ValueError):
                    routes, owners = {}, {}
                for host, ports in routes.items():
                    for port in ports:
                        unit = unit_of_pid(owners[port]) if port in owners else None
                        if unit in wanted and unit != "caddy.service":
                            link("caddy.service", unit)
                            hosts.setdefault(unit, [])
                            if host not in hosts[unit]:
                                hosts[unit].append(host)
            self.related, self.restarts, self.hosts = related, restarts, hosts

    def http(self) -> dict[str, dict]:
        """Unit -> cumulative request counters of the hosts it serves; caddy.service gets all."""
        if not self.caddy:
            return {}
        try:
            with urllib.request.urlopen(f"{CADDY_ADMIN}/metrics", timeout=3) as r:
                per_host = parse_caddy_metrics(r.read().decode())
        except (OSError, ValueError):
            return {}
        if not per_host:
            return {}

        def total(hosts) -> dict:
            out = {"hosts": sorted(hosts), "requests": 0, "status4": 0, "status5": 0}
            for host in hosts:
                for k in ("requests", "status4", "status5"):
                    out[k] += per_host.get(host, {}).get(k, 0)
            return out

        result = {unit: total(hosts) for unit, hosts in self.hosts.items()}
        result["caddy.service"] = total([h for h in per_host if h != "_other"] or per_host)
        return result


TOPOLOGY = Topology()


def attach_topology(snap: dict) -> None:
    """Adds unit, related units, restarts and HTTP counters to containers and services."""
    for c in snap["containers"]:
        c["unit"] = f"podman-{c['name']}.service"
    workloads = snap["containers"] + snap["services"]
    try:
        TOPOLOGY.refresh([w["unit"] for w in workloads])
        http = TOPOLOGY.http()
    except Exception as exc:  # topology is decoration; never fail the snapshot
        snap["errors"].append(f"topology: {exc}")
        return
    for w in workloads:
        w["related"] = sorted(TOPOLOGY.related.get(w["unit"], ()))
        if w["unit"] in TOPOLOGY.restarts:
            w["restarts"] = TOPOLOGY.restarts[w["unit"]]
        if w["unit"] in http:
            w["http"] = http[w["unit"]]


# ---------------------------------------------------------------------------
# Snapshots

_snapshot_lock = threading.Lock()
_snapshot: tuple[float, dict] | None = None


def node_snapshot() -> dict:
    global _snapshot
    with _snapshot_lock:
        now = time.time()
        if _snapshot and now - _snapshot[0] < SNAPSHOT_TTL:
            return _snapshot[1]
        with INVENTORY.lock:
            storage = INVENTORY.storage
        snap: dict = {
            "at": now,
            "system": system_info(),
            "cpu": cpu_seconds(),
            "memory": parse_meminfo(read_text("/proc/meminfo") or ""),
            "filesystems": filesystems(),
            "interfaces": parse_net_dev(read_text("/proc/net/dev") or "", True),
            "services": services(storage),
            "storage_at": storage["at"],
            "errors": [],
        }
        try:
            snap["containers"] = containers(storage)
        except (OSError, subprocess.SubprocessError, ValueError) as exc:
            snap["containers"] = []
            snap["errors"].append(f"podman: {exc}")
        attach_topology(snap)
        _snapshot = (now, snap)
        return snap


def tailnet_peers() -> list[dict]:
    status = json.loads(run([TAILSCALE, "status", "--json"], timeout=10))
    peers = []
    for key, node in [("self", status.get("Self") or {})] + [
        ("peer", p) for p in (status.get("Peer") or {}).values()
    ]:
        ips = node.get("TailscaleIPs") or []
        peers.append({
            "self": key == "self",
            "name": node.get("HostName", ""),
            "dns": (node.get("DNSName") or "").rstrip("."),
            "ipv4": next((ip for ip in ips if "." in ip), None),
            "tags": node.get("Tags") or [],
            "os": node.get("OS", ""),
            "online": bool(node.get("Online")) or key == "self",
            "last_seen": node.get("LastSeen"),
            "rx": node.get("RxBytes", 0),
            "tx": node.get("TxBytes", 0),
        })
    return peers


def fetch_peer(peer: dict) -> dict:
    entry = {"name": peer["name"], "address": peer["ipv4"], "tailnet": peer}
    if not peer["online"]:
        return {**entry, "ok": False, "error": "tailnet offline"}
    if not peer["ipv4"]:
        return {**entry, "ok": False, "error": "no IPv4 address"}
    try:
        with urllib.request.urlopen(f"http://{peer['ipv4']}:{PEER_PORT}/v1/node", timeout=6) as r:
            return {**entry, "ok": True, "data": json.load(r)}
    except (OSError, ValueError) as exc:
        return {**entry, "ok": False, "error": f"agent unreachable: {exc}"}


def cluster_snapshot() -> dict:
    result: dict = {"at": time.time(), "collector": os.uname().nodename, "errors": []}
    try:
        peers = tailnet_peers()
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        result["errors"].append(f"tailscale: {exc}")
        peers = [{"self": True, "name": os.uname().nodename, "dns": "", "ipv4": None,
                  "tags": [], "os": "linux", "online": True, "last_seen": None, "rx": 0, "tx": 0}]
    local = next(p for p in peers if p["self"]) if any(p["self"] for p in peers) else None
    others = [p for p in peers if not p["self"]]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        remote = list(pool.map(fetch_peer, others))
    nodes = [{"name": os.uname().nodename, "address": local and local["ipv4"],
              "tailnet": local, "ok": True, "data": node_snapshot()}] + remote
    result["nodes"] = nodes
    return result


# ---------------------------------------------------------------------------
# HTTP


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "cluster-agent"

    def do_GET(self) -> None:  # noqa: N802
        try:
            if self.path == "/v1/node":
                body = node_snapshot()
            elif self.path == "/v1/cluster" and COLLECT:
                body = cluster_snapshot()
            elif self.path == "/healthz":
                body = {"ok": True}
            else:
                self.send_error(404)
                return
            payload = json.dumps(body, separators=(",", ":")).encode()
        except Exception as exc:  # report, do not crash the server thread
            self.send_error(500, explain=str(exc))
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def address_string(self) -> str:
        return "-"

    def log_message(self, fmt: str, *args) -> None:
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def listening_sockets() -> list[socket.socket]:
    """Sockets passed by systemd, or AGENT_LISTEN=host:port for local testing."""
    if os.environ.get("LISTEN_PID") == str(os.getpid()):
        count = int(os.environ.get("LISTEN_FDS", "0"))
        return [socket.socket(fileno=3 + i) for i in range(count)]
    host, _, port = os.environ.get("AGENT_LISTEN", "127.0.0.1:9925").rpartition(":")
    sock = socket.create_server((host, int(port)))
    return [sock]


def main() -> None:
    threading.Thread(target=INVENTORY.storage_loop, daemon=True).start()
    servers = []
    for sock in listening_sockets():
        server = Server(None, Handler, bind_and_activate=False)
        server.socket.close()
        server.socket = sock
        server.server_address = sock.getsockname()
        servers.append(server)
    for server in servers[1:]:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    servers[0].serve_forever()


if __name__ == "__main__":
    main()
