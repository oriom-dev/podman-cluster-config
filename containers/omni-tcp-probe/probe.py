"""Temporary TCP capture endpoint: log incoming bytes, never send device commands."""
import asyncio
import contextlib
import itertools
import json
import os
from datetime import datetime, timezone

PORT = int(os.environ.get("PORT", "9682"))
MAX_CONNECTIONS = int(os.environ.get("MAX_CONNECTIONS", "8"))
MAX_BYTES = int(os.environ.get("MAX_BYTES", "65536"))
IDLE_SECONDS = float(os.environ.get("IDLE_SECONDS", "30"))
MAX_SECONDS = float(os.environ.get("MAX_SECONDS", "120"))
active = 0
connection_ids = itertools.count(1)


def log(event, **fields):
    print(json.dumps({
        "time": datetime.now(timezone.utc).isoformat(),
        "event": event,
        **fields,
    }), flush=True)


async def handle(reader, writer):
    global active
    connection = next(connection_ids)
    peer = writer.get_extra_info("peername")
    admitted = active < MAX_CONNECTIONS
    total = 0
    reason = "eof"
    try:
        if not admitted:
            log("reject", connection=connection, peer=peer, reason="connection_limit")
            return
        active += 1
        log("connect", connection=connection, peer=peer)
        deadline = asyncio.get_running_loop().time() + MAX_SECONDS
        while total < MAX_BYTES:
            remaining = deadline - asyncio.get_running_loop().time()
            if remaining <= 0:
                reason = "lifetime_limit"
                break
            try:
                data = await asyncio.wait_for(
                    reader.read(min(4096, MAX_BYTES - total)),
                    timeout=min(IDLE_SECONDS, remaining),
                )
            except asyncio.TimeoutError:
                reason = "lifetime_limit" if remaining <= IDLE_SECONDS else "idle_timeout"
                break
            if not data:
                break
            total += len(data)
            log("data", connection=connection, bytes=len(data), total_bytes=total, hex=data.hex())
        else:
            reason = "byte_limit"
    except ConnectionError as error:
        reason = type(error).__name__
    finally:
        if admitted:
            active -= 1
            log("disconnect", connection=connection, peer=peer, total_bytes=total, reason=reason)
        writer.close()
        with contextlib.suppress(ConnectionError, asyncio.TimeoutError):
            await asyncio.wait_for(writer.wait_closed(), timeout=2)


async def main():
    if min(PORT, MAX_CONNECTIONS, MAX_BYTES, IDLE_SECONDS, MAX_SECONDS) <= 0:
        raise ValueError("Port and capture limits must be positive")
    server = await asyncio.start_server(handle, "0.0.0.0", PORT, limit=8192)
    log("listen", port=PORT, max_connections=MAX_CONNECTIONS, max_bytes=MAX_BYTES,
        idle_seconds=IDLE_SECONDS, max_seconds=MAX_SECONDS)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
