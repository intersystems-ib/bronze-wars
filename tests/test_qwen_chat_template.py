"""Integration checks for the running Qwen server (standard library only).

Run: python -m unittest discover -s tests
Set QWEN_BASE_URL to use a server other than http://localhost:8001.
"""

import json
import os
import time
import unittest
import urllib.error
import urllib.request


BASE_URL = os.environ.get("QWEN_BASE_URL", "http://localhost:8001")
MODEL = os.environ.get("QWEN_MODEL_ALIAS", "qwen3.5-9b")
TOOLS = [{
    "type": "function",
    "function": {
        "name": "ping",
        "description": "Return a connectivity check.",
        "parameters": {"type": "object", "properties": {}},
    },
}]


def post(path, payload):
    request = urllib.request.Request(
        BASE_URL + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


class QwenTemplateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        deadline = time.monotonic() + 180
        while True:
            try:
                with urllib.request.urlopen(BASE_URL + "/health", timeout=5):
                    return
            except (urllib.error.URLError, TimeoutError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(2)

    def test_system_instructions_are_preserved_and_merged(self):
        result = post("/apply-template", {"messages": [
            {"role": "system", "content": "FIRST_INSTRUCTION"},
            {"role": "user", "content": "USER_QUERY"},
            {"role": "system", "content": [
                {"type": "text", "text": "SECOND_INSTRUCTION"},
            ]},
        ]})
        prompt = result["prompt"]
        self.assertEqual(prompt.count("<|im_start|>system"), 1)
        self.assertIn("FIRST_INSTRUCTION\n\nSECOND_INSTRUCTION", prompt)
        self.assertLess(prompt.index("SECOND_INSTRUCTION"), prompt.index("USER_QUERY"))

    def test_multiple_system_messages_with_tool_round_trip(self):
        messages = [
            {"role": "system", "content": "Use ping when requested."},
            {"role": "system", "content": "After the tool result, reply exactly OK."},
            {"role": "user", "content": "Call ping now."},
        ]
        payload = {
            "model": MODEL, "messages": messages, "tools": TOOLS,
            "max_tokens": 64, "temperature": 0,
            "tool_choice": "required",
        }
        response = post("/v1/chat/completions", payload)["choices"][0]
        self.assertEqual(response["finish_reason"], "tool_calls")
        call = response["message"]["tool_calls"][0]
        self.assertEqual(call["function"]["name"], "ping")
        self.assertEqual(json.loads(call["function"]["arguments"]), {})
        messages.extend([
            response["message"],
            {"role": "tool", "tool_call_id": call["id"], "content": "OK"},
            {"role": "system", "content": "The tool has finished. Reply OK without more calls."},
        ])
        payload["tool_choice"] = "none"
        final = post("/v1/chat/completions", payload)["choices"][0]
        self.assertEqual(final["finish_reason"], "stop")
        self.assertEqual(final["message"]["content"].strip(), "OK")

    def test_schema_instruction_after_user_returns_content(self):
        response = post("/v1/chat/completions", {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": "Reply only with compact JSON."},
                {"role": "user", "content": "Return the field ok with value true."},
                {"role": "system", "content": 'Use this JSON schema: {"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]}'},
            ],
            "max_tokens": 140, "temperature": 0,
        })["choices"][0]
        self.assertEqual(response["finish_reason"], "stop")
        self.assertEqual(json.loads(response["message"]["content"]), {"ok": True})


if __name__ == "__main__":
    unittest.main()
