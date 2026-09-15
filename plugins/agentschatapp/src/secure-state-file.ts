import { chmodSync, closeSync, existsSync, fsyncSync, lstatSync, openSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';

// Never interpolate paths or credentials into executable text.
export function protectStatePath(path: string): void {
  const info = lstatSync(path);
  if (info.isSymbolicLink()) throw new Error('State paths must not be symbolic links');
  if (process.platform !== 'win32') { chmodSync(path, info.isDirectory() ? 0o700 : 0o600); return; }
  const script = `$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue';
    $p=$env:AGENTSCHAT_SECURE_PATH; $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User;
    if ([System.IO.Directory]::Exists($p)) {
      $acl=New-Object System.Security.AccessControl.DirectorySecurity;
      $rule=New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow');
      $acl.SetAccessRuleProtection($true,$false); $acl.SetOwner($sid); $acl.AddAccessRule($rule);
      [System.IO.Directory]::SetAccessControl($p,$acl);
    } else {
      $acl=New-Object System.Security.AccessControl.FileSecurity;
      $rule=New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow');
      $acl.SetAccessRuleProtection($true,$false); $acl.SetOwner($sid); $acl.AddAccessRule($rule);
      [System.IO.File]::SetAccessControl($p,$acl);
    }`;
  execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')],
    { windowsHide: true, stdio: 'pipe', env: { ...process.env, AGENTSCHAT_SECURE_PATH: path } });
}

export function atomicStateWrite(path: string, value: unknown): void {
  const temp = `${path}.${randomUUID()}.tmp`;
  let fd: number | undefined;
  try {
    fd = openSync(temp, 'wx', 0o600);
    protectStatePath(temp);
    writeFileSync(fd, JSON.stringify(value, null, 2), 'utf8');
    fsyncSync(fd); closeSync(fd); fd = undefined;
    renameSync(temp, path);
  } finally {
    if (fd !== undefined) closeSync(fd);
    if (existsSync(temp)) unlinkSync(temp);
  }
}

export function lockedStateWrite<T>(path: string, work: () => T): T {
  const lock = `${path}.lock`;
  const until = Date.now() + 5000;
  let fd: number;
  while (true) {
    try { fd = openSync(lock, 'wx', 0o600); break; }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;
      // A dead writer's lock requires operator review. Automatic stale-lock
      // deletion could race a new owner and permit two concurrent writers.
      if (Date.now() >= until) throw new Error('State is busy; retry after the current writer exits');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25);
    }
  }
  try { writeFileSync(fd, String(process.pid)); fsyncSync(fd); return work(); }
  finally { closeSync(fd); unlinkSync(lock); }
}
