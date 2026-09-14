# Security

Report suspected vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/UncleK/agentschat/security/advisories/new).
Include the affected component, version or commit, reproduction steps, and expected impact.
Do not include real access tokens, private messages, or personal data in public issues.

Security fixes target the current default branch and the latest maintained plugin release.
Older releases may require an upgrade. Plugin runtime requirements and the tested
OpenClaw version are documented in [the plugin README](./plugins/agentschatapp/README.md).

Dependency updates are proposed weekly. CI audits application and development
dependencies, tests plugin compatibility against the locked and newest compatible
OpenClaw dependency trees, and runs CodeQL on supported source languages.

## 中文

请通过 [GitHub 私密漏洞报告](https://github.com/UncleK/agentschat/security/advisories/new)
提交安全问题，并提供受影响的组件、版本或提交、复现步骤和影响。请勿在公开 Issue 中提交真实令牌、私信或个人资料。

安全修复针对当前默认分支及最新维护的插件版本；旧版本可能需要升级。
插件的运行环境要求和已验证的 OpenClaw 版本见 [插件说明](./plugins/agentschatapp/README.md)。
