"""Exercise the installers' real Git phase using only synthetic local repositories.

The script is stopped before adapter activation: no accounts, tasks, services or
background processes are created. Run with --shell sh or --shell powershell.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


parser = argparse.ArgumentParser()
parser.add_argument("--shell", choices=("sh", "powershell"), required=True)
options, remaining = parser.parse_known_args()
ADAPTER = Path(__file__).resolve().parent


class InstallerRepositoryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="agentschat-install-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.checkout = self.root / "installed"
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.run_command("git", "init", "-b", "main", str(self.source))
        self.git(self.source, "config", "user.name", "Synthetic Test")
        self.git(self.source, "config", "user.email", "synthetic@example.invalid")
        package = self.source / "skills/agents-chat-v1"
        package.mkdir(parents=True)
        (package / "version.txt").write_text("old\n", encoding="utf-8")
        (self.source / ".gitignore").write_text(".runtime/\n", encoding="utf-8")
        self.git(self.source, "add", ".")
        self.git(self.source, "commit", "-m", "synthetic old version")
        self.git(self.source, "branch", "stable")
        (package / "version.txt").write_text("main\n", encoding="utf-8")
        self.git(self.source, "commit", "-am", "synthetic main version")
        self.expected_commit = self.git(self.source, "rev-parse", "HEAD").stdout.strip()

    def run_command(self, *args, check=True):
        result = subprocess.run(args, cwd=self.root, env=self.env, capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=45)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def git(self, directory, *args):
        return self.run_command("git", "-C", str(directory), *args)

    def install(self):
        if options.shell == "powershell":
            executable = shutil.which("pwsh") or shutil.which("powershell")
            self.assertIsNotNone(executable, "PowerShell is required for this test")
            source = (ADAPTER / "install.ps1").read_text(encoding="utf-8")
            prefix, separator, _ = source.partition("$adapterScript = Join-Path $repoDir")
            self.assertTrue(separator, "Could not isolate installer before activation")
            script = self.root / "git-phase.ps1"
            script.write_text(prefix, encoding="utf-8")
            return self.run_command(executable, "-NoProfile", "-File", str(script),
                                    "-SkillRepo", self.source.as_uri(), "-Branch", "main",
                                    "-ServerBaseUrl", "https://synthetic.invalid", "-Slot", "same-slot",
                                    "-WorkDir", str(self.checkout), check=False)
        executable = shutil.which("bash") if os.name == "nt" else shutil.which("sh")
        if os.name == "nt" and Path("C:/Program Files/Git/bin/bash.exe").is_file():
            executable = "C:/Program Files/Git/bin/bash.exe"
        self.assertIsNotNone(executable, "A POSIX shell is required for this test")
        source = (ADAPTER / "install.sh").read_text(encoding="utf-8")
        prefix, separator, _ = source.partition('ADAPTER_SCRIPT="$REPO_DIR/')
        self.assertTrue(separator, "Could not isolate installer before activation")
        script = self.root / "git-phase.sh"
        script.write_text(prefix, encoding="utf-8", newline="\n")
        return self.run_command(executable, script.as_posix(), "--skill-repo", self.source.as_uri(),
                                "--branch", "main", "--server-base-url", "https://synthetic.invalid",
                                "--slot", "same-slot", "--work-dir", self.checkout.as_posix(), check=False)

    def legacy_checkout(self):
        self.run_command("git", "clone", "--depth", "1", "--single-branch", "--branch", "stable",
                         self.source.as_uri(), str(self.checkout))
        self.git(self.source, "branch", "-D", "stable")
        state = self.checkout / "skills/agents-chat-v1/adapter/.runtime/state.json"
        state.parent.mkdir(parents=True)
        state.write_text('{"agentId":"synthetic-existing-agent","slot":"same-slot"}', encoding="utf-8")
        return state, state.read_bytes()

    def test_new_install_uses_main(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current").stdout.strip(), "main")
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD").stdout.strip(), self.expected_commit)

    def test_shallow_stable_install_moves_to_main_and_keeps_identity(self):
        state, before = self.legacy_checkout()
        for _ in range(2):
            result = self.install()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.git(self.checkout, "branch", "--show-current").stdout.strip(), "main")
            self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD").stdout.strip(), self.expected_commit)
            self.assertEqual(state.read_bytes(), before)
        refs = self.git(self.checkout, "config", "--get-all", "remote.origin.fetch").stdout.splitlines()
        self.assertEqual(len(refs), len(set(refs)), "Repeated updates must not duplicate fetch rules")

    def test_local_conflict_stops_without_overwriting_work_or_identity(self):
        state, before = self.legacy_checkout()
        modified = self.checkout / "skills/agents-chat-v1/version.txt"
        modified.write_text("local work\n", encoding="utf-8")
        result = self.install()
        self.assertNotEqual(result.returncode, 0, "An unsuccessful checkout must stop the installer")
        self.assertEqual(modified.read_text(encoding="utf-8"), "local work\n")
        self.assertEqual(state.read_bytes(), before)


if __name__ == "__main__":
    unittest.main(argv=[__file__, *remaining])
