"""Build the reviewed native plugin archive without dependencies or credentials."""
from pathlib import Path
import argparse
import base64
import gzip
import hashlib
import io
import json
import subprocess
import tarfile

root = Path(__file__).resolve().parent.parent
source = root / "plugins" / "agentschatapp"
output = root / "web" / "public" / "downloads"
package = json.loads((source / "package.json").read_text(encoding="utf-8"))
manifest = json.loads((source / "openclaw.plugin.json").read_text(encoding="utf-8"))
assert package["name"] == manifest["id"] == "agentschatapp"
tracked = subprocess.check_output(["git", "ls-files", "-z", "plugins/agentschatapp"], cwd=root).decode().split("\0")
files = sorted(path.removeprefix("plugins/agentschatapp/") for path in tracked if path and (
    path.removeprefix("plugins/agentschatapp/") in {"package.json", "openclaw.plugin.json", "README.md"}
    or path.startswith("plugins/agentschatapp/dist/") and path.endswith(".js")))
assert {"package.json", "openclaw.plugin.json", "README.md", "dist/index.js"}.issubset(files)
buffer = io.BytesIO()
payloads = {}
with gzip.GzipFile(fileobj=buffer, mode="wb", filename="", mtime=0) as compressed:
    with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for relative in files:
            path = source / relative
            release_readme = source / "releases" / package["version"] / "README.md"
            if relative == "README.md" and release_readme.is_file():
                path = release_readme
            if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(source.resolve()):
                raise RuntimeError("Unexpected package path: " + relative)
            data = path.read_bytes().replace(b"\r\n", b"\n")
            data.decode("utf-8")
            payloads["package/" + relative] = data
            entry = tarfile.TarInfo("package/" + relative)
            entry.size, entry.mode, entry.mtime = len(data), 0o644, 0
            archive.addfile(entry, io.BytesIO(data))
data = buffer.getvalue()
filename = f"agentschatapp-{package['version']}.tgz"
parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
if args.check:
    # zlib and zlib-ng can compress identical tar streams differently. Verify
    # every published file against source, then hash the actual shipped bytes.
    data = (output / filename).read_bytes()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        members = archive.getmembers()
        if sorted(member.name for member in members) != sorted(payloads):
            raise SystemExit("Native plugin archive file inventory differs")
        for member in members:
            if (not member.isfile() or member.mode != 0o644 or member.uid != 0
                    or member.gid != 0 or member.mtime != 0):
                raise SystemExit("Unexpected native plugin archive entry: " + member.name)
            if archive.extractfile(member).read() != payloads[member.name]:
                raise SystemExit("Native plugin archive source differs: " + member.name)
digest = hashlib.sha256(data).hexdigest()
metadata = {"name": package["name"], "version": package["version"], "filename": filename,
    "sha256": digest, "npmShasum": hashlib.sha1(data).hexdigest(),
    "npmIntegrity": "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode(),
    "files": len(files), "minGatewayVersion": package["openclaw"]["compat"]["minGatewayVersion"],
    "nodeEngines": package["engines"]["node"]}
expected = {filename: data, filename + ".sha256": f"{digest}  {filename}\n".encode(),
    "agentschatapp.json": (json.dumps(metadata, indent=2) + "\n").encode()}
if args.check:
    for name, content in expected.items():
        if not (output / name).is_file() or (output / name).read_bytes() != content:
            raise SystemExit("Native plugin artifact differs: " + name)
else:
    output.mkdir(parents=True, exist_ok=True)
    for name, content in expected.items():
        (output / name).write_bytes(content)
print(json.dumps(metadata))
