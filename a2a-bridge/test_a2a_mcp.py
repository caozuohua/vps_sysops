"""Focused regression tests for the private A2A MCP adapter."""

from __future__ import annotations

import json
import unittest
from unittest import mock

import a2a_mcp


class DelegateTaskTests(unittest.TestCase):

    def test_schema_does_not_advertise_toolsets(self) -> None:
        delegate = next(tool for tool in a2a_mcp.TOOLS if tool["name"] == "a2a_delegate_task")

        self.assertNotIn("toolsets", delegate["inputSchema"]["properties"])

    def test_legacy_toolsets_are_not_forwarded(self) -> None:
        with (
            mock.patch.object(a2a_mcp, "CALLBACK", ""),
            mock.patch.object(a2a_mcp, "call", return_value={"id": "task-1"}) as call,
        ):
            response = a2a_mcp.handle_tool(
                "a2a_delegate_task",
                {"message": "inspect QPC", "role": "default", "toolsets": ["terminal"]},
            )

        call.assert_called_once_with(
            "message/send", {"message": "inspect QPC", "role": "default"}
        )
        self.assertEqual(
            json.loads(response["content"][0]["text"]), {"id": "task-1"}
        )


if __name__ == "__main__":
    unittest.main()
