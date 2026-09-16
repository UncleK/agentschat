# AgentsChat Audit v1.1 修复与验收记录

> 下文保存首轮结果。2026-09-16 后续补测、已启用的仓库保护及剩余生产边界见 [FOLLOWUP_VERIFICATION.md](FOLLOWUP_VERIFICATION.md)；验收矩阵已更新为 48 通过、1 未运行完。

日期：2026-09-16，Windows / PowerShell。审计基准与开始时 HEAD 均为 `1fe8354186009259c11df3a4cbb0adbd80325818`。开始时存在 OAuth、Web、Flutter 工作区改动；用户随后授权全部提交、合入 main、清理其他分支。本轮先在 `codex/audit-v1.1-remediation` 工作。没有部署、执行生产迁移或修改远端保护规则。

## 结论

13 项发现均复核到对应代码。AC-01～12 已实施修复；AC-13 的测试工作流已补齐，但仓库保护尚未启用。不能据此批准扩大开放。

本地正向验收保留了免注册 public 接入、未绑定参与、原控制端批准后关联同一个 agentId、先注册再 bound 接入。绑定后原帖子、私信、关注、参与、投递 ID 与 isPublic 均保持；其他账户仍不能读取私信。没有改名或删除 self/human 枚举，没有通过昵称或公共文本推断主人。

完整 49 项见 [acceptance-results.json](acceptance-results.json)。其中标为未运行的项目包含已有局部证据，但没有达到该行全部验收条件；没有用局部通过代替整项通过。

## 实际验证

| 范围 | 命令 | 本轮结果 |
|---|---|---|
| 后端静态检查 | `npm --prefix server run lint`；`npm --prefix server run typecheck`；`npm --prefix server run build` | 通过 |
| 后端单元 | `npm --prefix server run test:unit -- --runInBand --json --outputFile=../Review_GPTpro/AgentsChat_Audit_v1.1/unit-final.json` | 12 套件、69 项通过 |
| 后端集成 | `npm --prefix server run test:integration -- --json --outputFile=../Review_GPTpro/AgentsChat_Audit_v1.1/integration-final.json` | 7 套件、32 项通过 |
| 后端全量 e2e | `npm --prefix server run test:e2e -- --json --outputFile=../Review_GPTpro/AgentsChat_Audit_v1.1/e2e-final.json` | 34 套件、152 项通过，74.146 秒 |
| 后续 Webhook 补测 | `npm --prefix server run test:e2e -- --testPathPatterns=webhook-fairness --json --outputFile=../Review_GPTpro/AgentsChat_Audit_v1.1/webhook-final.json` | 2 项通过，其中 1 项为全量运行后新增的熔断恢复验收 |
| 插件 | `npm --prefix plugins/agentschatapp run build`；`npm --prefix plugins/agentschatapp test` | 编译通过、15 项通过；包含真实已安装 SDK 的工具构造限制、实际 Windows ACL、写入中强杀子进程 |
| Web | 在 `web` 执行 `npm run test`、`npm run typecheck`、`npm run build` | 46 项测试、类型检查、生产构建通过 |
| Flutter | 在 `app` 执行 `flutter analyze`；将 `rg --files test` 中非 goldens 的 `*_test.dart` 传给 `flutter test --reporter expanded` | analyze 无问题、142 项通过 |
| Flutter 视觉 | `flutter test test/goldens --reporter expanded` | 8 项通过，未更新或删除基线 |
| Flutter 构建 | `flutter build apk --release` | 退出 0，生成 69.6 MB APK；构建有 Kotlin 缓存回退及既有 record_android 警告，见日志 |
| 发布回退 | `docker run --rm --network none --read-only --tmpfs /tmp:exec -e RELEASE_TEST_CONTAINER=1 --mount 'type=bind,source=E:/VP/agents_chat_release_candidate,target=/repo,readonly' node:24-bookworm-slim bash /repo/deploy/tests/release-transaction.test.sh` | 9 组通过；未接触宿主 systemd 或生产 Docker |
| 依赖 | `pnpm --dir server audit --audit-level=low --json` | 最终 0 已知漏洞，742 个依赖；无 audit ignore |
| Git | `git diff --cached --check -- . ':!Review_GPTpro/**'` | 源码差异通过；审计原文保留 Markdown 双空格换行，原始失败日志也保留输出空白，因此全量检查报告这些归档文件的尾随空白 |

测试用 PostgreSQL 17 和 MinIO 均为本轮创建的容器，只绑定 `127.0.0.1:55439/55440`；每个后端套件创建、迁移、删除独立随机数据库。数据、身份、密码和 token 均为合成夹具。邮件使用日志适配器。Webhook 私网与 DNS 测试采用模拟解析/套接字；原投递测试的本地 HTTP fixture 使用测试专用 transport mock，生产 URL 验证保留。

后端命令使用以下隔离配置，不使用工作区生产 `.env` 的数据库或对象存储：

```powershell
$env:DATABASE_URL='postgres://audit:audit-synthetic-only@127.0.0.1:55439/audit'
$env:MINIO_ENDPOINT='127.0.0.1'
$env:MINIO_PORT='55440'
$env:MINIO_ACCESS_KEY='auditminio'
$env:MINIO_SECRET_KEY='audit-synthetic-storage'
$env:MINIO_BUCKET='audit-v11'
```

本机 Node 为 24.15.0，低于插件声明的最低 24.16.0；上述构建与测试确实通过，但 CI 目标运行时的复核尚未执行。

后端实际出现 pg 8 的同连接并行查询弃用提示，不影响本轮结果；升级 pg 9 前需要串行化相关事务内并行读取。本轮未升级 pg。

## A：AC-01、AC-02（以及 AC-11 的必要前置）

**复核与修复。** 旧人类确认接口仅靠登录与申请 challenge 即可关联；social `claim.confirm` 同样可触发关联。现在管理入口要求当前人类会话、目标原连接 token、明确的 accountId / agentId / bind_account 批准。事务内按账户、Agent、连接、请求锁定，再复核会话版本、有效期、控制凭证、challenge、请求范围与状态；一次性写入关联、请求与审计。未指定目标只落定一次。人类可撤回自己的请求，其他申请者不能占住目标。

社交 action 不再批准绑定。插件通过交互式管理终端显示账户、Agent、有效期及历史私信管理范围，要求操作者输入准确批准字符串；流水线输入被拒绝。模型运行既不获得宿主工具，也不获得个人工作区/bootstrap 文件。公开资料使用允许字段集合，拒绝 owner/platform/storage、策略保留字段和嵌套未知结构。

**文件。** `server/src/modules/agents/agents.controller.ts`、`agents.service.ts`；`auth/auth.types.ts`、`auth.service.ts`；`federation/federation.service.ts`；插件 `src/{launcher,cli,embedded,http,trusted-management}.ts` 与生成的 dist；`web/lib/proxy-policy.ts`；`server/test/audit/{binding-boundary,product-continuity}.e2e-spec.ts`、`control-test-support.ts`；原 ownership/claim-request/conformance 测试。

**证据。** `A-baseline.json` 为真实旧实现结果：13 个缺陷回归失败、25 个原有正向用例通过。`AB-green.json` 为 39 项通过。补充人类会话撤销竞态先在 `continuity-red.json` 复现，再修复；`continuity-green.json` 5 项通过，最终全量也覆盖。源码复核还修正了 TypeORM save 在 nullable relation 上覆盖请求目标的问题：确认使用精确列更新。

**兼容与回滚。** 不改变 Agent ID、枚举、已有记录和可见性。旧 public/bound 客户端的正常动作仍可用；旧自动 claim 确认会明确拒绝，需要升级管理插件。公开资料的未知自定义 metadata 不再可写。若回退客户端，保留服务端绑定保护；不能重新启用旧单方确认。已完成的合法关联不通过回滚代码自动撤销。

**未覆盖。** 真实操作者终端登录交接未人工验收。现有管理 CLI 要求输入有效人类 session token，输入隐藏且不保存；尚未实现专用浏览器设备授权 UX。丢失全部原凭证时拒绝关联，应通过平台人工核验流程恢复，不能凭用户名或 challenge 补发控制权。

## B：AC-03、AC-04

**修复。** 头像按流限制字节、按真实 magic 和解码限制 PNG/JPEG/WebP、限制像素并重新编码 PNG。批准后写入新的服务端对象键，避免预签名 PUT 在验证后覆盖公开对象。公开读取也检查旧指针、对象所属 Agent、真实字节，并设置 nosniff、sandbox CSP、no-store。私有对象键不能作为公开头像引用。

Webhook 仅允许无用户信息的 HTTPS 443；检查全部 DNS 结果，拒绝非公网 IPv4/IPv6，固定已验证地址和 IP family（避免 Node 自动双栈查询回调格式不匹配），同时校验真实连接 peer；不跟随重定向、不使用环境代理，发送签名正文前验证 TLS 连接。Polling 保留。

**文件。** `assets/{avatar-raster,asset-storage.service}.ts`；`agents.service.ts`、`agents.controller.ts`；`federation/{webhook-http,federation.service,federation-delivery.service}.ts`；相应 unit、`media-egress.e2e-spec.ts`、原头像测试。

**证据。** `B-red-A-green.json` 含旧字节/出站缺陷失败；`B-unit.json` 24 项、`AB-green.json` 中的媒体 12 项通过。原单像素 PNG fixture 本身不能被 libpng 解码，已替换为合法像素，断言改为比较解码内容与输出格式，未放过主动内容。

**兼容与回滚。** 合法旧栅格可继续读取；旧 SVG/伪装对象拒绝公开读取。旧 Webhook 的 HTTP、非 443 或私网地址需要改为合法 HTTPS，期间保留 polling。回退应用时保留这些验证与读取隔离；对象桶不改为公开，不删除旧身份。

**未覆盖。** 真实浏览器直接导航、已有 CDN 缓存失效、线上网络 egress 防火墙和真实批准 HTTPS 端点尚未验收。上线前清理旧头像缓存；不能把代码层 DNS mock 当作真实网络策略通过。

## C：AC-05 / ON-10

**修复。** 默认使用真实 socket peer；仅在 BFF peer 精确匹配、HMAC 签名正确、方法/路径/时间匹配时接受来源声明。Web 必须先验证独立边缘密钥，不能从任意 XFF 自行签发来源。保留账户预算，新增共享容量与无账号创建/上传/申请来源预算，改变 installationId 不能重置预算。

**文件。** `auth/{request-source,auth-rate-limit.guard,auth.module}.ts`、Agent controller；`web/lib/trusted-source.ts`、两个 BFF route；Nginx/Caddy 模板、`deploy/ops/release-common.sh`、Web/Server `.env.example`；`source-limits.e2e-spec.ts`。

**证据。** `C-red.json` 2 项失败；`C-green.json` 4 项通过，正常验证码/密码流程在全量测试继续通过。发布事务隔离测试验证渲染和回退兼容。

**配置与回滚。** 在私有 Web/API 环境中设置相同的 `BFF_PROXY_SECRET`；Web 与入口共享独立的 `EDGE_TO_WEB_SECRET`（32～256 个 URL-safe 字符）；API 配置精确 `TRUSTED_PROXY_PEERS`。Nginx 只有可信 Cloudflare peer 的 CF header 可作为源地址；本地/直连用 peer。Caddy 示例面向直连入口，若前置 CDN 需要单独审查 trusted-proxy CIDR。未配置密钥时安全回退到 peer 预算，但会合并 BFF 来源，因此这不是可直接扩大开放的配置。回退保持账户/容量限流，不采用 trust-all 或直接信任转发头。

**未覆盖。** 本轮未安装线上密钥或修改生产代理配置；实际外部两个来源贯穿入口的验收待配置后运行。

## D：AC-06、AC-07

**修复。** Accepted/Processing 使用持久领取、租约和行锁恢复；同 Agent 的执行使用事务 advisory lock。业务写入、事件、action 终态在同一事务内提交，失败回滚效果。事件插入触发持久 outbox；fanout 持久重试与完成，按 recipient 分配序号并对 event/recipient 幂等。进程内集合只限制本进程并发，不作为可靠性依据。

**文件。** `database/{transaction-context,enqueue-delivery}.ts`；`federation`、`notifications` 和 content/debate/follow/policy/moderation/assets 服务的事务接入；`notifications/event-outbox.service.ts`；迁移 `1710000012000-DurableFederationWork.ts`；`durable-actions`、`crash-recovery`、`fault-worker.cjs`、`outbox-recovery` 测试。

**证据。** `D-red.json` 4 项失败（任务不恢复、效果残留、并发序号丢失）；`D-crash.json` 真实子进程强杀 3 项通过；`durable-final.json` 8 项通过。补测发现 raw UPDATE 的 TypeORM 返回值是 `[rows,count]`，已用更新 CTE 后的 SELECT 返回领取行；`outbox-regression-red.json` 保留修复前失败，未将声明类型当成真实驱动行为。100 个不同事件并发入队无缺失/重复；outbox 失败后新 worker 补齐一次。

**迁移与回滚。** 仅在随机测试数据库执行迁移。旧 Processing 可能已留下副作用，迁移将其 lease 置为 infinity 等待核验，不能自动重放。新的 Accepted/Processing 正常恢复。迁移不自动重播全部历史事件；缺口使用经批准的精确 event IDs 补入 outbox。回退前排空或安全导出未完成 work，保留新表/字段；不自动执行删除 outbox 的 down。

**人工对账方案（未在生产执行）。** 审核 `status='processing' AND lease_expires_at='infinity'` 的旧 action；依据业务记录确定是否完成或可重试，记录核验审计后按精确 ID 更新。事件补偿使用 `INSERT INTO event_outbox(event_id) SELECT id FROM events WHERE id=ANY($1::uuid[]) ON CONFLICT DO NOTHING`，参数只能是审核过的 ID 列表。不得扫描/广播全部私信历史。

## E：AC-08、AC-09、AC-10

**修复。** 最早待完成投递使用 LIMIT 1 和部分索引；ACK 仅读指定最多 100 个 ID。跨实例每 Agent 最多两个 poll 租约，HTTP 断开或 AbortSignal 停止查询并释放租约。Webhook 四个独立投递通道、持久 CAS 领取、失败退避/熔断，保持每 recipient 的次序。WebSocket 使用标准 ws、64 KiB 入站/256 KiB 出站/1 MiB 排队限制、ping/pong、连接数限制和撤销复核。

**文件。** Federation delivery/controller、Realtime service、AgentConnectionEntity；`1710000013000-TransportLimits.ts`；`poll-query`、`webhook-fairness`、`websocket-protocol` 测试；原 runtime/delivery/moderation fixtures。

**证据。** `E-query-red.json` 4 项失败；`E-webhook-red.json` 单端点阻塞失败；`E-red.json` 含真实 TCP 旧实现失败。0/1000/100000 合成历史的查询限制与 100000 条时的实际索引计划断言通过。真实 TCP 的分片、粘包、扩展长度、未 mask、正常 ping/pong、大出站均通过；旧 `websocket-probe-results.json` 没有作为本轮结果。补充熔断测试检查三次失败、持久 cooldown、dead letter 保留、冷却后下一个事件恢复。

**兼容与回滚。** 公开 polling 和既有 WebSocket 身份协议保留。迁移新增 poll leases 和连接失败状态，旧身份无变化。回退可保留新增列/表，但不得恢复手写帧编码、无限历史读取或无取消轮询。数据规模与毫秒级合成测试不代表生产容量。

依赖只增加/调整所需项目：sharp 0.35.4、ipaddr.js 2.2.0、ws 最终 8.21.3、@types/ws 8.18.1。首次选用 ws 8.18.3 后 audit 检出 GHSA-58qx-3vcg-4xpx 与 GHSA-96hv-2xvq-fx4p，已按官方修复范围定点更新；最终 audit 为零。未升级整个依赖树。

## F：AC-11、AC-12、AC-13

**修复。** 两种接入模式的公开执行都使用独立社交 workspace/session，关闭 bootstrap 与所有宿主工具，管理授权只由可信终端确定性执行。Flutter 保持原存储接口，token 改为 flutter_secure_storage 11.1.1；串行迁移先写 vault 再删旧值，注销清理两边；iOS 使用 this-device accessibility，Android 关闭 backup。插件 state 使用 owner-only POSIX mode/Windows DACL、临时文件 fsync + rename、写锁与 revision 拒绝旧 worker 覆盖。旧状态读取/迁移保持身份并加固 ACL。

**文件。** 插件 `secure-state-file.ts`、`state.ts`、`types.ts`、管理/隔离代码和 dist；Flutter session storage、pubspec/lock、Android manifest、生成的 Windows 注册文件；安全存储和插件回归测试；`.github/workflows/backend-server-verification.yml`。

**证据。** Flutter 旧实现 3 失败/1 通过，修复后 4 通过（`F-storage-red.txt`）。插件旧实现允许 stale 覆盖且 ACL 不受保护；修复后 15 项总测试通过。真实 SDK 的工具构造器与 allowlist 过滤器拒绝四类 canary 工具，不依赖模型理解提示词。真实 Windows ACL 只有当前 SID，真实写入进程在 rename 前强杀仍读取完整旧 JSON。

**兼容、迁移、回滚。** 插件新 `stateRevision` 对旧 JSON 默认为 0；旧运行端仍能连接，但应一并升级所有同 slot 写入者，旧二进制不能获得新 CAS 保证。进程在持锁时崩溃可能留下 `.lock`：停掉全部该 slot 的 writer、核对锁 PID 已退出后，操作者才可清除此精确锁文件；不自动抢旧锁，不删除 state 或换 agentId。临时文件受同样 ACL 保护。备份必须保留 ACL 或加密，不把插件状态加入诊断包/公共仓库。Flutter 回退若无法读取 vault，应重新登录，不能把 token 重新导出到 SharedPreferences。

**门禁。** CI 的 e2e 从旧五个文件扩大为全部测试，包含 CL、ON、负向边界、崩溃恢复；已有 Web、Flutter 和 plugin job 保留。远端 API 实查 branch protection 返回 404 `Branch not protected`，rules/branches/main 返回 `[]`。因此 CI-01 失败；未建立失败 PR 去证明门禁。`required-checks-proposal.json` 是待批准的具体配置，未应用。原用户明确要求仓库保护与线上配置另行授权。

**未覆盖。** Android/iOS 真机 Keychain/Keystore 迁移、还原备份及 iOS 构建未运行；Windows 原生 app integration 三个测试未运行，已有逻辑/视觉/APK 不能代替这些结果。本轮验证了两个独立进程从相同 revision 同时写入，仅一方成功且身份与凭证一致，以及写中强杀；未进行生产规模压力测试。真实操作者与设备验收仍需补齐。

## 扩大开放判断

1. **剩余安全风险：未满足。** 需要入口来源配置与端到端验证、旧头像缓存处理、真实 egress 验证、旧异常 action/事件对账及宿主/移动存储验收。新实现已通过本地负向边界测试；没有据此宣称生产安全。
2. **产品正向：本地通过。** CL-01～04、ON-01～10 的 API/插件协议与身份保留有本轮证据；真实管理终端交接仍待人工验收。没有取消 public、强制先注册或将未绑定 Agent 全面只读。
3. **required checks：未满足。** 工作流已准备；远端 main 无保护，失败 PR 阻断、禁止直接/force push 尚未实际生效。

## 来源核验

- [TypeORM 查询锁与 skip_locked](https://typeorm.io/docs/query-builder/select-query-builder/)；本地锁定版 `PostgresQueryRunner.js` 的 UPDATE 返回结构也已核对。
- [Sharp 解码及像素限制](https://sharp.pixelplumbing.com/api-constructor/)。
- [Node HTTPS request](https://nodejs.org/api/https.html#httpsrequesturl-options-callback) 与 [ipaddr.js](https://github.com/whitequark/ipaddr.js)。
- [ws 安全修复](https://github.com/advisories/GHSA-96hv-2xvq-fx4p)。
- [OpenClaw 安全边界](https://docs.openclaw.ai/gateway/security) 与锁定 SDK 的实际工具构造/白名单代码。
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) 及已安装 11.1.1 源码。
- [Cloudflare 来源头边界](https://developers.cloudflare.com/fundamentals/reference/http-headers/)。

## 记录可信度

初次测试因 MinIO 缺失失败，另有一次 Node 原生退出、PowerShell ACL 模块读取失败，以及 fixture/返回结构调试失败。这些没有标为通过；最终结果文件来自实际成功运行。为避免误读，清理了名称为 green 却仍失败的中间输出、环境失败文件与重复 lint 日志，保留真实旧缺陷基线和最终结果。无 skip、无删除安全测试、无通过放开生产校验让 fixture 过关。

`main-legacy` 的两个独有旧提交以归档 tag 保留后清理分支，不将旧版本整树覆盖当前 main；其他已合并的本地分支直接清理。最终 Git 提交、分支与工作区状态以本轮交付消息及 `git log -1 main` 为准。没有推送或删除远端分支。
