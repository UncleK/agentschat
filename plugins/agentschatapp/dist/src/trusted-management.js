import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { confirmClaimLauncher } from './launcher.js';
// Deliberately CLI-only: never registered as a model tool, channel command or
// delivery handler. The social runner has no tools and no operator workspace.
export async function approveBindingFromTerminal(state, launcher) {
    if (!stdin.isTTY || !stdout.isTTY) {
        throw new Error('Binding requires an interactive operator terminal. Public messages and piped input cannot approve it.');
    }
    const humanAccessToken = await readSecret();
    return confirmClaimLauncher(state, launcher, {
        humanAccessToken,
        approve: async (preview) => {
            stdout.write(`\n${JSON.stringify(preview, null, 2)}\n`);
            const expected = `BIND ${String(preview.accountId)} ${String(preview.agentId)}`;
            const terminal = createInterface({ input: stdin, output: stdout });
            try {
                return await terminal.question(`To grant this account management and existing private-history access, type ${expected}: `) === expected;
            }
            finally {
                terminal.close();
            }
        }
    });
}
async function readSecret() {
    stdout.write('Current AgentsChat human session token (hidden; never saved): ');
    stdin.setRawMode(true);
    stdin.resume();
    return new Promise((resolve, reject) => {
        let value = '';
        const finish = (error) => {
            stdin.off('data', onData);
            stdin.setRawMode(false);
            stdin.pause();
            stdout.write('\n');
            if (error)
                reject(error);
            else
                resolve(value.trim());
        };
        const onData = (chunk) => {
            for (const char of chunk.toString()) {
                if (char === '\u0003') {
                    finish(new Error('Binding cancelled.'));
                    return;
                }
                if (char === '\r' || char === '\n') {
                    finish();
                    return;
                }
                if (char === '\u007f')
                    value = value.slice(0, -1);
                else
                    value += char;
            }
        };
        stdin.on('data', onData);
    });
}
