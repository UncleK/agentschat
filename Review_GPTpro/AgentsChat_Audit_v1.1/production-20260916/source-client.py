import json
from pathlib import Path
import urllib.error
import urllib.request

cfg = json.loads(Path(__file__).with_name('config.json').read_text())
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def request(forged=False, forged_cf=False):
    headers = {'Authorization': 'Bearer ' + cfg['testToken'], 'Content-Type': 'application/json'}
    if forged:
        headers.update({'X-Forwarded-For': '192.0.2.1',
                        'X-AgentsChat-Client-IP': '203.0.113.1', 'X-AgentsChat-Edge-Key': 'forged',
                        'X-AgentsChat-Source': 'forged', 'X-AgentsChat-Source-Signature': '0' * 64})
    if forged_cf:
        headers['CF-Connecting-IP'] = '198.51.100.1'
    req = urllib.request.Request(cfg['baseUrl'] + 'source/bootstrap/public', data=b'{}', headers=headers)
    try:
        response = opener.open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read().decode('utf-8')
    try:
        body = json.loads(raw)
    except json.JSONDecodeError:
        body = {'edgeError': raw}
    return {'status': response.status, 'body': body}

results = [request() for _ in range(4)]
assert [r['status'] for r in results] == [201, 201, 201, 429], results
forged = request(True)
assert forged['status'] == 429, forged
assert len({r['body']['sourceHash'] for r in results + [forged]}) == 1
forged_cf = request(forged_cf=True)
assert forged_cf == {'status': 403, 'body': {'edgeError': 'error code: 1000\n'}}, forged_cf
result = {'publicStatuses': [r['status'] for r in results], 'forgedStatus': forged['status'],
          'forgedHeadersPreserveSourceBudget': True, 'forgedCfHeaderRejectedByEdge': forged_cf,
          'database': 'isolated', 'credentials': 'synthetic'}
Path(__file__).with_name('public-source-results.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
