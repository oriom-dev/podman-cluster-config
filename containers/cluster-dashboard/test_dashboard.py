"""Unit tests for the agent's parsers and the dashboard's rate calculation.

  python3 -m unittest -v test_dashboard.py
"""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent / "app"))
import agent  # noqa: E402
import server  # noqa: E402


class AgentParsers(unittest.TestCase):
    def test_container_cgroup_uses_libpod_scope(self):
        text = "0::/machine.slice/libpod-abc.scope/container\n"
        self.assertEqual(agent.container_cgroup(text), "/machine.slice/libpod-abc.scope")
        self.assertEqual(agent.container_cgroup("0::/system.slice/x.service\n"), "/system.slice/x.service")
        self.assertIsNone(agent.container_cgroup(""))

    def test_mounts_skip_virtual_readonly_and_bind_duplicates(self):
        text = "\n".join([
            "/dev/vda2 / ext4 rw,relatime 0 0",
            "/dev/vda2 /nix/store ext4 ro,relatime 0 0",
            "/dev/vda2 /var/lib/containers/storage/overlay ext4 rw 0 0",
            "/dev/sdb /srv/data ext4 rw,nofail 0 0",
            "/dev/sdc /usr/src/headers ext4 ro 0 0",
            "tmpfs /run tmpfs rw 0 0",
        ])
        self.assertEqual(agent.parse_mounts(text), [
            ("/dev/vda2", "/", "ext4"),
            ("/dev/sdb", "/srv/data", "ext4"),
        ])

    def test_net_dev(self):
        text = (
            "Inter-|   Receive |  Transmit\n"
            " face |bytes packets errs drop fifo frame compressed multicast|bytes\n"
            "    lo: 10 1 0 0 0 0 0 0 10 1 0 0 0 0 0 0\n"
            "  eth0: 100 1 0 0 0 0 0 0 200 1 0 0 0 0 0 0\n"
            "veth1: 5 1 0 0 0 0 0 0 6 1 0 0 0 0 0 0\n"
        )
        self.assertEqual(agent.parse_net_dev(text, True), {"eth0": {"rx": 100, "tx": 200}})
        self.assertEqual(set(agent.parse_net_dev(text, False)), {"eth0", "veth1"})

    def test_meminfo(self):
        mem = agent.parse_meminfo("MemTotal: 1024 kB\nMemAvailable: 512 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n")
        self.assertEqual(mem, {"total": 1048576, "available": 524288, "swap_total": 0, "swap_free": 0})

    def test_container_health_from_status(self):
        self.assertEqual(agent.container_health("Up 7 days (healthy)"), "healthy")
        self.assertEqual(agent.container_health("Up 3 seconds (starting)"), "starting")
        self.assertEqual(agent.container_health("Up 1 hour (unhealthy)"), "unhealthy")
        self.assertIsNone(agent.container_health("Up 3 hours"))

    def test_systemctl_show_blocks(self):
        text = "Id=a.service\nRequires=b.service sysinit.target\nNRestarts=2\n\nId=b.service\nPartOf=\n"
        units = agent.parse_systemctl_show(text)
        self.assertEqual(units["a.service"]["NRestarts"], "2")
        self.assertEqual(units["b.service"]["PartOf"], "")

    def test_caddy_routes_map_hosts_to_local_ports(self):
        config = {"apps": {"http": {"servers": {"srv0": {"routes": [
            {"match": [{"host": ["a.example"]}], "handle": [{"handler": "subroute", "routes": [
                {"handle": [{"handler": "reverse_proxy", "upstreams": [{"dial": "127.0.0.1:3000"}]}]}]}]},
            {"match": [{"host": ["b.example", "c.example"]}], "handle": [{"handler": "reverse_proxy",
                "upstreams": [{"dial": "localhost:2583"}, {"dial": "10.0.0.5:80"}]}]},
            {"match": [{"host": ["static.example"]}], "handle": [{"handler": "file_server"}]},
        ]}}}}}
        self.assertEqual(agent.caddy_routes(config),
                         {"a.example": [3000], "b.example": [2583], "c.example": [2583], "static.example": []})

    def test_ss_listeners(self):
        text = ('LISTEN 0 4096 127.0.0.1:3000 0.0.0.0:* users:(("conmon",pid=566000,fd=5))\n'
                'LISTEN 0 128 [::]:22 [::]:* users:(("sshd",pid=900,fd=4))\n')
        self.assertEqual(agent.parse_ss_listeners(text), {3000: 566000, 22: 900})

    def test_caddy_metrics_use_busiest_handler_per_host(self):
        m = "caddy_http_request_duration_seconds_count"
        text = "\n".join([
            "# TYPE caddy_http_request_duration_seconds histogram",
            f'{m}{{code="200",handler="subroute",host="a.example",method="GET",server="srv0"}} 90',
            f'{m}{{code="404",handler="subroute",host="a.example",method="GET",server="srv0"}} 6',
            f'{m}{{code="502",handler="subroute",host="a.example",method="GET",server="srv0"}} 4',
            f'{m}{{code="200",handler="reverse_proxy",host="a.example",method="GET",server="srv0"}} 90',
            f'{m}{{code="502",handler="reverse_proxy",host="a.example",method="GET",server="srv0"}} 4',
            f'{m}{{code="200",handler="file_server",host="b.example",method="GET",server="srv0"}} 1e+03',
        ])
        self.assertEqual(agent.parse_caddy_metrics(text), {
            "a.example": {"requests": 100, "status4": 6, "status5": 4},
            "b.example": {"requests": 1000, "status4": 0, "status5": 0},
        })


class DashboardRates(unittest.TestCase):
    def test_rate_ignores_resets_and_gaps(self):
        self.assertEqual(server.rate(150, 100, 10), 5)
        self.assertIsNone(server.rate(50, 100, 10))
        self.assertIsNone(server.rate(150, None, 10))
        self.assertIsNone(server.rate(150, 100, 0))

    def test_workload_rates_use_agent_sample_time(self):
        state = server.State()
        item = {"id": "c1", "cpu_usec": 1_000_000, "io_read": 0, "io_write": 0,
                "memory": 10, "net": {"eth0": {"rx": 0, "tx": 0}}}
        state.workload_view("n", item, "container", at=100, now=1000)
        item2 = {**item, "cpu_usec": 3_000_000, "net": {"eth0": {"rx": 1000, "tx": 500}}}
        view = state.workload_view("n", item2, "container", at=110, now=1003)
        self.assertAlmostEqual(view["cpu"], 0.2)
        self.assertEqual(view["net_rx_rate"], 100)
        self.assertEqual(view["net_tx_rate"], 50)

    def test_shared_netns_has_no_rates(self):
        state = server.State()
        view = state.workload_view("n", {"id": "c2", "net": {"shared_with": "x"}}, "container", 1, 1)
        self.assertNotIn("net_rx_rate", view)

    def test_failed_poll_keeps_last_state(self):
        state = server.State()
        state.current = {"updated": 1, "nodes": [{"name": "a"}]}
        with patch.object(server, "fetch_cluster", side_effect=OSError("down")):
            state.update()
        self.assertEqual(state.current["nodes"], [{"name": "a"}])
        self.assertIn("down", state.current["error"])

    def test_http_rates_and_window_ratios(self):
        state = server.State()
        base = {"id": "c1", "name": "c1", "restarts": 3,
                "http": {"hosts": ["a.example"], "requests": 1000, "status4": 10, "status5": 5}}
        state.workload_view("n", base, "container", 100.0, 100.0)
        later = {**base, "restarts": 4, "http": {**base["http"], "requests": 1100, "status4": 20, "status5": 7}}
        view = state.workload_view("n", later, "container", 110.0, 110.0)
        self.assertEqual(view["http"]["requests_rate"], 10.0)
        self.assertAlmostEqual(view["http"]["ratio5_1h"], 0.02)
        self.assertAlmostEqual(view["http"]["ratio4_1h"], 0.1)
        self.assertEqual(view["restarts_1h"], 1)


if __name__ == "__main__":
    unittest.main()
