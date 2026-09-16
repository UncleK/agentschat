import hashlib
import http.client
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

WORK = Path('/opt/agents-chat/shared/audit-canary-20260916')
SITE = Path('/etc/nginx/conf.d/agents-chat.conf')
NODE = '/opt/agents-chat/runtime/bin/node'
SOURCE = Path(__file__).resolve().parent

def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()

def sql(query):
    return run(['docker', 'exec', '-i', 'agents-chat-postgres', 'sh', '-c', 'exec psql -X -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -A -t'], input=query)

def write(path, text, mode=0o600, group=None):
    path.write_text(text, encoding='utf-8')
    path.chmod(mode)
    if group is not None: os.chown(path, 0, group)

def replace_site(text):
    temporary = SITE.with_suffix('.audit-next')
    write(temporary, text)
    os.replace(temporary, SITE)

def setup(expected):
    release = Path('/opt/agents-chat/current').resolve()
    assert (release / '.source-commit').read_text().strip() == expected
    assert not WORK.exists(), 'An earlier canary must be reconciled before setup'
    for port in (3211, 3212):
        with socket.socket() as sock: sock.bind(('127.0.0.1', port))
    uid = pwd.getpwnam('agentschat')
    WORK.mkdir(mode=0o750)
    os.chown(WORK, 0, uid.pw_gid)
    nonce = secrets.token_hex(6)
    database = 'agentschat_audit_' + nonce
    password = secrets.token_urlsafe(32)
    cfg = dict(release=str(release), expected=expected, apiPort=3212, webPort=3211,
               database=database, databaseUrl=f'postgresql://{database}:{password}@127.0.0.1:55434/{database}',
               bffSecret=secrets.token_urlsafe(32), edgeSecret=secrets.token_urlsafe(32),
               rateSecret=secrets.token_urlsafe(32), testToken=secrets.token_urlsafe(32),
               webhookSecret=secrets.token_urlsafe(32), webhookBody=json.dumps({'event':'synthetic.audit', 'nonce':nonce}),
               apiUnit='agents-chat-audit-api-' + nonce, webUnit='agents-chat-audit-web-' + nonce,
               baseUrl=f'https://agentschat.app/api/__audit_{nonce}/')
    write(WORK/'config.json', json.dumps(cfg), 0o640, uid.pw_gid)
    sql(f'CREATE ROLE {database} LOGIN PASSWORD \'{password}\';\nCREATE DATABASE {database} OWNER {database};\n')
    for name in ('fixture.cjs', 'egress.cjs'):
        write(WORK/name, (SOURCE/name).read_text(), 0o640, uid.pw_gid)
    env = {'NODE_ENV':'production', 'HOSTNAME':'127.0.0.1', 'PORT':'3211', 'API_ORIGIN':'http://127.0.0.1:3212',
           'SESSION_COOKIE_SECURE':'true', 'BFF_PROXY_SECRET':cfg['bffSecret'], 'EDGE_TO_WEB_SECRET':cfg['edgeSecret']}
    write(WORK/'web.env', ''.join(f'{key}={value}\n' for key,value in env.items()), 0o640, uid.pw_gid)
    run(['systemd-run', '--unit='+cfg['apiUnit'], '--collect', '-p', 'User=agentschat', '-p', 'Group=agentschat',
         '-p', 'MemoryMax=256M', '-p', 'CPUQuota=25%', NODE, str(WORK/'fixture.cjs'), str(WORK/'config.json')])
    run(['systemd-run', '--unit='+cfg['webUnit'], '--collect', '-p', 'User=agentschat', '-p', 'Group=agentschat',
         '-p', 'MemoryMax=384M', '-p', 'CPUQuota=25%', '--working-directory='+str(release/'web/.next/standalone'),
         NODE, '--env-file='+str(WORK/'web.env'), 'server.js'])
    for attempt in range(30):
        try:
            result = request(cfg, '/api/v1/audit/status', mode='direct-web', method='GET')
            if result['status'] == 200 and result['body'].get('ready'): break
        except (OSError, ValueError): pass
        time.sleep(1)
    else: raise RuntimeError('Canary did not become ready')
    before = SITE.read_text()
    marker = '    # HTTP API must pass through the Web BFF for HttpOnly sessions.'
    assert before.count(marker) == 1
    write(WORK/'nginx.before', before)
    prefix = '/api/__audit_' + nonce + '/'
    block = f'''    # Temporary synthetic audit canary; removed after verification.
    location ^~ {prefix}source/ {{
        proxy_pass http://127.0.0.1:3211/api/v1/audit/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $agents_chat_client_ip;
        proxy_set_header X-Real-IP $agents_chat_client_ip;
        proxy_set_header X-AgentsChat-Client-IP $agents_chat_client_ip;
        proxy_set_header X-AgentsChat-Edge-Key "{cfg['edgeSecret']}";
        proxy_set_header X-AgentsChat-Source "";
        proxy_set_header X-AgentsChat-Source-Signature "";
    }}
    location ^~ {prefix}webhook/ {{
        proxy_pass http://127.0.0.1:3212/api/v1/audit/webhook/;
        proxy_set_header Host $host;
    }}
'''
    after = before.replace(marker, block + marker)
    cfg['installedSiteHash'] = hashlib.sha256(after.encode()).hexdigest()
    write(WORK/'config.json', json.dumps(cfg), 0o640, uid.pw_gid)
    replace_site(after)
    try: run(['nginx', '-t'])
    except Exception:
        replace_site(before)
        raise
    run(['systemctl', 'reload', 'nginx'])
    print(json.dumps({'ready':True, 'baseUrl':cfg['baseUrl'], 'release':expected, 'database':'isolated', 'ports':[3211,3212]}))

def request(cfg, route='bootstrap/public', mode='public', method='POST', forged=False):
    headers={'Authorization':'Bearer '+cfg['testToken'], 'Content-Type':'application/json'}
    if forged:
        headers.update({'X-Forwarded-For':'192.0.2.123','CF-Connecting-IP':'198.51.100.77',
                        'X-AgentsChat-Client-IP':'203.0.113.99','X-AgentsChat-Edge-Key':'forged',
                        'X-AgentsChat-Source':'forged','X-AgentsChat-Source-Signature':'0'*64})
    body=b'{}' if method=='POST' else None
    if mode=='public':
        url=cfg['baseUrl']+'source/'+route
        req=urllib.request.Request(url, data=body, headers=headers, method=method)
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try: response=opener.open(req, timeout=15)
        except urllib.error.HTTPError as error: response=error
        return {'status':response.status,'body':json.loads(response.read())}
    if mode=='origin':
        context=ssl.create_default_context(cafile='/etc/agents-chat/origin-ca.pem')
        connection=http.client.HTTPSConnection('agentschat.app', timeout=15, context=context)
        connection.sock=context.wrap_socket(socket.create_connection(('127.0.0.1',443),timeout=15),server_hostname='agentschat.app')
        route='/'+cfg['baseUrl'].split('/',3)[3]+'source/'+route
    else:
        connection=http.client.HTTPConnection('127.0.0.1',cfg['webPort'],timeout=15)
    connection.request(method,route,body,headers)
    response=connection.getresponse()
    result={'status':response.status,'body':json.loads(response.read())}
    connection.close()
    return result

def source_probe():
    cfg=json.loads((WORK/'config.json').read_text())
    remote=request(cfg)
    assert remote['status'] in (201,429), remote
    origin=[request(cfg, mode='origin', forged=True) for _ in range(4)]
    assert [item['status'] for item in origin]==[201,201,201,429], origin
    assert remote['body']['sourceHash']!=origin[0]['body']['sourceHash'], 'Real ingress sources collapsed'
    direct=request(cfg, '/api/v1/audit/bootstrap/public', mode='direct-web', forged=True)
    assert direct['status']==429 and direct['body']['sourceHash']==origin[0]['body']['sourceHash'], direct
    result={'publicSourceStatus':remote['status'],'originStatuses':[item['status'] for item in origin],
            'publicAndOriginIndependent':True,'forgedHeadersDoNotResetBudget':True,'directBffSpoofRejected':True}
    write(WORK/'source-results.json',json.dumps(result))
    print(json.dumps(result))

def cleanup():
    assert WORK.resolve().parent==Path('/opt/agents-chat/shared') and WORK.name=='audit-canary-20260916'
    cfg=json.loads((WORK/'config.json').read_text())
    before=WORK/'nginx.before'
    if before.exists():
        current=hashlib.sha256(SITE.read_bytes()).hexdigest()
        original=hashlib.sha256(before.read_bytes()).hexdigest()
        assert current in (cfg.get('installedSiteHash'),original), 'Site changed during canary; do not overwrite it'
        replace_site(before.read_text())
        run(['nginx','-t'])
        run(['systemctl','reload','nginx'])
    for key in ('webUnit','apiUnit'):
        subprocess.run(['systemctl','stop',cfg[key]],capture_output=True)
    database=cfg['database']
    assert re.fullmatch(r'agentschat_audit_[a-f0-9]+',database)
    sql(f'DROP DATABASE IF EXISTS {database};\nDROP ROLE IF EXISTS {database};\n')
    # Exact task-owned path verified above. No live data or configuration removed.
    shutil.rmtree(WORK)
    print(json.dumps({'canaryRemoved':True,'productionSiteRestored':True,'testDatabaseRemoved':True}))

if __name__=='__main__':
    if sys.argv[1]=='setup': setup(sys.argv[2])
    elif sys.argv[1]=='source': source_probe()
    elif sys.argv[1]=='cleanup': cleanup()
    else: raise ValueError('Unknown command')
