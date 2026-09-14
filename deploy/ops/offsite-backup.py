#!/usr/bin/env python3
"""Encrypt a completed backup; optionally upload to this project's private R2 bucket."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path('/opt/agents-chat')
CONFIG = Path('/etc/agents-chat/offsite.env')
BACKUPS = ROOT / 'backups'
REPORT = BACKUPS / 'reports/offsite-backup.json'


def main():
    if os.geteuid() != 0:
        raise RuntimeError('Run this backup as root.')
    if not CONFIG.exists():
        print('Offsite backup is not configured; local backups remain available.')
        return
    env = json.loads(subprocess.check_output([
        str(ROOT / 'runtime/bin/node'), '--env-file=' + str(CONFIG), '-e',
        'console.log(JSON.stringify(Object.fromEntries(Object.entries(process.env)'
        '.filter(([k])=>k.startsWith("R2_")||k==="BACKUP_AGE_RECIPIENT"))))',
    ], text=True))
    recipient = env.get('BACKUP_AGE_RECIPIENT', '')
    if not re.fullmatch(r'age1[a-z0-9]{58}', recipient):
        raise RuntimeError('Set a valid age recovery public key.')
    manifest = dict(line.split('=', 1) for line in
                    (BACKUPS / 'reports/latest-backup.txt').read_text().splitlines())
    timestamp = manifest['timestamp']
    if not re.fullmatch(r'\d{14}', timestamp):
        raise RuntimeError('Invalid backup timestamp.')
    sources = []
    for key in ('postgres_dump', 'minio_archive'):
        path = Path(manifest[key]).resolve(strict=True)
        path.relative_to(BACKUPS)
        sources.append(str(path.relative_to('/')))
    encrypted_dir = BACKUPS / 'encrypted'
    encrypted_dir.mkdir(mode=0o700, exist_ok=True)
    target = encrypted_dir / ('agents-chat-' + timestamp + '.tar.age')
    if not target.exists():
        partial = target.with_suffix('.age.partial')
        with partial.open('wb') as output:
            archive = subprocess.Popen([
                'tar', '-czf', '-', '--exclude=*recovery*', '-C', '/',
                *sources, 'etc/agents-chat',
                'opt/agents-chat/current/.source-commit',
            ], stdout=subprocess.PIPE)
            encryption = subprocess.run(['age', '-r', recipient],
                                        stdin=archive.stdout, stdout=output)
            archive.stdout.close()
            archive_status = archive.wait()
        if archive_status or encryption.returncode:
            partial.unlink(missing_ok=True)
            raise RuntimeError('Backup encryption failed.')
        partial.replace(target)
    with target.open('rb') as body:
        digest = hashlib.file_digest(body, 'sha256').hexdigest()
    cutoff = time.time() - 7 * 86400
    for path in encrypted_dir.glob('agents-chat-*.tar.age'):
        if path.stat().st_mtime < cutoff:
            path.unlink()
    report = {'timestamp': timestamp, 'encrypted_file': str(target),
              'sha256': digest, 'bytes': target.stat().st_size,
              'remote_status': 'awaiting_bucket_credentials'}
    REPORT.write_text(json.dumps(report, indent=2) + '\n')
    if not env.get('R2_ACCESS_KEY_ID') or not env.get('R2_SECRET_ACCESS_KEY'):
        print('Encrypted backup created; R2 upload awaits bucket-scoped credentials.')
        return
    account = env.get('R2_ACCOUNT_ID', '')
    bucket = env.get('R2_BUCKET', '')
    if not re.fullmatch(r'[a-f0-9]{32}', account) or bucket != 'agents-chat-backups':
        raise RuntimeError('Destination must be this project\'s private R2 bucket.')
    import boto3
    from botocore.config import Config
    client = boto3.client('s3', endpoint_url=f'https://{account}.r2.cloudflarestorage.com',
                          aws_access_key_id=env['R2_ACCESS_KEY_ID'],
                          aws_secret_access_key=env['R2_SECRET_ACCESS_KEY'], region_name='auto',
                          config=Config(retries={'max_attempts': 3},
                                        connect_timeout=10, read_timeout=60,
                                        s3={'addressing_style': 'path'}))
    key = 'daily/' + target.name
    listing = client.list_objects_v2(Bucket=bucket, Prefix='daily/', MaxKeys=1000)
    if listing.get('IsTruncated'):
        raise RuntimeError('Unexpected backup object count; review before uploading.')
    objects = listing.get('Contents', [])
    projected = sum(o['Size'] for o in objects if o['Key'] != key) + target.stat().st_size
    cap = min(int(env.get('R2_MAX_TOTAL_BYTES', 2 * 1024**3)), 2 * 1024**3)
    if projected > cap:
        raise RuntimeError('Project R2 backup cap exceeded; upload was not attempted.')
    with target.open('rb') as body:
        client.put_object(Bucket=bucket, Key=key, Body=body,
                          ContentType='application/octet-stream', Metadata={'sha256': digest})
    restored = client.get_object(Bucket=bucket, Key=key)['Body']
    remote_hash = hashlib.sha256()
    for chunk in restored.iter_chunks(chunk_size=1024 * 1024):
        remote_hash.update(chunk)
    restored.close()
    if remote_hash.hexdigest() != digest:
        raise RuntimeError('R2 download checksum mismatch.')
    report.update(remote_status='verified', bucket=bucket, key=key)
    REPORT.write_text(json.dumps(report, indent=2) + '\n')
    for obj in objects:
        if (re.fullmatch(r'daily/agents-chat-\d{14}\.tar\.age', obj['Key'])
                and obj['LastModified'].timestamp() < cutoff):
            client.delete_object(Bucket=bucket, Key=obj['Key'])
    print('R2 encrypted backup uploaded and downloaded checksum verified.')


if __name__ == '__main__':
    os.umask(0o077)
    try:
        main()
    except Exception as error:
        print(f'Offsite backup failed: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)
