#!/usr/bin/env python3
"""Minimal MCP stdio client to reproduce the gateway's exact call path."""
import json, subprocess, sys, time, os

ENV = dict(os.environ)
ENV["A2A_REMOTE_URL"] = "http://100.101.90.114:8765/a2a"
ENV["A2A_CALLBACK_URL"] = "http://100.115.42.83:8765/a2a/v1/events"
ENV["A2A_TOKEN_FILE"] = "/home/caozuohua/.config/hermes-a2a-bridge.env"

proc = subprocess.Popen(
    ["/usr/bin/python3", "/home/caozuohua/vps_sysops/a2a-bridge/a2a_mcp.py"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    env=ENV, text=True, bufsize=1,
)

import select

def rpc(method, params=None, rid="1", timeout=25):
    msg = {"jsonrpc": "2.0", "id": rid, "method": method}
    if params is not None:
        msg["params"] = params
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    # read until we get a line with matching id (skip stray output)
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([proc.stdout], [], [], 1)
        if r:
            line = proc.stdout.readline()
            if not line:
                break
            try:
                obj = json.loads(line)
            except Exception:
                sys.stderr.write("NONJSON: " + line[:200] + "\n")
                continue
            if obj.get("id") == rid or "result" in obj or "error" in obj:
                return obj
        else:
            sys.stderr.write(f"[{method}] no data within 1s, waiting...\n")
    return {"timeout": True}

print("initialize:", json.dumps(rpc("initialize", {"protocolVersion": "2024-11-05"}))[:150], flush=True)
sys.stderr.write("sent initialize\n")
print("tools/list:", json.dumps(rpc("tools/list"))[:120], flush=True)
res = rpc("tools/call", {"name": "a2a_delegate_task",
    "arguments": {"message": "probe from mcp_probe.py: echo PROBE_OK"}}, rid="2")
print("delegate result:", json.dumps(res)[:400], flush=True)
# drain stderr
time.sleep(1)
proc.terminate()
