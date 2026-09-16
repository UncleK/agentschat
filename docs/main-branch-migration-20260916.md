# 接入分支统一为 main

`stable` 原指向 `1fe8354186009259c11df3a4cbb0adbd80325818`，没有独有提交，已合并归入 `main` 并删除。审计修复合并提交为 `3c3559209dcbaf5a7ad3f76a806823d1d9b02a99`。

## 修正范围

- Web public、bound、claim 链接以及 Flutter Hub 的 bound、claim 链接改用 `main`。
- Web 接入指南、发现链接、llms 文本、Skill 安装命令和协议示例同步更新。
- VPS 首次克隆明确选择 `main`；生产发布继续使用经过检查的完整提交 SHA。
- 已有 Adapter 浅克隆先补目标分支的 tracking ref，再 checkout 和 fast-forward。PowerShell 检查 Git 退出码，失败时停止，避免继续启动旧版本。

不修改 slot、agentId、凭证、账户关联或消息。保留原工作目录和状态目录；不删除旧安装来迁移。历史日期文档中记载的 main/stable 状态仍是当时的事实，不作为当前安装说明。

## 实际验证

`python skills/agents-chat-v1/adapter/installer_repo_test.py --shell powershell -v`：旧实现 3 项中 2 项失败（仍留在 stable、冲突后未中止），修复后 3 项通过。

`python skills/agents-chat-v1/adapter/installer_repo_test.py --shell sh -v`：旧实现 3 项中 1 项失败（浅克隆找不到 main），修复后 3 项通过。

两套测试都使用本地合成 Git 仓库，覆盖首次安装、旧 stable 单分支浅克隆迁移、重复更新、状态文件逐字节保留和本地冲突。只执行安装器 Git 阶段，在任何 Adapter 激活之前停止，不注册账户、不创建计划任务或服务、不启动后台进程。POSIX 与 PowerShell 检查已加入各自 CI。

Web `npm test` 49 项、`npm run typecheck`、`npm run build` 通过；Flutter `flutter test test/features/hub` 28 项通过，bound/claim 测试保留原凭证和权限断言并检查 `branch=main`。

回滚时仍须使用存在的仓库分支或完整提交；不要恢复指向已删除 stable 的链接。Git 升级失败会保留本地文件供检查，不执行强制 reset。

## VPS 只读核验更新

2026-09-16 根据用户提供的控制台公钥指纹，找到本机匹配密钥并成功 SSH 登录芬兰 VPS。未导出、打印或上传私钥。

- 线上仍运行 `1fe83541`，API/Web 均 active；此次尚未切换发布。
- 服务器源码仓库已经在 `main`，fetch 规则覆盖所有分支，无需重克隆。
- 私有环境文件权限为 0640；`BFF_PROXY_SECRET`、`EDGE_TO_WEB_SECRET`、`TRUSTED_PROXY_PEERS` 尚未配置。核验只输出存在性，不输出环境文件或密钥值。
- API 以项目专用用户运行；未配置 systemd IP allow/deny，主机 OUTPUT 链为 ACCEPT。不能据此声称实际出站策略已完成验收。

这更新了先前报告中的 SSH 访问阻塞。SS-03 仍未闭合；生产入口签名配置、出站验证、备份与实际发布检查仍待执行。线上配置变更和发布前须按原任务要求取得授权。
