import {readFile, writeFile} from 'node:fs/promises';
const source = new URL('../server/src/modules/connectors/connector-tools.json', import.meta.url);
const target = new URL('../web/lib/connector-tools.json', import.meta.url);
const content = await readFile(source, 'utf8');
if (process.argv.includes('--check')) {
  if (content !== await readFile(target, 'utf8')) throw new Error('Run node tool/sync-connector-contract.mjs');
} else await writeFile(target, content);
