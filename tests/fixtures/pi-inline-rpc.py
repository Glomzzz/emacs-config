"""Deterministic Pi RPC stand-in: no network, credentials, or model calls."""

import json
import sys
import time


def emit(record):
    # Deliberately fragment records, retain Unicode separators, and use CRLF.
    wire = (json.dumps(record, ensure_ascii=False) + "\r\n").encode()
    for offset in range(0, len(wire), 7):
        sys.stdout.buffer.write(wire[offset:offset + 7])
        sys.stdout.buffer.flush()


for line in sys.stdin.buffer:
    record = json.loads(line)
    if record["type"] == "get_state":
        emit({"type": "response", "id": record["id"], "success": True,
              "data": {"sessionFile": "/tmp/pi-inline-fixture-session.jsonl"}})
    elif record["type"] == "prompt":
        prompt = record["message"]
        if "fixture/reject" in prompt:
            emit({"type": "response", "id": record["id"], "success": False,
                  "error": "Rejected fixture prompt"})
            continue
        emit({"type": "response", "id": record["id"], "success": True,
              "data": {"disposition": "handled" if "fixture/handled" in prompt else "started"}})
        if "fixture/hang" in prompt or "fixture/handled" in prompt:
            continue
        emit({"type": "message_start", "message": {"role": "assistant"}})
        emit({"type": "message_update", "assistantMessageEvent": {
            "type": "thinking_start", "contentIndex": 0}})
        emit({"type": "message_update", "assistantMessageEvent": {
            "type": "thinking_delta", "contentIndex": 0, "delta": "Checking context"}})
        emit({"type": "message_update", "assistantMessageEvent": {
            "type": "text_delta", "contentIndex": 1, "delta": "incorrect partial"}})
        message = {"role": "assistant", "stopReason": "stop", "content": [
            {"type": "thinking", "thinking": "Checking context"},
            {"type": "text", "text": "generated λ\u2028text\n"}]}
        if "fixture/error" in prompt:
            message.update(stopReason="error", errorMessage="Provider fixture failure")
        if "fixture/length" in prompt:
            message.update(stopReason="length")
        if "fixture/empty" in prompt:
            message["content"] = []
        emit({"type": "message_end", "message": message})
        emit({"type": "tool_execution_start", "toolName": "read",
              "args": {"path": "example.txt"}})
        emit({"type": "tool_execution_end", "toolName": "read",
              "result": {"content": [{"type": "text", "text": "Read result"}]}})
        emit({"type": "agent_end", "willRetry": False})
        # Permit a test to inspect the state between agent_end and settled.
        time.sleep(0.15)
        emit({"type": "agent_settled", "aborted": False})
