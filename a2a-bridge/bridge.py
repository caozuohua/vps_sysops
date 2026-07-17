#!/usr/bin/env python3
"""Private Hermes A2A server: JSON-RPC, tasks, SSE, callbacks and artifacts."""

from __future__ import annotations

import base64
import hashlib
import hmac
import ipaddress
import json
import mimetypes
import os
import queue
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import HTTPHandler, Request, build_opener

MAX_BODY = 64 * 1024
MAX_ARTIFACT = 10 * 1024 * 1024
MAX_MESSAGE = 32 * 1024
MAX_HISTORY = 12
MAX_PENDING_TASKS = int(os.environ.get("A2A_MAX_PENDING_TASKS", "8"))
TASK_TTL = int(os.environ.get("A2A_TASK_TTL", "604800"))
CONTEXT_TTL = int(os.environ.get("A2A_CONTEXT_TTL", "2592000"))
CALLBACK_RETRIES = int(os.environ.get("A2A_CALLBACK_RETRIES", "3"))
CALLBACK_TIMEOUT = int(os.environ.get("A2A_CALLBACK_TIMEOUT", "5"))
REQUIRE_SIGNATURE = os.environ.get("A2A_REQUIRE_SIGNATURE", "true").lower() == "true"
SIGNATURE_WINDOW = int(os.environ.get("A2A_SIGNATURE_WINDOW", "300"))
TIMEOUT = int(os.environ.get("A2A_TIMEOUT", "900"))
TOKEN = os.environ.get("A2A_TOKEN", "")
CALLBACK_TOKEN = os.environ.get("A2A_CALLBACK_TOKEN", TOKEN)
SIGNING_KEY = os.environ.get("A2A_SIGNING_KEY", "")
CALLBACK_SIGNING_KEY = os.environ.get("A2A_CALLBACK_SIGNING_KEY", SIGNING_KEY)
AGENT_NAME = os.environ.get("A2A_AGENT_NAME", "hermes")
AGENT_VERSION = os.environ.get("A2A_AGENT_VERSION", "0.3.0")
HOST = os.environ.get("A2A_BIND", "127.0.0.1")
PORT = int(os.environ.get("A2A_PORT", "8765"))
STATE_DIR = Path(os.environ.get("A2A_STATE_DIR", "./state"))
HERMES_EXEC = os.environ.get("A2A_HERMES_EXEC", "hermes")
HERMES_ARGS = json.loads(os.environ.get("A2A_HERMES_ARGS", "[]"))
ENABLE_TOOLS = os.environ.get("A2A_ENABLE_TOOLS", "false").lower() == "true"
try:
    TOOL_POLICY = json.loads(os.environ.get("A2A_TOOL_POLICY", '{"default":{"toolsets":[]}}'))
except json.JSONDecodeError:
    TOOL_POLICY = {"default": {"toolsets": []}}
PEERS = {x.strip() for x in os.environ.get("A2A_PEERS", "").split(",") if x.strip()}

STORE_LOCK = threading.RLock()
PROCESS_LOCK = threading.RLock()
PROCESSES: dict[str, subprocess.Popen[str]] = {}
CANCEL_REQUESTS: set[str] = set()
SUBSCRIBERS: dict[str, list[queue.Queue[dict]]] = {}
WORKER_LIMIT = threading.BoundedSemaphore(1)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def safe_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", name)[:120] or "artifact.bin"


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.chmod(temp, 0o600)
    temp.replace(path)


def read_json(path: Path, default: object) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


DB_PATH = STATE_DIR / "a2a.db"


def db_connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def init_store() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with db_connect() as conn:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at TEXT NOT NULL)")
        conn.execute("CREATE TABLE IF NOT EXISTS contexts (id TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at TEXT NOT NULL)")
        conn.execute("CREATE TABLE IF NOT EXISTS nonces (id TEXT PRIMARY KEY, created_at INTEGER NOT NULL)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_updated ON tasks(updated_at)")
        # Recover tasks that could not survive a Bridge restart.
        rows = conn.execute("SELECT id, data FROM tasks").fetchall()
        for row in rows:
            task = json.loads(row["data"])
            if task.get("status") in ("submitted", "working"):
                task["status"] = "failed"
                task["error"] = "bridge_restarted"
                task["updated_at"] = now()
                conn.execute("UPDATE tasks SET data=?, updated_at=? WHERE id=?", (json.dumps(task, ensure_ascii=False), task["updated_at"], row["id"]))
        conn.commit()
    migrate_legacy_json()


def migrate_legacy_json() -> None:
    tasks_dir = STATE_DIR / "tasks"
    contexts_dir = STATE_DIR / "contexts"
    with db_connect() as conn:
        for path in tasks_dir.glob("*.json"):
            task = read_json(path, None)
            if isinstance(task, dict) and task.get("id"):
                conn.execute("INSERT OR IGNORE INTO tasks(id,data,updated_at) VALUES(?,?,?)", (task["id"], json.dumps(task, ensure_ascii=False), task.get("updated_at", now())))
        for path in contexts_dir.glob("*.json"):
            history = read_json(path, None)
            if isinstance(history, list):
                conn.execute("INSERT OR IGNORE INTO contexts(id,data,updated_at) VALUES(?,?,?)", (path.stem, json.dumps(history, ensure_ascii=False), now()))
        conn.commit()


def load_task(task_id: str) -> dict | None:
    with db_connect() as conn:
        row = conn.execute("SELECT data FROM tasks WHERE id=?", (task_id,)).fetchone()
    if not row:
        return None
    task = json.loads(row["data"])
    return task if isinstance(task, dict) else None


def save_task(task: dict, publish: bool = True) -> None:
    with STORE_LOCK:
        with db_connect() as conn:
            conn.execute("INSERT INTO tasks(id,data,updated_at) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data, updated_at=excluded.updated_at", (task["id"], json.dumps(task, ensure_ascii=False), task["updated_at"]))
            conn.commit()
        if publish:
            for subscriber in list(SUBSCRIBERS.get(task["id"], [])):
                try:
                    subscriber.put_nowait(task.copy())
                except queue.Full:
                    pass


def context_path(context_id: str) -> Path:
    return STATE_DIR / "contexts" / f"{context_id}.json"


def load_context(context_id: str) -> list[dict]:
    with db_connect() as conn:
        row = conn.execute("SELECT data FROM contexts WHERE id=?", (context_id,)).fetchone()
    value = json.loads(row["data"]) if row else []
    return value if isinstance(value, list) else []


def save_context(context_id: str, history: list[dict]) -> None:
    with STORE_LOCK:
        history = history[-MAX_HISTORY:]
        with db_connect() as conn:
            conn.execute("INSERT INTO contexts(id,data,updated_at) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data, updated_at=excluded.updated_at", (context_id, json.dumps(history, ensure_ascii=False), now()))
            conn.commit()


def cleanup_store() -> None:
    cutoff = datetime.now(timezone.utc).timestamp() - TASK_TTL
    context_cutoff = datetime.now(timezone.utc).timestamp() - CONTEXT_TTL
    with db_connect() as conn:
        rows = conn.execute("SELECT id, data, updated_at FROM tasks").fetchall()
        for row in rows:
            try:
                old = datetime.fromisoformat(row["updated_at"]).timestamp() < cutoff
            except (TypeError, ValueError):
                old = False
            if old and json.loads(row["data"]).get("status") in ("completed", "failed", "cancelled"):
                conn.execute("DELETE FROM tasks WHERE id=?", (row["id"],))
                shutil.rmtree(STATE_DIR / "artifacts" / row["id"], ignore_errors=True)
        conn.execute("DELETE FROM contexts WHERE updated_at < ?", (datetime.fromtimestamp(context_cutoff, timezone.utc).isoformat(),))
        conn.commit()
    events = STATE_DIR / "events.jsonl"
    try:
        if events.stat().st_size > 10 * 1024 * 1024:
            rotated = events.with_name("events.jsonl.1")
            events.replace(rotated)
    except FileNotFoundError:
        pass


def cleanup_loop() -> None:
    while True:
        time.sleep(3600)
        try:
            cleanup_store()
        except Exception as exc:
            print(f"a2a-bridge: cleanup failed: {exc}", file=sys.stderr, flush=True)


def metrics_text() -> str:
    counts: dict[str, int] = {}
    with db_connect() as conn:
        rows = conn.execute("SELECT data FROM tasks").fetchall()
    for row in rows:
        state = json.loads(row["data"]).get("status", "unknown")
        counts[state] = counts.get(state, 0) + 1
    with PROCESS_LOCK:
        active = len(PROCESSES)
    lines = ["# HELP a2a_tasks_total Tasks currently retained by state", "# TYPE a2a_tasks_total gauge"]
    for state, count in sorted(counts.items()):
        lines.append(f'a2a_tasks_total{{state="{state}"}} {count}')
    lines += ["# HELP a2a_workers_active Active Hermes subprocesses", "# TYPE a2a_workers_active gauge", f"a2a_workers_active {active}"]
    return "\n".join(lines) + "\n"


def reply(handler: BaseHTTPRequestHandler, status: int, payload: object) -> None:
    data = json.dumps(payload, ensure_ascii=False).encode()
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(data)


def signature_headers(body: bytes, key: str) -> dict[str, str]:
    timestamp = str(int(time.time()))
    digest = hmac.new(key.encode(), timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
    return {"X-A2A-Timestamp": timestamp, "X-A2A-Signature": f"sha256={digest}"}


def authorized(handler: BaseHTTPRequestHandler, body: bytes = b"") -> bool:
    if not bool(TOKEN) or handler.headers.get("Authorization") != f"Bearer {TOKEN}":
        return False
    if not REQUIRE_SIGNATURE or not body:
        return True
    if not SIGNING_KEY:
        return False
    try:
        timestamp = int(handler.headers.get("X-A2A-Timestamp", "0"))
    except ValueError:
        return False
    if abs(int(time.time()) - timestamp) > SIGNATURE_WINDOW:
        return False
    supplied = handler.headers.get("X-A2A-Signature", "")
    expected = hmac.new(SIGNING_KEY.encode(), str(timestamp).encode() + b"." + body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(supplied, f"sha256={expected}"):
        return False
    request_id = handler.headers.get("X-A2A-Request-ID", "")
    if not request_id or len(request_id) > 128:
        return False
    try:
        with db_connect() as conn:
            conn.execute("DELETE FROM nonces WHERE created_at < ?", (int(time.time()) - SIGNATURE_WINDOW,))
            conn.execute("INSERT INTO nonces(id,created_at) VALUES(?,?)", (request_id, int(time.time())))
            conn.commit()
    except sqlite3.IntegrityError:
        return False
    return True


def task_view(task: dict) -> dict:
    return {
        "id": task["id"],
        "context_id": task["context_id"],
        "status": task["status"],
        "agent": AGENT_NAME,
        "created_at": task["created_at"],
        "updated_at": task["updated_at"],
        "input": task["message"],
        "output": task.get("output"),
        "error": task.get("error"),
        "toolsets": task.get("toolsets", []),
        "artifacts": task.get("artifacts", []),
    }


def standard_task(task: dict) -> dict:
    state = "canceled" if task["status"] == "cancelled" else task["status"]
    return {
        "id": task["id"],
        "contextId": task["context_id"],
        "status": {"state": state, "timestamp": task["updated_at"]},
        "artifacts": task.get("artifacts", []),
        "metadata": {"agent": AGENT_NAME, "output": task.get("output"), "error": task.get("error")},
    }


def callback_allowed(url: str) -> bool:
    try:
        parsed = urlparse(url)
        addr = ipaddress.ip_address(parsed.hostname or "")
        return (
            parsed.scheme == "http" and parsed.port == PORT
            and parsed.path == "/a2a/v1/events"
            and str(addr) in PEERS and addr in ipaddress.ip_network("100.64.0.0/10")
        )
    except (ValueError, TypeError):
        return False


def send_callback(task: dict) -> None:
    url = task.get("callback_url")
    if not url or not callback_allowed(url):
        return
    view = standard_task(task)
    payload = json.dumps({"statusUpdate": {
        "taskId": view["id"], "contextId": view["contextId"], "status": view["status"],
        "final": view["status"]["state"] in {"completed", "failed", "canceled"},
    }}, ensure_ascii=False).encode()
    headers = {
        "Authorization": f"Bearer {CALLBACK_TOKEN}",
        "Content-Type": "application/a2a+json",
        "Content-Length": str(len(payload)),
    }
    headers.update(signature_headers(payload, CALLBACK_SIGNING_KEY))
    headers["X-A2A-Request-ID"] = str(uuid.uuid4())
    if task.get("notification_token"):
        headers["X-A2A-Notification-Token"] = task["notification_token"]
    request = Request(url, data=payload, method="POST", headers=headers)
    for attempt in range(CALLBACK_RETRIES):
        try:
            build_opener(HTTPHandler).open(request, timeout=CALLBACK_TIMEOUT).close()
            return
        except Exception as exc:
            if attempt + 1 == CALLBACK_RETRIES:
                print(f"a2a-bridge: callback failed after retries: {exc}", file=sys.stderr, flush=True)
            else:
                time.sleep(0.5 * (2 ** attempt))


def allowed_toolsets(role: str, requested: list[str]) -> tuple[bool, list[str]]:
    if not requested:
        return True, []
    if not ENABLE_TOOLS:
        return False, []
    policy = TOOL_POLICY.get(role) or TOOL_POLICY.get("default") or {}
    allowed = set(policy.get("toolsets", []))
    return set(requested).issubset(allowed), sorted(allowed)


def build_command(task: dict, prompt: str) -> list[str]:
    args = list(HERMES_ARGS)
    if task.get("toolsets") and ENABLE_TOOLS:
        args = [arg for arg in args if arg != "--safe-mode"]
        index = args.index("-z") if "-z" in args else len(args)
        args[index:index] = ["-t", ",".join(task["toolsets"])]
    return [HERMES_EXEC, *args, prompt]


def run_task(task: dict) -> None:
    WORKER_LIMIT.acquire()
    if task.get("cancel_requested"):
        task["status"] = "cancelled"
        task["error"] = "cancelled_by_client"
        task["updated_at"] = now()
        save_task(task)
        send_callback(task)
        WORKER_LIMIT.release()
        return
    task["status"] = "working"
    task["updated_at"] = now()
    save_task(task)
    send_callback(task)
    history = load_context(task["context_id"])
    prompt = "You are handling a private agent-to-agent task. Answer directly and concisely.\n"
    if history:
        prompt += "Recent context:\n" + "\n".join(f"{x['role']}: {x['content']}" for x in history) + "\n"
    prompt += f"Latest request:\n{task['message']}\n"
    prompt += "Allowed toolsets: " + ", ".join(task["toolsets"]) if task["toolsets"] else "Do not call tools."
    process: subprocess.Popen[str] | None = None
    try:
        process = subprocess.Popen(
            build_command(task, prompt), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env=os.environ.copy()
        )
        with PROCESS_LOCK:
            PROCESSES[task["id"]] = process
        deadline = threading.Event()
        while process.poll() is None:
            if task.get("cancel_requested") or task["id"] in CANCEL_REQUESTS:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                task["status"] = "cancelled"
                task["error"] = "cancelled_by_client"
                task["updated_at"] = now()
                save_task(task)
                send_callback(task)
                return
            if deadline.wait(1):
                break
            if (datetime.now(timezone.utc) - datetime.fromisoformat(task["updated_at"])).total_seconds() > TIMEOUT:
                process.kill()
                task["status"] = "failed"
                task["error"] = "hermes_timeout"
                task["updated_at"] = now()
                save_task(task)
                send_callback(task)
                return
        stdout, stderr = process.communicate()
        if process.returncode != 0:
            task["status"] = "failed"
            task["error"] = stderr[-4000:] or "hermes_failed"
        else:
            task["status"] = "completed"
            task["output"] = stdout.strip()[-65536:]
            history.extend([
                {"role": "user", "content": task["message"]},
                {"role": "agent", "content": task["output"]},
            ])
            save_context(task["context_id"], history)
        task["updated_at"] = now()
        save_task(task)
        send_callback(task)
    except Exception as exc:
        task["status"] = "failed"
        task["error"] = str(exc)[-4000:]
        task["updated_at"] = now()
        save_task(task)
        send_callback(task)
    finally:
        with PROCESS_LOCK:
            PROCESSES.pop(task["id"], None)
            CANCEL_REQUESTS.discard(task["id"])
        WORKER_LIMIT.release()


def submit_task(body: dict) -> tuple[dict | None, str | None]:
    message = body.get("message")
    if isinstance(message, dict):
        parts = message.get("parts", [])
        message = "\n".join(p.get("text", "") for p in parts if isinstance(p, dict))
    if not isinstance(message, str) or not message.strip() or len(message) > MAX_MESSAGE:
        return None, "invalid_message"
    context_id = body.get("context_id", body.get("contextId")) or str(uuid.uuid4())
    role = body.get("role", "default")
    toolsets = body.get("toolsets", [])
    if not isinstance(toolsets, list) or any(not isinstance(x, str) for x in toolsets):
        return None, "invalid_toolsets"
    accepted, allowed = allowed_toolsets(role, toolsets)
    if not accepted:
        return None, "toolset_not_allowed:" + ",".join(allowed)
    callback_url = body.get("callback_url", body.get("callbackUrl"))
    if callback_url is not None and (not isinstance(callback_url, str) or not callback_allowed(callback_url)):
        return None, "callback_not_allowed"
    with db_connect() as conn:
        rows = conn.execute("SELECT data FROM tasks").fetchall()
    pending = sum(1 for row in rows if json.loads(row["data"]).get("status") in ("submitted", "working"))
    if pending >= MAX_PENDING_TASKS:
        return None, "task_queue_full"
    task = {
        "id": str(uuid.uuid4()), "context_id": context_id, "status": "submitted",
        "message": message, "role": role, "toolsets": toolsets, "callback_url": callback_url,
        "created_at": now(), "updated_at": now(), "artifacts": [],
    }
    save_task(task)
    threading.Thread(target=run_task, args=(task,), daemon=True).start()
    return task, None


def rpc_error(request_id: object, code: int, message: str) -> dict:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


class Handler(BaseHTTPRequestHandler):
    server_version = "HermesA2ABridge/0.3"

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write("a2a-bridge: " + (fmt % args) + "\n")

    def do_GET(self) -> None:
        if self.path == "/healthz":
            reply(self, 200, {"ok": True, "agent": AGENT_NAME})
            return
        if self.path == "/metrics":
            if not authorized(self):
                reply(self, 401, {"error": "unauthorized"})
                return
            data = metrics_text().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path == "/.well-known/agent-card.json":
            reply(self, 200, {
                "name": AGENT_NAME, "description": "Private Hermes agent", "version": AGENT_VERSION,
                "url": f"http://{HOST}:{PORT}/a2a", "supportedInterfaces": [{
                    "url": f"http://{HOST}:{PORT}/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"
                }],
                "capabilities": {"streaming": True, "pushNotifications": True},
                "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"}},
                "security": [{"bearerAuth": []}],
                "defaultInputModes": ["text/plain", "application/json"],
                "defaultOutputModes": ["text/plain", "application/json"],
                "skills": [{"id": "hermes-delegation", "name": "Hermes delegated task",
                            "description": "Run a bounded task through Hermes", "tags": ["research", "coding"]}],
            })
            return
        prefix = "/a2a/v1/tasks/"
        if self.path.startswith(prefix):
            if not authorized(self):
                reply(self, 401, {"error": "unauthorized"})
                return
            suffix = self.path[len(prefix):].split("?", 1)[0]
            if suffix.endswith("/events"):
                self.stream_events(suffix[:-7].rstrip("/"))
                return
            if "/artifacts/" in suffix:
                task_id, artifact_id = suffix.split("/artifacts/", 1)
                self.download_artifact(task_id, artifact_id)
                return
            task = load_task(suffix)
            if not task:
                reply(self, 404, {"error": "task_not_found"})
            else:
                reply(self, 200, task_view(task))
            return
        reply(self, 404, {"error": "not_found"})

    def read_body(self, limit: int = MAX_BODY) -> tuple[dict, bytes] | None:
        length = int(self.headers.get("Content-Length", "-1"))
        if length < 0 or length > limit:
            return None
        try:
            raw = self.rfile.read(length)
            value = json.loads(raw)
            return (value, raw) if isinstance(value, dict) else None
        except (ValueError, json.JSONDecodeError):
            return None

    def do_POST(self) -> None:
        parsed = self.read_body(MAX_ARTIFACT + MAX_BODY if self.path.endswith("/artifacts") else MAX_BODY)
        if parsed is None:
            reply(self, 400, {"error": "invalid_json_or_body_too_large"})
            return
        body, raw_body = parsed
        if not authorized(self, raw_body):
            reply(self, 401, {"error": "unauthorized"})
            return
        if self.path == "/a2a":
            self.handle_rpc(body)
            return
        if self.path == "/a2a/v1/message":
            task, error = submit_task(body)
            if error:
                reply(self, 403 if error.startswith("toolset_") else 400, {"error": error})
            else:
                reply(self, 202, task_view(task))
            return
        if self.path == "/a2a/v1/events":
            event_path = STATE_DIR / "events.jsonl"
            event_path.parent.mkdir(parents=True, exist_ok=True)
            with event_path.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps({"received_at": now(), "event": body}, ensure_ascii=False) + "\n")
            reply(self, 202, {"accepted": True})
            return
        prefix = "/a2a/v1/tasks/"
        if self.path.startswith(prefix) and self.path.endswith("/artifacts"):
            self.upload_artifact(self.path[len(prefix):-10].rstrip("/"), body)
            return
        reply(self, 404, {"error": "not_found"})

    def handle_rpc(self, body: dict) -> None:
        request_id = body.get("id")
        if body.get("jsonrpc") != "2.0":
            reply(self, 400, rpc_error(request_id, -32600, "invalid JSON-RPC request"))
            return
        method = body.get("method")
        params = body.get("params") or {}
        if method in ("message/send", "message/stream"):
            task, error = submit_task(params)
            if error:
                reply(self, 403 if error.startswith("toolset_") else 400, rpc_error(request_id, -32000, error))
                return
            if method == "message/stream":
                self.stream_events(task["id"], request_id)
            else:
                reply(self, 200, {"jsonrpc": "2.0", "id": request_id, "result": standard_task(task)})
            return
        task_id = params.get("id", params.get("taskId"))
        task = load_task(task_id) if isinstance(task_id, str) else None
        if method == "tasks/get":
            if not task:
                reply(self, 404, rpc_error(request_id, -32001, "task not found"))
            else:
                reply(self, 200, {"jsonrpc": "2.0", "id": request_id, "result": standard_task(task)})
            return
        if method == "tasks/cancel":
            if not task:
                reply(self, 404, rpc_error(request_id, -32001, "task not found"))
            elif task["status"] in ("completed", "failed", "cancelled"):
                reply(self, 200, {"jsonrpc": "2.0", "id": request_id, "result": standard_task(task)})
            else:
                task["cancel_requested"] = True
                with PROCESS_LOCK:
                    CANCEL_REQUESTS.add(task["id"])
                save_task(task)
                reply(self, 200, {"jsonrpc": "2.0", "id": request_id, "result": standard_task(task)})
            return
        if method in ("tasks/pushNotificationConfig/set", "tasks/pushNotificationConfig/get", "tasks/pushNotificationConfig/delete", "tasks/pushNotificationConfig/list"):
            if not task:
                reply(self, 404, rpc_error(request_id, -32001, "task not found"))
                return
            if method == "tasks/pushNotificationConfig/set":
                config = params.get("pushNotificationConfig") or params.get("push_notification_config") or {}
                url = config.get("url") if isinstance(config, dict) else None
                if not isinstance(url, str) or not callback_allowed(url):
                    reply(self, 400, rpc_error(request_id, -32602, "push notification URL is not an allowed Tailscale peer"))
                    return
                task["callback_url"] = url
                task["notification_token"] = config.get("token")
                save_task(task)
                result_value = {"taskId": task["id"], "pushNotificationConfig": {"url": url, "token": config.get("token")}}
            elif method == "tasks/pushNotificationConfig/delete":
                task.pop("callback_url", None)
                task.pop("notification_token", None)
                save_task(task)
                result_value = {"deleted": True, "taskId": task["id"]}
            else:
                config = ({"url": task["callback_url"], "token": task.get("notification_token")} if task.get("callback_url") else None)
                result_value = ([config] if method.endswith("/list") and config else (config or {}))
            reply(self, 200, {"jsonrpc": "2.0", "id": request_id, "result": result_value})
            return
        if method == "tasks/resubscribe":
            if not task:
                reply(self, 404, rpc_error(request_id, -32001, "task not found"))
                return
            self.stream_events(task["id"], request_id)
            return
        reply(self, 400, rpc_error(request_id, -32601, "method not found"))

    def stream_events(self, task_id: str, request_id: object = None) -> None:
        task = load_task(task_id)
        if not task:
            reply(self, 404, {"error": "task_not_found"})
            return
        subscriber: queue.Queue[dict] = queue.Queue(maxsize=32)
        with STORE_LOCK:
            SUBSCRIBERS.setdefault(task_id, []).append(subscriber)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        try:
            initial = {"jsonrpc": "2.0", "id": request_id, "result": standard_task(task)} if request_id is not None else standard_task(task)
            self.wfile.write(f"data: {json.dumps(initial, ensure_ascii=False)}\n\n".encode())
            self.wfile.flush()
            while task["status"] not in ("completed", "failed", "cancelled"):
                try:
                    task = subscriber.get(timeout=15)
                    event = {"jsonrpc": "2.0", "id": request_id, "result": standard_task(task)} if request_id is not None else standard_task(task)
                    self.wfile.write(f"data: {json.dumps(event, ensure_ascii=False)}\n\n".encode())
                    self.wfile.flush()
                except queue.Empty:
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with STORE_LOCK:
                if task_id in SUBSCRIBERS and subscriber in SUBSCRIBERS[task_id]:
                    SUBSCRIBERS[task_id].remove(subscriber)

    def upload_artifact(self, task_id: str, body: dict) -> None:
        task = load_task(task_id)
        if not task:
            reply(self, 404, {"error": "task_not_found"})
            return
        try:
            raw = base64.b64decode(body["content_base64"], validate=True)
            if len(raw) > MAX_ARTIFACT:
                raise ValueError("artifact too large")
            artifact_id = str(uuid.uuid4())
            filename = safe_name(str(body.get("filename", "artifact.bin")))
            path = STATE_DIR / "artifacts" / task_id / f"{artifact_id}-{filename}"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            os.chmod(path, 0o600)
            item = {"artifact_id": artifact_id, "filename": filename, "mime_type": body.get("mime_type") or mimetypes.guess_type(filename)[0] or "application/octet-stream", "size": len(raw), "url": f"/a2a/v1/tasks/{task_id}/artifacts/{artifact_id}"}
            task.setdefault("artifacts", []).append(item)
            task["updated_at"] = now()
            save_task(task)
            reply(self, 201, item)
        except (KeyError, ValueError, base64.binascii.Error) as exc:
            reply(self, 400, {"error": "invalid_artifact", "detail": str(exc)})

    def download_artifact(self, task_id: str, artifact_id: str) -> None:
        task = load_task(task_id)
        if not task:
            reply(self, 404, {"error": "task_not_found"})
            return
        item = next((x for x in task.get("artifacts", []) if x.get("artifact_id") == artifact_id), None)
        if not item:
            reply(self, 404, {"error": "artifact_not_found"})
            return
        matches = list((STATE_DIR / "artifacts" / task_id).glob(f"{artifact_id}-*"))
        if not matches:
            reply(self, 404, {"error": "artifact_not_found"})
            return
        data = matches[0].read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", item["mime_type"])
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Disposition", f"attachment; filename=\"{item['filename']}\"")
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    if not TOKEN:
        raise SystemExit("A2A_TOKEN is required")
    (STATE_DIR / "tasks").mkdir(parents=True, exist_ok=True)
    (STATE_DIR / "contexts").mkdir(parents=True, exist_ok=True)
    (STATE_DIR / "artifacts").mkdir(parents=True, exist_ok=True)
    init_store()
    cleanup_store()
    threading.Thread(target=cleanup_loop, name="a2a-cleanup", daemon=True).start()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Hermes A2A bridge listening on {HOST}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
