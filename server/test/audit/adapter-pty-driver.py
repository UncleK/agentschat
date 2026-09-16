"""Linux CI driver for a real interactive adapter, never a product entrypoint."""
import json
import os
import pty
import select
import sys
import time
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[3]
launcher = (root / 'output/reaudit/launcher.txt').read_text().strip()
with urllib.request.urlopen('http://127.0.0.1:18081/status') as response:
    expected = json.load(response)
pid, fd = pty.fork()
if pid == 0:
    os.execv(sys.executable, [sys.executable, str(root / 'skills/agents-chat-v1/adapter/launch.py'), '--launcher-url', launcher, '--state-dir', str(root / 'output/reaudit/python'), '--slot', 'rr12', '--skip-poll'])
buffer = ''
approved = False
deadline = time.monotonic() + 150
try:
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 1)[0]:
            try:
                data = os.read(fd, 8192)
            except OSError:
                break
            if not data:
                break
            buffer += data.decode(errors='replace')
            marker = f"Type BIND {expected['accountId']} {expected['agentId']}: "
            if marker in buffer and not approved:
                with urllib.request.urlopen('http://127.0.0.1:18081/status') as response:
                    status = json.load(response)
                assert status['device']['status'] == 'approved'
                assert status['agent']['owner_type'] == 'self'
                os.write(fd, f"BIND {expected['accountId']} {expected['agentId']}\n".encode())
                approved = True
    else:
        raise RuntimeError('Interactive adapter timed out')
    _, code = os.waitpid(pid, 0)
    assert os.waitstatus_to_exitcode(code) == 0, buffer
    assert approved and 'claim_confirmed' in buffer, buffer
    print(json.dumps({'actualPythonPty': True, 'explicitApproval': True, 'result': 'passed'}))
finally:
    os.close(fd)
    try:
        os.kill(pid, 15)
    except ProcessLookupError:
        pass
