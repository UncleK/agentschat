import json
from pathlib import Path
import urllib.error
import urllib.request

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
browser = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36', 'Sec-Fetch-Dest': 'document'}
def get(path, headers=None):
    request = urllib.request.Request('https://agentschat.app' + path, headers=headers or {})
    try:
        response = opener.open(request, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    response_headers = dict((k.lower(), v) for k, v in response.headers.items())
    response_headers['set-cookie'] = '; '.join(response.headers.get_all('set-cookie') or [])
    return response.status, response_headers, response.read().decode('utf-8')

status, headers, body = get('/', browser)
assert status == 200 and '<main' in body and 'Agents Chat' in body
assert headers.get('clear-site-data') == '"cache"', headers
assert 'agents-chat.avatar-cache-policy=raster-v1' in headers.get('set-cookie', '')
status, second_headers, _ = get('/', {**browser, 'Cookie': 'agents-chat.avatar-cache-policy=raster-v1'})
assert status == 200 and 'clear-site-data' not in second_headers
status, api_headers, body = get('/api/v1/health')
assert status == 200 and json.loads(body)['status'] == 'ok'
assert 'no-store' in api_headers.get('cache-control', '')
assert api_headers.get('cf-cache-status') != 'HIT'
status, auth_headers, _ = get('/api/v1/auth/me')
assert status == 401
assert 'no-store' in auth_headers.get('cache-control', '')
status, _, docs = get('/docs', browser)
assert status == 200 and '/blob/main/' in docs and '/blob/stable/' not in docs
status, _, llms = get('/llms.txt', browser)
assert status == 200 and '/main/' in llms and '/stable/' not in llms
result = {'site': 'https://agentschat.app', 'homepage': 200, 'firstDocumentClearSiteData': headers.get('clear-site-data'),
          'secondDocumentDoesNotClearAgain': True, 'health': 200, 'apiCacheControl': api_headers.get('cache-control'),
          'apiCloudflareCacheStatus': api_headers.get('cf-cache-status'), 'unauthenticatedMe': 401,
          'docsAndLlmsUseMain': True, 'requestCredentials': 'none; synthetic cache policy cookie only'}
Path(__file__).with_name('http-smoke.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
