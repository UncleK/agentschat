import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { httpJson, normalizeBaseUrl, parseLauncherUrl } from './http.js';
// CLI-only. Never register as a model tool or delivery handler.
export async function approveBindingFromTerminal(state, launcherUrl) {
    if (!stdin.isTTY || !stdout.isTTY)
        throw new Error('Binding requires an interactive operator terminal. Public messages and piped input cannot approve it.');
    const launcher = parseLauncherUrl(launcherUrl);
    if (!state.serverBaseUrl || !state.accessToken || !state.agentId || launcher.mode !== 'claim' || !launcher.claimRequestId || !launcher.challengeToken)
        throw new Error('Binding requires a claimed slot and a valid claim launcher.');
    const base = normalizeBaseUrl(state.serverBaseUrl);
    if ((launcher.serverBaseUrl && normalizeBaseUrl(launcher.serverBaseUrl) !== base) || (launcher.agentId && launcher.agentId !== state.agentId))
        throw new Error('Binding launcher targets another server or agent.');
    const device = await httpJson('POST', `${base}/api/v1/binding-devices`, { requestId: launcher.claimRequestId, challengeToken: launcher.challengeToken }, state.accessToken);
    stdout.write(`Open in your browser: ${base}/binding/authorize?code=${encodeURIComponent(device.userCode)}\n`);
    const deadline = Date.now() + 600_000;
    while (Date.now() < deadline) {
        const preview = await httpJson('POST', `${base}/api/v1/binding-devices/${device.id}/poll`, { deviceSecret: device.deviceSecret }, state.accessToken);
        if (preview.status !== 'approved') {
            await new Promise(resolve => setTimeout(resolve, 2000));
            continue;
        }
        if (preview.purpose !== 'bind_account' || preview.agentId !== state.agentId || preview.requestId !== launcher.claimRequestId || typeof preview.accountId !== 'string')
            throw new Error('Authorization scope does not match the original controller.');
        stdout.write(`${JSON.stringify(preview, null, 2)}\n`);
        const expected = `BIND ${preview.accountId} ${state.agentId}`;
        const terminal = createInterface({ input: stdin, output: stdout });
        try {
            if (await terminal.question(`Grant this account management and existing private-history access. Type ${expected}: `) !== expected)
                throw new Error('Binding was not approved by the local operator.');
        }
        finally {
            terminal.close();
        }
        return httpJson('POST', `${base}/api/v1/binding-devices/${device.id}/confirm`, {
            deviceSecret: device.deviceSecret, challengeToken: launcher.challengeToken,
            authorization: { purpose: 'bind_account', accountId: preview.accountId, agentId: state.agentId, requestId: launcher.claimRequestId, approved: true }
        }, state.accessToken);
    }
    throw new Error('Browser authorization timed out.');
}
