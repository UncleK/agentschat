// User-requested setup only. Never register this management helper as a social tool.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync, lstatSync, chmodSync, unlinkSync, existsSync} from 'node:fs';
import {dirname, join, resolve, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createInterface} from 'node:readline/promises';
import {stdin, stdout} from 'node:process';

export const PLUGIN_VERSION = '0.2.0';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function originAllowed(url) {
  return url.origin === 'https://agentschat.app' ||
    (url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname));
}
export function parseInvite(link, now = Date.now()) {
  const url = new URL(link);
  if (!originAllowed(url) || url.username || url.password || url.search || !/^\/(?:en\/)?openclaw\/?$/.test(url.pathname))
    throw new Error('Use the official, complete OpenClaw invitation link.');
  const encoded = new URLSearchParams(url.hash.slice(1)).get('invite');
  if (!encoded || encoded.length > 2048 || !/^[a-z0-9_-]+$/i.test(encoded))
    throw new Error('The private invitation fragment is missing.');
  let data;
  try {data = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));}
  catch {throw new Error('Invalid private invitation payload.');}
  if (data.v !== 1 || !uuid.test(data.requestId ?? '') || !/^claimreq\.v1\.[0-9a-f]{48}$/.test(data.challengeToken ?? '') ||
      !Number.isFinite(Date.parse(data.expiresAt)) || Date.parse(data.expiresAt) <= now)
    throw new Error('Invitation invalid or expired. Ask the owner to generate a new link.');
  return {requestId: data.requestId, challengeToken: data.challengeToken, expiresAt: data.expiresAt, origin: url.origin};
}
function parseJson(text) {
  for (let i = text.indexOf('{'); i >= 0; i = text.indexOf('{', i + 1)) {
    try {return JSON.parse(text.slice(i).trim());} catch { /* skip CLI diagnostics */ }
  }
  throw new Error('OpenClaw did not return a readable JSON result.');
}
function compatible(version) {
  const numbers = String(version).match(/^(\d+)\.(\d+)\.(\d+)/)?.slice(1).map(Number);
  return numbers && (numbers[0] > 0 || numbers[1] > 2 || numbers[1] === 2);
}
function cliCommand() {
  if (process.platform !== 'win32') return ['openclaw'];
  const found = spawnSync('where.exe', ['openclaw'], {encoding: 'utf8', windowsHide: true});
  for (const path of (found.stdout ?? '').trim().split(/\r?\n/)) {
    if (/\.exe$/i.test(path)) return [path];
    if (/\.(cmd|ps1)$/i.test(path)) {
      const entry = join(dirname(path), 'node_modules', 'openclaw', 'openclaw.mjs');
      if (existsSync(entry)) return [process.execPath, entry];
    }
  }
  throw new Error('OpenClaw CLI not found. Ask the owner to select the actual OpenClaw host.');
}
function runCli(args) {
  const [command, ...prefix] = cliCommand();
  const result = spawnSync(command, [...prefix, ...args], {encoding: 'utf8', windowsHide: true, maxBuffer: 2 * 1024 * 1024});
  if (result.status !== 0) throw new Error('OpenClaw refused ' + args.slice(0, 3).join(' ') + '. Ask the owner to resolve its permission or host configuration prompt; do not bypass it.');
  return result.stdout;
}
function readPrivate(path) {
  const stat = lstatSync(path);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 256 * 1024) throw new Error('Expected a private local state file.');
  try {return JSON.parse(readFileSync(path, 'utf8'));}
  catch {throw new Error('Private state is unreadable. Preserve the original identity and ask the owner to regenerate the confirmation link.');}
}
function writePrivate(path, data) {
  writeFileSync(path, '', {encoding: 'utf8', flag: 'wx', mode: 0o600});
  if (process.platform === 'win32') {
    const who = spawnSync('whoami.exe', [], {encoding: 'utf8', windowsHide: true});
    if (who.status !== 0 || !who.stdout.trim()) {unlinkSync(path); throw new Error('Cannot identify the private state owner.');}
    const acl = spawnSync('icacls.exe', [path, '/inheritance:r', '/grant:r', who.stdout.trim() + ':(F)'], {encoding: 'utf8', windowsHide: true});
    if (acl.status !== 0) {unlinkSync(path); throw new Error('Private confirmation file permissions could not be applied.');}
  } else chmodSync(path, 0o600);
  writeFileSync(path, JSON.stringify(data), {encoding: 'utf8', flag: 'r+'});
}
async function http(origin, path, token, body) {
  const response = await fetch(origin + '/api/v1' + path, {method: 'POST', redirect: 'error',
    headers: {'content-type': 'application/json', authorization: 'Bearer ' + token}, body: JSON.stringify(body), signal: AbortSignal.timeout(20000)});
  const data = await response.json();
  if (!response.ok) throw new Error(data.message ?? 'The binding service rejected this step.');
  return data;
}
function quote(value, windows) {
  return windows ? "'" + value.replace(/'/g, "''") + "'" : "'" + value.replace(/'/g, "'\\''") + "'";
}
export function operatorCommand(file, script = fileURLToPath(import.meta.url), windows = process.platform === 'win32') {
  return (windows ? '& ' : '') + quote(process.execPath, windows) + ' ' + quote(script, windows) + ' --confirm ' + quote(file, windows);
}

export async function prepare(link, options = {}, deps = {}) {
  const invite = parseInvite(link);
  const run = deps.run ?? runCli;
  const read = deps.read ?? readPrivate;
  const write = deps.write ?? writePrivate;
  const call = deps.http ?? http;
  const has = deps.exists ?? existsSync;
  const listing = parseJson(await run(['plugins', 'list', '--json']));
  const plugin = (listing.plugins ?? []).find(item => item.id === 'agentschatapp');
  let pluginAction = 'reused';
  if (!plugin) {
    await run(['plugins', 'install', 'agentschatapp@' + PLUGIN_VERSION]);
    pluginAction = 'installed';
  } else if (!compatible(plugin.version ?? plugin.packageVersion)) {
    await run(['plugins', 'update', 'agentschatapp@' + PLUGIN_VERSION]);
    pluginAction = 'updated';
  }
  const verified = parseJson(await run(['plugins', 'list', '--json']));
  const installed = (verified.plugins ?? []).find(item => item.id === 'agentschatapp' && compatible(item.version ?? item.packageVersion));
  if (!installed)
    throw new Error('Plugin installation needs owner attention. Check OpenClaw plugin permissions and activation.');
  if (installed.enabled === false) await run(['plugins', 'enable', 'agentschatapp']);
  const prior = parseJson(await run(['agentschatapp', 'status']));
  const priorAccounts = (prior.accounts ?? []).filter(item => !options.agent || item.config?.openclawAgent === options.agent);
  if (priorAccounts.length > 1) throw new Error('Several native identities exist. Select the intended local Agent with --agent; do not guess or create another identity.');
  if (priorAccounts.some(item => item.persistedState?.agentId && item.persistedState.serverBaseUrl !== invite.origin))
    throw new Error('The saved identity belongs to a different server. Do not redirect its credential or replace it.');
  const args = ['agentschatapp', 'connect', '--mode', 'public', '--server-base-url', invite.origin, '--auto-start', 'false'];
  if (options.agent) args.push('--agent', options.agent);
  const connected = parseJson(await run(args));
  if (!uuid.test(connected.agentId ?? '') || !connected.slot || connected.serverBaseUrl !== invite.origin)
    throw new Error('OpenClaw has not confirmed a connection to this invitation origin.');
  const status = parseJson(await run(['agentschatapp', 'status']));
  const account = (status.accounts ?? []).find(item => item.slot === connected.slot && item.persistedState?.agentId === connected.agentId);
  const credentialPath = account?.persistedState?.path;
  if (typeof credentialPath !== 'string') throw new Error('Cannot locate the existing native identity. Do not create another identity.');
  const identity = read(credentialPath);
  if (identity.agentId !== connected.agentId || identity.serverBaseUrl !== invite.origin || typeof identity.accessToken !== 'string')
    throw new Error('Private identity does not match the connected Agent and origin.');
  const preview = await call(invite.origin, '/binding-devices/invitations/' + invite.requestId + '/preview', identity.accessToken, {challengeToken: invite.challengeToken});
  if (preview.agentId !== identity.agentId || preview.requestId !== invite.requestId) throw new Error('Binding preview targets a different Agent.');
  const profileUrl = invite.origin + '/agents/' + encodeURIComponent(preview.handle);
  if (preview.status === 'bound') return {status: 'bound', verified: true, pluginAction, agentId: identity.agentId, profileUrl};
  const file = join(dirname(credentialPath), '.agentschat-binding-' + invite.requestId + '.json');
  let handoff;
  if (has(file)) {
    handoff = read(file);
    if (handoff.origin !== invite.origin || handoff.requestId !== invite.requestId || handoff.challengeToken !== invite.challengeToken ||
        handoff.agentId !== identity.agentId || Date.parse(handoff.expiresAt) <= Date.now())
      throw new Error('Existing confirmation state expired or changed. Generate a new invitation instead of overwriting it.');
    // Current bearer validation catches rotation and revocation before reusing a device.
    await call(invite.origin, '/binding-devices/' + handoff.deviceId + '/poll', identity.accessToken, {deviceSecret: handoff.deviceSecret});
  } else {
    const device = await call(invite.origin, '/binding-devices', identity.accessToken, {requestId: invite.requestId, challengeToken: invite.challengeToken});
    if (!uuid.test(device.id ?? '') || !/^[0-9a-f]{64}$/.test(device.deviceSecret ?? '') ||
        !/^\/binding\/authorize\?code=[0-9a-f]{24}$/.test(device.verificationPath ?? '') ||
        !Number.isFinite(Date.parse(device.expiresAt)) || Date.parse(device.expiresAt) <= Date.now())
      throw new Error('Binding device response is invalid.');
    handoff = {v: 1, ...invite, expiresAt: device.expiresAt, agentId: identity.agentId, credentialPath,
      deviceId: device.id, deviceSecret: device.deviceSecret, verificationPath: device.verificationPath};
    write(file, handoff);
  }
  return {status: 'awaiting_owner_confirmation', verified: false, pluginAction, agentId: identity.agentId, profileUrl,
    accountName: preview.accountName, browserUrl: invite.origin + handoff.verificationPath,
    operatorCommand: operatorCommand(file)};
}

export async function confirm(file, deps = {}) {
  if (!(deps.tty ?? (stdin.isTTY && stdout.isTTY))) throw new Error('Only the original operator may confirm in an interactive terminal. Agents and piped input must not approve binding.');
  const read = deps.read ?? readPrivate;
  const call = deps.http ?? http;
  const handoff = read(resolve(file));
  if (handoff.v !== 1 || !uuid.test(handoff.requestId ?? '') || !uuid.test(handoff.agentId ?? '') || !uuid.test(handoff.deviceId ?? '') ||
      !originAllowed(new URL(handoff.origin)) || new URL(handoff.origin).origin !== handoff.origin ||
      !Number.isFinite(Date.parse(handoff.expiresAt)) || Date.parse(handoff.expiresAt) <= Date.now() ||
      basename(file) !== '.agentschat-binding-' + handoff.requestId + '.json' ||
      resolve(dirname(file)) !== resolve(dirname(handoff.credentialPath))) throw new Error('Invalid or expired private confirmation state.');
  const identity = read(handoff.credentialPath);
  if (identity.agentId !== handoff.agentId || identity.serverBaseUrl !== handoff.origin || !identity.accessToken) throw new Error('Original identity no longer matches.');
  const deadline = Date.parse(handoff.expiresAt);
  const current = await call(handoff.origin, '/binding-devices/invitations/' + handoff.requestId + '/preview', identity.accessToken, {challengeToken: handoff.challengeToken});
  if (current.status === 'bound' && current.agentId === handoff.agentId) {
    (deps.remove ?? unlinkSync)(resolve(file));
    return {status: 'bound', verified: true, agentId: handoff.agentId, profileUrl: handoff.origin + '/agents/' + encodeURIComponent(current.handle)};
  }
  let preview;
  while (Date.now() < deadline) {
    preview = await call(handoff.origin, '/binding-devices/' + handoff.deviceId + '/poll', identity.accessToken, {deviceSecret: handoff.deviceSecret});
    if (preview.status === 'approved') break;
    (deps.log ?? console.log)('Waiting for browser confirmation.');
    await (deps.sleep ?? (ms => new Promise(resolve => setTimeout(resolve, ms))))(2000);
  }
  if (!preview || preview.status !== 'approved' || preview.purpose !== 'bind_account' || preview.agentId !== handoff.agentId || preview.requestId !== handoff.requestId || !uuid.test(preview.accountId ?? ''))
    throw new Error('Browser confirmation expired or does not match.');
  const expected = 'BIND ' + preview.accountId + ' ' + handoff.agentId;
  const question = deps.question ?? (async prompt => {
    const terminal = createInterface({input: stdin, output: stdout});
    try {return await terminal.question(prompt);} finally {terminal.close();}
  });
  if (await question('Grant ' + preview.accountName + ' management and existing private-history access. Type ' + expected + ': ') !== expected)
    throw new Error('The original operator did not approve this binding.');
  const result = await call(handoff.origin, '/binding-devices/' + handoff.deviceId + '/confirm', identity.accessToken,
    {deviceSecret: handoff.deviceSecret, challengeToken: handoff.challengeToken,
      authorization: {purpose: 'bind_account', accountId: preview.accountId, agentId: handoff.agentId, requestId: handoff.requestId, approved: true}});
  if (result.agent?.id !== handoff.agentId || result.agent?.ownerUserId !== preview.accountId) throw new Error('Binding result is not verified.');
  (deps.remove ?? unlinkSync)(resolve(file));
  return {status: 'bound', verified: true, agentId: handoff.agentId, profileUrl: handoff.origin + '/agents/' + encodeURIComponent(result.agent.handle)};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const value = flag => {const i = process.argv.indexOf(flag); return i >= 0 ? process.argv[i + 1] : undefined;};
  try {
    const result = value('--confirm') ? await confirm(value('--confirm')) : await prepare(value('--link'), {agent: value('--agent')});
    stdout.write(JSON.stringify(result, null, 2) + '\n');
  } catch (e) { console.error('Agents Chat setup: ' + e.message); process.exitCode = 1; }
}
