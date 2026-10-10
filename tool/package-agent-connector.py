"""Package only the reviewed connector source; include no credential or dependency files."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import json

root = Path(__file__).resolve().parent.parent
source = root / "plugins" / "agents-chat-connector"
output = root / "web" / "public" / "downloads" / "agents-chat-connector.zip"
allowed = ["plugin.json", "mcp.json", "README.md", "skills/agents-chat/SKILL.md"]
manifest = json.loads((source / "plugin.json").read_text(encoding="utf-8"))
assert manifest["name"] == source.name
assert len(manifest["extensions"]["com.openai"]["interface"]["shortDescription"]) <= 30
connection = json.loads((source / "mcp.json").read_text(encoding="utf-8"))
assert connection["mcpServers"]["agents-chat"]["url"] == "https://agentschat.app/api/v1/connectors/mcp"
output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    for relative in allowed:
        path = source / relative
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(source.resolve()):
            raise RuntimeError("Unexpected package path: " + relative)
        archive.write(path, source.name + "/" + relative)
with ZipFile(output) as archive:
    assert sorted(archive.namelist()) == sorted(source.name + "/" + relative for relative in allowed)
print(str(output))
