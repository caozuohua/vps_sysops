#!/usr/bin/env python3
"""Reproduce EXACTLY how Hermes gateway builds the MCP subprocess env,
then call a2a_delegate_task to see if 403 reproduces."""
import json, subprocess, sys, time, os, select

# Replicate mcp_tool._build_safe_env + user_env
_SAFE_ENV_KEYS = frozenset({"PATH","HOME","USER","LANG","LC_ALL","TERM","SHELL","TMPDIR"})
def build_safe_env(user_env):
    env = {}
    for k, v in os.environ.items():
        if k in _SAFE_ENV_KEYS or k.startswith("XDG_"):
            env[k] = v
    if user_env:
        env.update(user_env)
    return env

user_env = {
    "A2A_REMOTE_URL": "http://100.101.90.114:8765/a2a",
    "A2A_CALLBACK_URL": "http://100.87.159.14:8765/a2a/v1/events",
    "A2A_TOKEN_FILE": "/home/caozuohua/.config/hermes-a2a-bridge.env",
}
ENV = build_safe_env(user_env)
print("ENV keys passed to subprocess:", sorted(ENV.keys()), file=sys.stderr)

proc = subprocess.Popen(
    ["/usr/bin/python3", "/home/caozuohua/vps_sysops/a2a-bridge/a2a_mcp.py"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    env=ENV, text=True, bufsize=1,
)

def rpc(method, params=None, rid="1", timeout=25):
    msg = {"jsonrpc": "2.0", "id": rid, "method": method}
    if params is not None:
        msg["params"] = params
    proc.stdin.write(json.dumps(msg) + "\n"); proc.stdin.flush()
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([proc.stdout], [], [], 1)
        if r:
            line = proc.stdout.readline()
            if not line: break
            try: obj = json.loads(line)
            except Exception: continue
            if obj.get("id") == rid or "result" in obj or "error" in obj:
                return obj
    return {"timeout": True}

rpc("initialize", {"protocolVersion": "2024-11-05"})
res = rpc("tools/call", {"name": "a2a_delegate_task",
    "arguments": {"message": "probe SAFE_ENV repro: echo SAFE_ENV_OK"}}, rid="2")
print("delegate result:", json.dumps(res)[:400], flush=True)
time.sleep(1)
proc.stderr.flush()
err = proc.stderr.read()
print("STDERR:", err[:800], file=sys.stderr)
proc.terminate()
