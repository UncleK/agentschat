import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess

def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()

release = Path('/opt/agents-chat/current').resolve()
expected = '06dfebdb8ec5f782625912a6332933774ce49b3c'
assert (release / '.source-commit').read_text().strip() == expected
assert (release / '.release-ready').is_file()
assert not (release / '.release-failed').exists()
def env(path):
    return dict(line.split('=', 1) for line in Path(path).read_text().splitlines() if '=' in line and not line.startswith('#'))
server = env('/etc/agents-chat/server.env')
web = env('/etc/agents-chat/web.env')
assert server['BFF_PROXY_SECRET'] == web['BFF_PROXY_SECRET'] != web['EDGE_TO_WEB_SECRET']
assert len(server['BFF_PROXY_SECRET']) >= 32 and len(web['EDGE_TO_WEB_SECRET']) >= 32
assert server['TRUSTED_PROXY_PEERS'] == '127.0.0.1,::1'
site = Path('/etc/nginx/conf.d/agents-chat.conf')
assert stat.S_IMODE(site.stat().st_mode) == 0o600
assert web['EDGE_TO_WEB_SECRET'] in site.read_text()
assert '__audit_' not in site.read_text()
assert not Path('/opt/agents-chat/shared/audit-canary-20260916').exists()
for port in (3211, 3212):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', port))
units = ['agents-chat-api', 'agents-chat-web', 'nginx', 'agents-chat-backup.timer', 'hysteria-server', 'aveniqa-web', 'aveniqa-db']
units += ['aveniqa-worker@' + worker for worker in ['account-deletion', 'analytics-delivery', 'billing', 'curation', 'external-erasure', 'generation', 'media', 'privacy-cleanup', 'push']]
statuses = {}
for unit in units:
    result = subprocess.run(['systemctl', 'is-active', unit], capture_output=True, text=True)
    statuses[unit] = result.stdout.strip()
assert all(value == 'active' for value in statuses.values()), statuses
query = '''BEGIN READ ONLY;
SELECT json_build_object('migrations', (SELECT count(*) FROM typeorm_migrations),
  'syntheticDatabasesRemaining', (SELECT count(*) FROM pg_database WHERE datname LIKE 'agentschat_audit_%'),
  'syntheticRolesRemaining', (SELECT count(*) FROM pg_roles WHERE rolname LIKE 'agentschat_audit_%'));
ROLLBACK;'''
result = run(['docker', 'exec', '-i', 'agents-chat-postgres', 'sh', '-c', 'exec psql -X -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -A -t'], input=query)
database = json.loads(result)
assert database == {'migrations': 14, 'syntheticDatabasesRemaining': 0, 'syntheticRolesRemaining': 0}, database
backup = env('/opt/agents-chat/backups/reports/latest-backup.txt')
backups = {key: {'path': value, 'bytes': Path(value).stat().st_size} for key, value in backup.items() if key != 'timestamp'}
output = {'release': expected, 'readyAtUtc': (release / '.release-ready').read_text().strip(),
          'previousRelease': (release / '.previous-release').read_text().strip(),
          'bffKeysMatch': True, 'independentEdgeKey': True, 'trustedPeers': ['127.0.0.1', '::1'],
          'nginxMode': '0600', 'canaryRemoved': True, 'services': statuses, 'database': database,
          'backupTimestamp': backup['timestamp'], 'backups': backups,
          'egressKernelBoundary': run(['iptables', '-S', 'OUTPUT'])}
print(json.dumps(output, indent=2))
