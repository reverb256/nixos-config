#!/usr/bin/env python3
"""nexus-exec-daemon: Remote command execution daemon for Nexus."""
import asyncio, json, os, socket, subprocess, time, signal

SOCKET_PATH = os.environ.get("NEXUS_EXEC_SOCKET", "/run/nexus-exec/exec.sock")
SHUTDOWN_EVENT = asyncio.Event()

async def handle_client(reader, writer):
    try:
        data = await reader.readline()
        if not data: return
        try:
            req = json.loads(data.decode("utf-8").strip())
        except json.JSONDecodeError as e:
            writer.write((json.dumps({"error": f"invalid JSON: {e}"}) + "\n").encode("utf-8"))
            await writer.drain(); return
        req_id = req.get("id", "0"); cmd = req.get("cmd", "")
        cwd = req.get("cwd", os.environ.get("HOME", "/"))
        env_overrides = req.get("env", {})
        if not cmd:
            writer.write((json.dumps({"id": req_id, "error": "empty cmd"}) + "\n").encode("utf-8"))
            await writer.drain(); return
        env = os.environ.copy(); env.update(env_overrides)
        start = time.monotonic()
        try:
            proc = await asyncio.create_subprocess_shell(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                cwd=cwd, env=env, shell=True)
            stdout, stderr = await proc.communicate()
            dur = int((time.monotonic() - start) * 1000)
            result = {"id": req_id, "exit": proc.returncode,
                "stdout": stdout.decode("utf-8", errors="replace"),
                "stderr": stderr.decode("utf-8", errors="replace"), "duration_ms": dur}
            writer.write((json.dumps(result) + "\n").encode("utf-8"))
            await writer.drain()
        except Exception as e:
            writer.write((json.dumps({"id": req_id, "error": str(e)}) + "\n").encode("utf-8"))
            await writer.drain()
    except: pass
    finally:
        try: writer.close(); await writer.wait_closed()
        except: pass

async def main():
    try: os.unlink(SOCKET_PATH)
    except OSError: pass
    os.makedirs(os.path.dirname(SOCKET_PATH), exist_ok=True)
    server = await asyncio.start_unix_server(handle_client, path=SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o600)
    print(f"nexus-exec: listening on {SOCKET_PATH}", flush=True)
    async with server: await SHUTDOWN_EVENT.wait()

def handle_signal(signum, frame): SHUTDOWN_EVENT.set()
signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)
try: asyncio.run(main())
except KeyboardInterrupt: pass
