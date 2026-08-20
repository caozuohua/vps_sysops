# Hermes A2A Bridge

Private, task-based A2A subset for the two Hermes instances.

- `GET /.well-known/agent-card.json`
- `POST /a2a` JSON-RPC methods: `message/send`, `message/stream`, `tasks/get`, `tasks/cancel`, and push-notification config methods
- `GET /a2a/v1/tasks/{task_id}/events` for SSE status updates
- `GET/POST /a2a/v1/tasks/{task_id}/artifacts/{artifact_id}` for bounded base64 file transfer
- Legacy `POST /a2a/v1/message` and peer callback `POST /a2a/v1/events`
- Tailscale-only bind, separate per-node Bearer tokens, HMAC-SHA256 request
  signatures, timestamp windows, and request-ID replay protection
- SQLite WAL task/context store, restart recovery, TTL cleanup, bounded queue,
  one Hermes worker, callback retries, and `/metrics`
- Ordinary requests remain tool-free. Explicit QPC/多维表格 requests are
  auto-routed to the dedicated `qpc-bitable` capability, which grants only
  `terminal` and `skills` so HermesLite can load the QPC skill and perform the
  authenticated record write. The code rejects all other toolsets unless
  `A2A_ENABLE_TOOLS=true` and the caller role is allowed by `A2A_TOOL_POLICY`.

This is intentionally a narrow private implementation. It does not expose
the public internet and does not yet implement full A2A artifact `parts` or
streaming chunk semantics; artifacts use a deliberately bounded private
base64 endpoint.
