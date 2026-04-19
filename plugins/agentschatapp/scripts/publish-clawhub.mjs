import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(scriptDir, "..");
const packageJsonPath = join(pluginRoot, "package.json");
const pkg = JSON.parse(readFileSync(packageJsonPath, "utf8"));
const parsed = parseArgs(process.argv.slice(2));

if (parsed.help) {
  printHelp();
  process.exit(0);
}

const repoRoot = runCapture("git", ["rev-parse", "--show-toplevel"], {
  cwd: pluginRoot
}).trim();
const packageName = pkg.name;
const version = pkg.version;
const displayName = parsed.displayName ?? pkg.openclaw?.channel?.label ?? packageName;
const family = parsed.family ?? "code-plugin";
const sourcePath =
  parsed.sourcePath ??
  pkg.repository?.directory ??
  relative(repoRoot, pluginRoot).replace(/\\/g, "/");
const outputRoot =
  parsed.outputRoot ??
  join(repoRoot, "output", `${packageName}-clawhub-${version}`);
const publishRoot = join(outputRoot, "package");
const tgzPath = join(outputRoot, `${packageName}-${version}.tgz`);
const inferredSourceRepo = parsed.sourceRepo ?? inferGitHubRepo(pkg.repository);
const inferredSourceCommit = parsed.sourceCommit ?? runCapture("git", ["rev-parse", "HEAD"], {
  cwd: repoRoot
}).trim();
const dirtyTree = isDirtyTree(repoRoot);

if ((parsed.sourceRepo && !parsed.sourceCommit) || (!parsed.sourceRepo && parsed.sourceCommit)) {
  throw new Error("--source-repo and --source-commit must be set together.");
}

let effectiveSourceRepo = null;
let effectiveSourceCommit = null;

if (parsed.sourceRepo && parsed.sourceCommit) {
  effectiveSourceRepo = parsed.sourceRepo;
  effectiveSourceCommit = parsed.sourceCommit;
} else if (!dirtyTree && inferredSourceRepo && inferredSourceCommit) {
  effectiveSourceRepo = inferredSourceRepo;
  effectiveSourceCommit = inferredSourceCommit;
} else if (dirtyTree) {
  console.warn(
    "Git working tree is dirty; omitting source metadata so ClawHub does not point at mismatched source."
  );
  console.warn("Commit first if you want --source-repo / --source-commit to be attached automatically.");
}

preparePublishFolder({
  outputRoot,
  pluginRoot,
  tgzPath
});

const clawhubArgs = [
  "package",
  "publish",
  "--family",
  family,
  "--display-name",
  displayName,
  "--version",
  version
];

if (parsed.changelog) {
  clawhubArgs.push("--changelog", parsed.changelog);
}

if (effectiveSourceRepo && effectiveSourceCommit) {
  clawhubArgs.push(
    "--source-repo",
    effectiveSourceRepo,
    "--source-commit",
    effectiveSourceCommit,
    "--source-path",
    sourcePath
  );
}

clawhubArgs.push(publishRoot);

if (parsed.prepareOnly) {
  console.log(`Prepared ClawHub package folder: ${publishRoot}`);
  console.log(`Packed tarball: ${tgzPath}`);
  console.log("");
  console.log("Publish command:");
  console.log(formatCommand(getExecutableName("clawhub"), clawhubArgs));
  process.exit(0);
}

runCommand(getExecutableName("clawhub"), clawhubArgs, { cwd: pluginRoot });

function preparePublishFolder({ outputRoot, pluginRoot, tgzPath }) {
  rmSync(outputRoot, { recursive: true, force: true });
  mkdirSync(outputRoot, { recursive: true });

  runCommand(getExecutableName("npm"), ["pack", "--pack-destination", outputRoot], {
    cwd: pluginRoot
  });

  if (!existsSync(tgzPath)) {
    throw new Error(`Expected packed tarball was not created: ${tgzPath}`);
  }

  runCommand("tar", ["-xf", tgzPath, "-C", outputRoot], { cwd: pluginRoot });

  if (!existsSync(publishRoot)) {
    throw new Error(`Expected extracted package folder was not created: ${publishRoot}`);
  }
}

function parseArgs(argv) {
  const parsed = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    switch (arg) {
      case "--changelog":
        parsed.changelog = readValue(argv, ++index, arg);
        break;
      case "--display-name":
        parsed.displayName = readValue(argv, ++index, arg);
        break;
      case "--family":
        parsed.family = readValue(argv, ++index, arg);
        break;
      case "--output-root":
        parsed.outputRoot = resolve(readValue(argv, ++index, arg));
        break;
      case "--prepare-only":
        parsed.prepareOnly = true;
        break;
      case "--source-commit":
        parsed.sourceCommit = readValue(argv, ++index, arg);
        break;
      case "--source-path":
        parsed.sourcePath = readValue(argv, ++index, arg);
        break;
      case "--source-repo":
        parsed.sourceRepo = readValue(argv, ++index, arg);
        break;
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}

function readValue(argv, index, flagName) {
  const value = argv[index];
  if (!value) {
    throw new Error(`Missing value for ${flagName}`);
  }
  return value;
}

function inferGitHubRepo(repository) {
  const raw = typeof repository === "string" ? repository : repository?.url;
  if (!raw) {
    return null;
  }
  const match = raw.match(/github\.com[:/](.+?)(?:\.git)?$/i);
  return match?.[1] ?? null;
}

function isDirtyTree(cwd) {
  return runCapture("git", ["status", "--porcelain"], { cwd }).trim().length > 0;
}

function getExecutableName(baseName) {
  return baseName;
}

function runCapture(command, args, options) {
  const invocation = createSpawnInvocation(command, args);
  const result = spawnSync(invocation.command, invocation.args, {
    ...options,
    encoding: "utf8",
    shell: invocation.shell
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const message = result.stderr?.trim() || result.stdout?.trim() || `Command failed: ${command}`;
    throw new Error(message);
  }

  return result.stdout ?? "";
}

function runCommand(command, args, options) {
  console.log(`> ${formatCommand(command, args)}`);
  const invocation = createSpawnInvocation(command, args);
  const result = spawnSync(invocation.command, invocation.args, {
    ...options,
    stdio: "inherit",
    shell: invocation.shell
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function createSpawnInvocation(command, args) {
  if (process.platform === "win32") {
    return {
      command: formatCommand(command, args),
      args: [],
      shell: true
    };
  }

  return {
    command,
    args,
    shell: false
  };
}

function formatCommand(command, args) {
  return [command, ...args].map(quoteArg).join(" ");
}

function quoteArg(value) {
  if (/^[A-Za-z0-9_./:\\-]+$/.test(value)) {
    return value;
  }
  return JSON.stringify(value);
}

function printHelp() {
  console.log(`Usage: node ./scripts/publish-clawhub.mjs [options]

Prepare a clean publish folder from npm pack output and optionally publish it to ClawHub.

Options:
  --changelog <text>      Changelog text to attach to the ClawHub release
  --display-name <name>   Override display name (default: package openclaw channel label)
  --family <family>       code-plugin or bundle-plugin (default: code-plugin)
  --output-root <path>    Override the temporary publish folder root
  --prepare-only          Prepare the folder and print the final clawhub command without publishing
  --source-repo <repo>    Explicit GitHub repo override; must be paired with --source-commit
  --source-commit <sha>   Explicit commit override; must be paired with --source-repo
  --source-path <path>    Repo subpath override (default: repository.directory)
  -h, --help              Show this help
`);
}
