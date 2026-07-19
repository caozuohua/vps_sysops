#!/usr/bin/env python3
"""stdio MCP adapter for the private Hermes A2A Bridge.

The Hermes process starts this file as an MCP child. The adapter keeps no
model or shell capability; it only calls the peer Bridge over Tailscale.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.request
import uuid


REMOTE = os.environ.get("A2A_REMOTE_URL", "").rstrip("/")
CALLBACK = os.environ.get("A2A_CALLBACK_URL", "")
TOKEN_FILE = os.environ.get("A2A_TOKEN_FILE", "")


def token() -> str:
    if os.environ.get("A2A_TOKEN"):
        return os.environ["A2A_TOKEN"]
    if TOKEN_FILE:
        try:
            for line in open(TOKEN_FILE, encoding="utf-8"):
                if line.startswith("A2A_TOKEN="):
                    return line.rstrip("\n").split("=", 1)[1]
        except OSError:
            pass
    return ""


def signing_key() -> str:
    if os.environ.get("A2A_SIGNING_KEY"):
        return os.environ["A2A_SIGNING_KEY"]
    if TOKEN_FILE:
        try:
            for line in open(TOKEN_FILE, encoding="utf-8"):
                if line.startswith("A2A_SIGNING_KEY="):
                    return line.rstrip("\n").split("=", 1)[1]
        except OSError:
            pass
    return ""


def signed_headers(body: bytes) -> dict[str, str]:
    timestamp = str(int(time.time()))
    digest = hmac.new(signing_key().encode(), timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
    return {"X-A2A-Timestamp": timestamp, "X-A2A-Signature": f"sha256={digest}", "X-A2A-Request-ID": str(uuid.uuid4())}


def call(method: str, params: dict, timeout: float = 30) -> object:
    if not REMOTE or not token():
        raise RuntimeError("A2A_REMOTE_URL or A2A_TOKEN_FILE is not configured")
    body = json.dumps({"jsonrpc": "2.0", "id": "mcp", "method": method, "params": params}).encode()
    _tok = token()
    headers = {"Authorization": f"Bearer {_tok}", "Content-Type": "application/json"}
    headers.update(signed_headers(body))
    request = urllib.request.Request(
        REMOTE,
        data=body,
        method="POST",
        headers=headers,
    )
    with urllib.request.build_opener(urllib.request.HTTPHandler).open(request, timeout=timeout) as response:
        data = json.loads(response.read())
    if "error" in data:
        raise RuntimeError(data["error"].get("message", str(data["error"])))
    return data.get("result")


def get_task(task_id: str) -> dict:
    return call("tasks/get", {"id": task_id})


TOOLS = [
    {
        "name": "a2a_agent_card",
        "description": "Read the remote Hermes agent capabilities before delegating.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "a2a_delegate_task",
        "description": "Submit a bounded task to the remote Hermes agent. Use for research, review, coding, or independent verification.",
        "inputSchema": {"type": "object", "properties": {
            "message": {"type": "string", "description": "Self-contained task and desired output format."},
            "context_id": {"type": "string", "description": "Reuse to continue a previous delegation."},
            "role": {"type": "string", "description": "Policy role, usually default."},
        }, "required": ["message"], "additionalProperties": False},
    },
    {
        "name": "a2a_get_task",
        "description": "Get the current status and result of a delegated task.",
        "inputSchema": {"type": "object", "properties": {"task_id": {"type": "string"}}, "required": ["task_id"], "additionalProperties": False},
    },
    {
        "name": "a2a_wait_task",
        "description": "Wait for a delegated task to finish and return its final result.",
        "inputSchema": {"type": "object", "properties": {
            "task_id": {"type": "string"}, "timeout_seconds": {"type": "integer", "minimum": 1, "maximum": 900},
        }, "required": ["task_id"], "additionalProperties": False},
    },
    {
        "name": "a2a_cancel_task",
        "description": "Cancel a running delegated task.",
        "inputSchema": {"type": "object", "properties": {"task_id": {"type": "string"}}, "required": ["task_id"], "additionalProperties": False},
    },
    {
        "name": "a2a_upload_artifact",
        "description": "Upload a small base64-encoded artifact to a delegated task (maximum 10 MB).",
        "inputSchema": {"type": "object", "properties": {
            "task_id": {"type": "string"}, "filename": {"type": "string"}, "content_base64": {"type": "string"}, "mime_type": {"type": "string"},
        }, "required": ["task_id", "filename", "content_base64"], "additionalProperties": False},
    },
    {
        "name": "a2a_download_artifact",
        "description": "Download a task artifact as base64 (use only for small files).",
        "inputSchema": {"type": "object", "properties": {
            "task_id": {"type": "string"}, "artifact_id": {"type": "string"},
        }, "required": ["task_id", "artifact_id"], "additionalProperties": False},
    },
]


def result(value: object, error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": json.dumps(value, ensure_ascii=False)}], "isError": error}


def handle_tool(name: str, args: dict) -> dict:
    if name == "a2a_agent_card":
        with urllib.request.urlopen(f"{REMOTE.rsplit('/a2a', 1)[0]}/.well-known/agent-card.json", timeout=20) as response:
            return result(json.loads(response.read()))
    if name == "a2a_delegate_task":
        params = dict(args)
        # Older clients may still send this field. The deployed peers run A2A
        # workers in safe mode, so forwarding it can only trigger a policy
        # rejection; silently discard it at the adapter boundary.
        params.pop("toolsets", None)
        if CALLBACK:
            params["callbackUrl"] = CALLBACK
        return result(call("message/send", params))
    if name == "a2a_get_task":
        return result(get_task(args["task_id"]))
    if name == "a2a_wait_task":
        deadline = time.time() + min(int(args.get("timeout_seconds", 900)), 900)
        while True:
            task = get_task(args["task_id"])
            state = task.get("status", {}).get("state")
            if state in {"completed", "failed", "canceled", "cancelled"} or time.time() >= deadline:
                return result(task)
            time.sleep(3)
    if name == "a2a_cancel_task":
        return result(call("tasks/cancel", {"id": args["task_id"]}))
    if name == "a2a_upload_artifact":
        task_id = args["task_id"]
        body = json.dumps({k: args[k] for k in ("filename", "content_base64", "mime_type") if k in args}).encode()
        headers = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}
        headers.update(signed_headers(body))
        request = urllib.request.Request(
            f"{REMOTE.rsplit('/a2a', 1)[0]}/a2a/v1/tasks/{task_id}/artifacts",
            data=body, method="POST", headers=headers,
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return result(json.loads(response.read()))
    if name == "a2a_download_artifact":
        task_id = args["task_id"]
        artifact_id = args["artifact_id"]
        request = urllib.request.Request(
            f"{REMOTE.rsplit('/a2a', 1)[0]}/a2a/v1/tasks/{task_id}/artifacts/{artifact_id}",
            headers={"Authorization": f"Bearer {token()}"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(2 * 1024 * 1024 + 1)
            if len(data) > 2 * 1024 * 1024:
                raise RuntimeError("artifact exceeds MCP adapter 2 MiB response limit")
            return result({"artifact_id": artifact_id, "content_base64": base64.b64encode(data).decode()})
    raise RuntimeError(f"unknown tool: {name}")


def main() -> None:
    for raw in sys.stdin:
        try:
            request = json.loads(raw)
            method = request.get("method")
            if method == "initialize":
                response = {"jsonrpc": "2.0", "id": request.get("id"), "result": {
                    "protocolVersion": request.get("params", {}).get("protocolVersion", "2024-11-05"),
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "hermes-a2a-mcp", "version": "0.1.0"},
                }}
            elif method == "tools/list":
                response = {"jsonrpc": "2.0", "id": request.get("id"), "result": {"tools": TOOLS}}
            elif method == "tools/call":
                try:
                    response = {"jsonrpc": "2.0", "id": request.get("id"), "result": handle_tool(request.get("params", {}).get("name", ""), request.get("params", {}).get("arguments", {}))}
                except Exception as exc:
                    response = {"jsonrpc": "2.0", "id": request.get("id"), "result": result({"error": str(exc)}, True)}
            elif method in ("notifications/initialized", "notifications/cancelled"):
                continue
            elif method == "ping":
                response = {"jsonrpc": "2.0", "id": request.get("id"), "result": {}}
            else:
                response = {"jsonrpc": "2.0", "id": request.get("id"), "error": {"code": -32601, "message": "method not found"}}
            sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
            sys.stdout.flush()
        except Exception as exc:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32603, "message": str(exc)}}) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
