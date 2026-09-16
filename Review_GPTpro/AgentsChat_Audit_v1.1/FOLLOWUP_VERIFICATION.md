# 剩余验收补测与发布边界

日期：2026-09-16。接续首轮本地 `248a8aff`；工作分支 `codex/audit-release-verification`，正式修复 PR [#7](https://github.com/UncleK/agentschat/pull/7)。本记录补充并更新 REMEDIATION_RESULTS.md 的首轮状态，不把首轮结果文件当作补测结果。

## 五项复核

| 验收 | 实际补测和修复 | 结论与边界 |
|---|---|---|
| AV-02 | Chromium 直接访问合法 PNG、历史栅格、旧 SVG、伪装 PNG、HTML；合法图片及嵌入正常，恶意字节 403，无脚本执行。未保护的合成 SVG 正对照确实执行。另经真实构建的 Next.js BFF 再测。 | 通过。发现 BFF 漏转发 CORP，先保存失败探针，再补转发；CSP、nosniff、CORP 与 no-store 均保留。 |
| AV-03 | 真实浏览器预先缓存可执行旧 SVG，证明来源修复后仍命中旧缓存；首次 Web 文档访问发出 `Clear-Site-Data: "cache"` 后重新读取安全 PNG。第二次不重复清缓存；cookie/localStorage 合成身份保持。Cloudflare 实查 API 绕过缓存，并按 Agent API 前缀清缓存。 | 通过已实施与隔离验收。生产新代码尚未切换，上线仍需确认响应头及清缓存路径生效。未删除存储对象或身份；已缓存内容仅在客户端重新访问站点后才可清理。 |
| SS-03 | 使用实际 HTTPS/TLS/socket、合成证书受信任 CA、固定 peer；一次签名正文投递成功，私网 DNS、错误证书名称和重定向均拒绝。Docker internal 网络关闭外部路由。 | **局部通过，整项仍未运行完**。测试没有替换生产 DNS/socket 函数，也未扫描真实内网；生产出站规则、入口签名配置仍需服务器访问才能实查。 |
| ST-01 | Android API 36.1 独立 AVD 和 macOS CI 的独立 iOS simulator：原生 vault 迁移、进程终止/重启读取、注销后再重启均通过。Android Backup Manager 在启用本地 transport 后拒绝备份该应用；iOS Release 无签名构建通过。会话 401/注销等 19 项测试通过。 | 通过当前验收条件。Android 新增 cloud/device transfer 显式全域排除，先红后绿。iOS 锁定依赖将 this-device 选项映射到 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。没有宣称硬件真机换机恢复、商店签名或上架已完成。 |
| CI-01 | main 启用严格 required checks、要求 PR、管理员同样受限、禁止 force push/删除。故意失败的 PR [#8](https://github.com/UncleK/agentschat/pull/8) 中 unit canary 实际失败，GitHub 返回 `mergeStateStatus=BLOCKED`。 | 通过。负向 PR 已关闭，探针分支与 worktree 已清理。实际保护绑定 GitHub Actions/Advanced Security 的 app ID；最终候选仍必须等待全部 required checks 通过后合并。 |

以上使矩阵变为 **48 通过、0 失败、1 未运行完（SS-03）**。这不是生产发布许可：仍需完成本节及下文明确列出的部署检查。

## 额外发现与最小修复

### B：旧浏览器缓存和 BFF 安全头

旧 API 可返回 `max-age=86400, stale-while-revalidate=604800`。新解码器无法撤回已进入浏览器的旧字节，因此增加一次性的页面访问缓存清理。只清 HTTP cache，不清 cookies/storage；cookie 只标记已采用的头像缓存策略。旧栅格仍可读取并重编码，不修改 Agent ID 或数据库枚举。BFF 增加 CORP 透传。

文件：`web/lib/avatar-cache-policy.ts`、`web/proxy.ts`、`web/app/api/v1/[...path]/route.ts`、`web/tests/avatar-cache-policy.test.ts`，浏览器 fixture/verify 脚本位于 `server/test/audit/avatar-*.{cjs,js}`。

证据：`AV-cache-red.log`、`AV-cache-browser.log`、`AV-browser-green.log`、`AV-bff-red.log`、`AV-bff-green.log`、`AV-cloudflare-evidence.json`。Playwright 的 `headers()` 省略部分安全头，最终探针使用 `allHeaders()`，未放宽响应头断言。

### D：同步分发与 outbox 的完成状态

CI 复现：同步通知发出后关联账户变化，后台 outbox 重新计算接收者，导致旧事件又通知新账户。先增强原回归，稳定得到预期 1 条、实际 2 条；再令同步调用与后台 worker 在同一 outbox 行锁内检查/写入完成状态，通知、投递与完成标记原子提交。锁顺序与 worker 一致。失败事务仍可重试；已完成事件不会因接收者后来变化而再次扩散。

文件：`server/src/modules/notifications/notifications.service.ts`、`server/test/reliability/runtime-boundaries.e2e-spec.ts`。无新数据库迁移。`D-recipient-replay-red.json` 是实际失败；`D-recipient-replay-green.json` 为相关 4 套件 21 项通过。测试夹具现在先建立参与者再发布事件，避免发布未完成的合成业务状态。未删除或放宽原断言。

### F：移动存储与 CI

Android 官方说明 `allowBackup=false` 在部分设备上不能覆盖设备间迁移，所以补充 `backup_rules.xml` 和 `data_extraction_rules.xml`，保留原关闭备份配置。`ST-backup-red.log` 先失败，`ST-backup-green.log` 5 项通过。`app/integration_test/session_storage_native_test.dart` 和 `app/test_driver/session_storage_test.dart` 使用实际平台插件，没有 mock channel。

Flutter 3.41.5 的 `flutter test`、默认 `flutter drive` 结束时会卸载应用，早期重启试验因此失败。最终使用 `flutter drive --keep-app-running`，阶段间用 adb/simctl 终止进程，保留安装与应用数据。各阶段独立进程，断言没有减少。

限流 CI 的 `ECONNRESET` 源于并发 Supertest 的临时 listener 被首个响应关闭；测试改为显式持有 listener，原 12 个 401/4 个 429 等断言保持。`CI-regression-green.json` 中限流和媒体共 14 项通过。

新 `.github/workflows/mobile-storage-verification.yml` 持续执行 iOS 原生存储及无签名 Release 构建。`required-checks-proposal.json` 现在是已应用的 11 项配置。待所有 required checks 通过后才允许合并 #7，不使用管理员绕过。

## CodeQL 逐条复核

- #15 动态正则：实际 Agent 查找先受 UUID 数据库查询约束；仍将键检查改为字面前缀加固定文件名正则，消除动态拼接。
- #12 密码哈希：定位点实际是 HMAC 签名服务器生成的会话 payload（用户 ID、过期、版本），不是密码存储；密码的 `hashPassword`/`verifyPassword` 使用随机盐 scrypt。保留算法和协议，按误报记录原因。
- #13/#14 跳转/XSS：`safeReturnPath` 只接受明确的本站路径前缀，拒绝反斜线和控制字符。补测实际 URL 解析器、两种语言、javascript/data、协议相对 URL、编码斜线、dot segments；均保持 HTTPS 本站 origin。未删除扫描规则，逐条以源码和测试依据标记误报。

`CodeQL-triage.json` 保存 GitHub 复核状态；扫描和告警检查仍在 required checks 中。

## 实际命令与结果

- Browser：`npx --yes --package @playwright/cli playwright-cli --session audit-avatar run-code --filename server/test/audit/avatar-browser.verify.js`，另运行 `avatar-bff.verify.js`、`avatar-cache.verify.js`。真实隔离 Chromium，HTTP fixtures 仅绑定 127.0.0.1:55441～55443，PostgreSQL/MinIO 仍是 55439/55440 的合成容器。
- TLS：先 `npm --prefix server run build`，以 `esbuild@0.25.12` 将实际 `server/dist/src/modules/federation/webhook-http.js` 打包；Docker `--internal --subnet 11.254.253.0/24` 内运行 `webhook-tls.fixture.cjs` / `webhook-tls.verify.cjs`。公网上可路由的形式只用于隔离网络内的合成 peer，不连接该真实公网地址。`NODE_EXTRA_CA_CERTS` 仅为本次合成证书；没有禁用 TLS 校验。实际结果在 `SS-real-tls.log`。
- Android：独立 `AgentsChat_Audit_Synthetic` AVD，`flutter drive --keep-app-running --target integration_test/session_storage_native_test.dart --driver test_driver/session_storage_test.dart -d emulator-5580 --dart-define=STORAGE_AUDIT_PHASE=<migrate|restart|logged-out>`。三阶段日志 `ST-android-*.log`；Backup Manager 结果 `ST-android-backup.log`。
- iOS：[CI 35039143916](https://github.com/UncleK/agentschat/actions/runs/35039143916) 三阶段原生 Keychain 均通过，Release 无签名产物 41.7 MB。原始阶段日志 `ST-ios-native/`，完整 job 日志 `ST-ios-ci.log`。模拟器每次新建并清理。
- 后端：本地新增相关 e2e 21 项和媒体/限流 14 项通过。Windows 全量进程退出 `-1073740791`，没有生成完整成功结果，保留 `e2e-followup-windows-abort.log`；不标记其通过。Linux CI [35039935075](https://github.com/UncleK/agentschat/actions/runs/35039935075) 实际运行后端全量，结果保存在 `e2e-followup-linux.json` 与 `backend-followup-ci.log`。
- Web：`npm test` 49 项、`npm run typecheck`、`npm run build` 通过；`web-followup.log`、`web-followup-build.log`。Flutter 会话相关 `flutter test ... --reporter expanded` 19 项通过，见 `ST-session-followup.log`。Windows 原生 app shell/hub/chat 及视觉检查在远端工作流已有成功结果，最终合并仍以当前 HEAD required checks 为准。

## 兼容、生产边界与回滚

public 免注册接入、未绑定社交参与、后续原控制端授权关联同一个 agentId、先注册再 bound 均继续由 CL-01～04、ON-01～10 在完整 e2e 中验收。未修改旧数据、站内身份或私信可见性策略；Human 不能冒充 Agent 作者。

本次实际外部修改仅有 GitHub 分支保护/PR/源分支和 Agents Chat 的 Cloudflare Agent API 缓存清除。没有生产代码切换、业务数据查询、生产迁移、服务重启、读取真实私信或发送真实凭证。服务器 SSH 公钥登录失败，生产验收未运行；不能把隔离 Docker 的出站成功写成生产 egress 已通过。

上线前仍必须完成：

1. 实查并配置独立 BFF/edge 签名密钥、精确 trusted peers；两个来源穿过真实入口的限流验收。
2. 实查出站规则，与 HTTPS/443、DNS pinning、peer 校验和不重定向的代码政策一致；使用受控合成 Webhook 完成生产出口的验收。
3. 备份后检查旧 `processing` action 是否需精确对账，以及历史 outbox 缺口是否需经批准补偿；不盲目重放历史私信。
4. 原操作者实际终端授权交接、精确发布 SHA、服务重启/回滚探针与发布后缓存响应头。移动商店发布另需正式 bundle ID、签名与商店流程；本次无签名构建不是上架产物。

回滚：缓存清除不改变用户数据；必要时可回退一次性 Web 清缓存逻辑，但保留字节校验与 BFF 安全头。Android 不回退为明文 token；无需新业务迁移。通知回退必须保留 durable checkpoint，避免重启后重放。GitHub 保护回滚是独立管理操作，本次保留已启用门禁。生产应用未部署，因此尚无本轮线上回退动作。

**扩大开放判断：** 产品正向与隔离安全回归有证据；生产安全配置及 SS-03 未闭合；required checks 已生效，候选必须全绿后合并。故当前还不能直接发布扩大开放。

参考：[Android 备份规则](https://developer.android.com/identity/data/autobackup)、[Clear-Site-Data](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Clear-Site-Data)、[GitHub 保护分支 API](https://docs.github.com/en/rest/branches/branch-protection)、[CodeQL 告警复核](https://docs.github.com/en/code-security/how-tos/manage-security-alerts/manage-code-scanning-alerts/resolve-alerts)。
