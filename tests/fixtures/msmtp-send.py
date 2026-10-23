#!/usr/bin/env python3
"""Offline sendmail fixture: never opens a socket or reads credentials."""
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["MAIL_ASYNC_TEST_ROOT"])
with (root / "starts").open("a") as stream:
    stream.write("started\n")
(root / "started").touch()
deadline = time.monotonic() + 10
while not (root / "release").exists():
    if time.monotonic() > deadline:
        print("synthetic transport timed out", file=sys.stderr)
        sys.exit(75)
    time.sleep(0.02)
(root / "arguments.json").write_text(json.dumps(sys.argv[1:]))
(root / "wire.eml").write_bytes(sys.stdin.buffer.read())
if os.environ.get("MAIL_ASYNC_TEST_FAIL") == "1":
    print("synthetic SMTP rejection", file=sys.stderr)
    sys.exit(69)
print("synthetic SMTP acceptance")
