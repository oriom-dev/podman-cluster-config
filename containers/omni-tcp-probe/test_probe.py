import asyncio
import unittest
from unittest.mock import patch

import probe


class ProbeTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.events = []
        self.connections = []
        self.tasks = set()
        self.logging = patch.object(probe, "log", lambda event, **fields: self.events.append({"event": event, **fields}))
        self.logging.start()
        self.server = await asyncio.start_server(self.handle, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]

    async def handle(self, reader, writer):
        task = asyncio.current_task()
        self.tasks.add(task)
        try:
            await probe.handle(reader, writer)
        finally:
            self.tasks.remove(task)

    async def connect(self):
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        self.connections.append(writer)
        return reader, writer

    async def asyncTearDown(self):
        self.server.close()
        await self.server.wait_closed()
        for writer in self.connections:
            writer.close()
            await writer.wait_closed()
        if self.tasks:
            await asyncio.wait_for(asyncio.gather(*list(self.tasks)), timeout=3)
        self.logging.stop()
        self.assertEqual(probe.active, 0)

    async def test_capture_exact_bytes_without_reply(self):
        with patch.object(probe, "MAX_BYTES", 4):
            reader, writer = await self.connect()
            writer.write(b"\x00\xffABextra")
            await writer.drain()
            self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        data = [event for event in self.events if event["event"] == "data"]
        self.assertEqual(b"".join(bytes.fromhex(event["hex"]) for event in data), b"\x00\xffAB")
        self.assertEqual(self.events[-1]["reason"], "byte_limit")

    async def test_idle_connection_is_closed(self):
        with patch.object(probe, "IDLE_SECONDS", 0.05):
            reader, _ = await self.connect()
            self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        self.assertEqual(self.events[-1]["reason"], "idle_timeout")

    async def test_connection_limit_rejects_extra_client(self):
        with patch.object(probe, "MAX_CONNECTIONS", 1):
            await self.connect()
            reader, _ = await self.connect()
            self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        self.assertTrue(any(event["event"] == "reject" for event in self.events))

    async def test_lifetime_limit_is_enforced(self):
        with patch.object(probe, "MAX_SECONDS", 0.05):
            reader, _ = await self.connect()
            self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        self.assertEqual(self.events[-1]["reason"], "lifetime_limit")


if __name__ == "__main__":
    unittest.main()
