"""Deterministic Pi RPC stand-in: no network, credentials, or model calls."""

import json
from pathlib import Path
import re
import sys
import time


def emit(record):
    # Deliberately fragment UTF-8, retain Unicode separators, and use CRLF.
    wire = (json.dumps(record, ensure_ascii=False) + "\r\n").encode()
    for offset in range(0, len(wire), 7):
        sys.stdout.buffer.write(wire[offset:offset + 7])
        sys.stdout.buffer.flush()


def complete(prompt, reply="Edited files λ\u2028summary\n"):
    target = Path(json.loads(re.search(r"^Target file: (.*)$", prompt, re.M)[1]))
    emit({"type": "message_start", "message": {"role": "assistant"}})
    emit({"type": "message_update", "assistantMessageEvent": {
        "type": "thinking_start", "contentIndex": 0}})
    emit({"type": "message_update", "assistantMessageEvent": {
        "type": "thinking_delta", "contentIndex": 0, "delta": "Checking context"}})
    emit({"type": "message_end", "message": {"role": "assistant", "stopReason": "toolUse",
          "content": [{"type": "thinking", "thinking": "Checking context"}]}})
    emit({"type": "tool_execution_start", "toolName": "write",
          "args": {"path": str(target), "tags": ["whole", "file"]}})
    if "fixture/edit" in prompt:
        target.write_text("Pi changed the whole file\n")
        target.with_name("sidecar.txt").write_text("Pi changed another file\n")
    if "fixture/delete" in prompt:
        target.unlink()
    emit({"type": "tool_execution_end", "toolName": "write",
          "result": {"content": [{"type": "text", "text": "Write result"}]}})
    emit({"type": "message_start", "message": {"role": "assistant"}})
    emit({"type": "message_update", "assistantMessageEvent": {
        "type": "text_delta", "contentIndex": 0, "delta": "incorrect partial"}})
    message = {"role": "assistant", "stopReason": "stop", "content": [
        {"type": "text", "text": reply}]}
    if "fixture/error" in prompt:
        message.update(stopReason="error", errorMessage="Provider fixture failure")
    if "fixture/length" in prompt:
        message.update(stopReason="length")
    if "fixture/empty" in prompt:
        message["content"] = []
    emit({"type": "message_end", "message": message})
    emit({"type": "agent_end", "willRetry": False})
    time.sleep(0.15)
    emit({"type": "agent_settled", "aborted": False})


pending = None
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
        if "fixture/dialog" in prompt:
            pending = prompt
            emit({"type": "extension_ui_request", "id": "fixture-confirm", "method": "confirm",
                  "title": "Proceed?", "message": "Allow the fixture to continue?"})
        else:
            complete(prompt)
    elif record["type"] == "extension_ui_response" and pending:
        complete(pending, "Dialog confirmed: " + json.dumps(record.get("confirmed")))
        pending = None
