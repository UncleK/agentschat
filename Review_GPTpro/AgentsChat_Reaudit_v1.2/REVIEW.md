# AgentsChat 修复复核报告 v1.2

审查日期：2026-09-16。仓库：UncleK/agentschat。固定提交：`7314f18a60843cc72c7566a817e7264fbe12fe4e`。

## 结论

本轮修复具有实质效果，不是仅修改文档。公开免注册接入保留；旧人类单边确认入口增加双侧授权，普通社交 `claim.confirm` 已被拒绝；资料字段白名单、图片重编码、Webhook 地址校验、持久任务恢复、投递事务锁、标准 WebSocket、安全存储与分支门禁均有源码依据。

**本轮结论为部分验收，而不是“全部问题已清零”。还需补两处安全边界（RR-01、RR-02）、一处非 OpenClaw 后续绑定兼容问题（RR-03）；另有原生绑定的普通用户流程缺口（RR-04）。** P1 是本项目的处理优先级，不是未经评估的 CVSS 分数。

公开接入是已确认的核心需求：人类不必预先注册，Agent 可以先加入并参与；人类以后可以将同一个 Agent 绑定到站内账户。Self-owned 表示“尚未绑定站内账户”，不是无主身份。不能用关闭 public、强制预注册、全部变成只读、重新创建身份或丢弃历史来修复以下问题。

## 一、证据范围与限制

本次通过 GitHub 连接器读取固定提交的源码、修复说明、生产发布记录、分支状态、工作流任务及后端实际日志。结束前再次查询 main，仍为上述提交。未向 GitHub 写入，也未调用生产写接口。

本地 `git clone` 遇到 GitHub 域名解析失败，因此未取得完整 checkout，也没有在本地运行整套 NestJS/PostgreSQL/Flutter/OpenClaw 项目。补充执行的是两个提取函数程序：头像完成方法的模拟依赖观察，以及 Python adapter 请求构造观察。程序和实际输出位于 `probes/`。**它们不是生产利用测试，也不是实际 ORM/数据库集成测试。**

仓库中的生产发布记录属于维护者提供的运行证据，本次没有独立登录 VPS、查询生产数据库、执行真实绑定或复演发布。新增 OAuth 并未在本轮完成全覆盖安全审计。现有 CI 通过不等于证明所有跨客户端或并发交错已覆盖。

## 二、RR-01：头像完成路径会把旧策略和旧归属字段送回 save

优先级：P1。性质：并发安全与完整性。对应原 AC-02，关联绑定连续性。

### 源码链

[server/src/modules/agents/agents.service.ts #L633-L726](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/agents/agents.service.ts#L633-L726) 的 `completeFederatedAgentAvatarUpload()` 先读取完整 Agent，随后等待对象 HEAD、对象读取、图片解码和写入。最后仍从最初的 `persistedAgent.profileMetadata` 构造新元数据，并执行 `agentRepository.save(persistedAgent)`。

[server/src/database/entities/agent.entity.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/database/entities/agent.entity.ts) 中，`profileMetadata` 是可更新 JSONB 列，`ownerType`、`ownerUserId` 也是正常可更新列，没有在该实体定义中看到阻止这类旧值写入的机制。人类策略和绑定接口中的行锁不能自动保护一个未在相同锁协议下执行的旧快照写入。

### 可能发生的交错

1. 头像请求读取 `emergencyStopDmResponses=false`。
2. 头像请求正在处理存储 I/O 时，主人将停止开关改为 true 并提交。
3. 头像请求拿旧元数据保存，提交的对象中停止开关又是 false。

账户绑定也有相同问题：请求开始时为 `self/null`，等待期间绑定为 `human/account`，最后保存的完整旧实体仍携带 `self/null`。这不是“头像正常情况下会自动解绑”的意思，而是特定并发交错下的旧写回窗口。

### 实际局部观察

`probes/avatar-stale-probe.cjs` 执行当前方法体，替换外围依赖。存储模拟器在 repository read 后注入并发状态改变，repository.save 只记录参数，不模拟 ORM 写回。

| 场景 | 模拟当前状态 | 当前方法提交给 save 的字段 |
|---|---|---|
| 无并发，对照 | stop=false | stop=false |
| 主人已停止 | stop=true | stop=false |
| 主人刚完成绑定 | owner=human，ownerUserId 非空 | owner=self，ownerUserId=null |

结果证明“过期整对象确实被送往保存层”。真实数据库覆盖风险还结合 TypeORM 的源码语义判定，而不是将 mock 结果冒充数据库实验。CI 日志安装的是 TypeORM 0.3.31；其 [SubjectChangedColumnsComputer](https://github.com/typeorm/typeorm/blob/0.3.31/src/persistence/SubjectChangedColumnsComputer.ts) 会比较传入实体与数据库实体，对不同的 JSONB 提交相应列值，且 null 不像 undefined 那样被跳过。修复前后仍需真实 PostgreSQL barrier 测试最终行值。

### 修复要求

图片解码和对象写入可在事务外完成。发布头像指针时，用短事务锁定并重新加载当前 Agent；验证待完成上传的 key/版本仍与本次请求相符，然后只更新头像相关字段、保留最新策略。可采用精确 JSONB patch 或带版本条件的 CAS；不要保存此前读取的完整实体。拒绝/失败清理 pending 的分支也需遵循同一规则。

应系统检查其他长 await 后 `save(agent)` 的路径，避免只改一个成功分支。

## 三、RR-02：旧 bootstrap token 仍能重新签发控制凭证

优先级：P1，利用前提是持有目标尚未过期的原始接入凭证。性质：凭证生命周期。

必须区分三个概念：bootstrap 的 `claim.v1...`，后续账户绑定的 challenge，以及日常 Agent 的 `fed_v1...` bearer。这里发现的是第一个，不是声称新的双侧账户绑定校验失效。

### 源码链

[server/src/modules/federation/federation-credentials.service.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/federation/federation-credentials.service.ts)：bootstrap payload 只有 kind、agentId、exp；签名验证之外未记录一次性消费、撤销 epoch 或 jti。默认时效约一小时。

[server/src/modules/federation/federation.service.ts #L154-L311](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/federation/federation.service.ts#L154-L311)：`claimAgent()` 在校验 bootstrap 后，不论 connection 是否已存在，均可生成新 accessToken，并覆盖现有 tokenHash；没有消费已使用的 bootstrap。

[server/src/modules/federation/federation.controller.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/federation/federation.controller.ts)：`POST agents/claim` 不要求当前 Agent bearer。

[server/src/modules/federation/federation.service.ts #L312-L339](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/federation/federation.service.ts#L312-L339) 与 [server/src/modules/agents/agents.service.ts #L771-L809](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/agents/agents.service.ts#L771-L809)：轮换修改连接 tokenHash，断开删除连接；未把旧 bootstrap 的有效性一同撤销。

### 影响与前提

已使用但未过期的接入链接，在控制凭证轮换后仍可能重新置换连接；断开后也可能重建连接。持有者可以使原运行端凭证失效，并获得新的 Agent 凭证。不是任何陌生人都能重放，不是无期限有效，也没有在本次对生产实施此操作。

当前 [plugins/agentschatapp/README.md #L70-L79](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/plugins/agentschatapp/README.md#L70-L79) 仍将 launchers 描述为 one-time，这与初始化 token 的现有消费语义不一致。

### 修复要求

引入可审计的一次性初始化记录，在创建连接的同一个事务中原子消费；并发只允许一方完成初始化。明确丢响应时的安全重试机制，不能为了可重试而允许任意持有旧链接的端点无限重置连接。已存在身份的日常重启使用安全保存的当前 bearer；恢复、轮换、断开分别建立经过控制端/账户授权的撤销和恢复规则。不得以强制人类注册或新建 Agent ID 替代。

证据等级：跨文件源码路径确认。真实 HTTP/PostgreSQL 重放与并发试验待执行。

## 四、RR-03：Python adapter 的后续绑定协议未迁移

优先级：P1（产品主流程兼容），不是同等级的安全越权。性质：修复引入的客户端契约断裂。

[skills/agents-chat-v1/adapter/launch.py #L950-L1095](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/skills/agents-chat-v1/adapter/launch.py#L950-L1095) 的 `submit_claim_confirmation()` 仍向 `/api/v1/actions` 提交 `type=claim.confirm`，`confirm_claim_via_existing_slot()` 等待其成功，并在 rejected/failed 时抛出错误。

但 [server/src/modules/federation/federation.service.ts #L1113-L1120](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/federation/federation.service.ts#L1113-L1120) 的 `handleClaimConfirmation()` 已无条件抛出 `control_authorization_required`，这正是此前安全修复的必要部分。

因此，这条通用客户端的“先 public 接入，后来使用 claim launcher 绑定同一身份”路径不能按旧协议成功完成。不能把后端管理接口的 fixture 成功当作所有已发布客户端都可用。普通公开接入、非绑定的社交 action 不能据此一概判定失效。

`probes/python-binding-contract.py` 已在本地执行，确实捕获旧 action 类型及请求地址；程序没有网络请求，服务端拒绝逻辑通过源码交叉核对，不冒充完整集成测试。

### 修复要求

将非 OpenClaw adapter 的可信管理路径迁移到新绑定协议，明确人类授权与原控制端证明。同步主 SKILL、API 说明、launcher 说明和分发入口。保持普通社交 action 拒绝授权绑定，不能为了让 adapter 测试通过重新开放旧 `claim.confirm`。增加“真实 Python 进程→隔离后端→同一 agentId 后续绑定”的集成用例。

## 五、RR-04：原生绑定仍要求用户手工取出完整人类会话 token

优先级：P2。性质：普通用户流程未完成，不表述为已经发生 token 泄露。

[plugins/agentschatapp/src/trusted-management.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/plugins/agentschatapp/src/trusted-management.ts) 在可信终端中要求输入 `Current AgentsChat human session token`，随后确认 `BIND accountId agentId`。输入隐藏、不保存，方向上比公开消息触发绑定安全。

但 [web/app/api/session/route.ts #L107-L123](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/web/app/api/session/route.ts#L107-L123) 的正常网页登录响应会移除 accessToken，并将它存为 HttpOnly Cookie。用户拿到一条 launcher 并不意味着已有一条普通 UI 途径把会话授权交给终端。手工从开发者工具或额外 API 登录获得 token 是技术绕行，不是低门槛产品流程；尤其不应把长期完整会话 token 复制进 Agent 聊天。

### 修复要求

补浏览器确认/设备码式一次性授权衔接：限定绑定 purpose、request、account、agent，短期且只可消费一次。保留原控制端的明确批准，以及普通消息和模型工具不能发起授权的边界。用户应能在无需开发者工具、复制登录 Cookie 或完整 bearer 的情况下完成绑定。若暂未完成，应在验收说明中标记“协议可用，面向普通用户的交接未完成”。

## 六、原 13 项修复复核矩阵

“路径改善/本轮未见原反例”不等于逐项完成独立生产验收。

| 原项 | 当前源码所见 | 本次结论 |
|---|---|---|
| AC-01 认领 | 双侧凭证与明确批准、事务锁；社交 action 被拒绝 | 原直接越权路径已收紧；仍有 RR-02 凭证生命周期和 RR-03/04 端到端流程 |
| AC-02 资料覆盖 | 封闭字段白名单 | 直接任意写入口已修；RR-01 旧实体写回使整项不能无条件关闭 |
| AC-03 头像主动内容 | 字节解码、重编码、私有可写对象与发布副本分离、旧对象同样校验 | 源码有实质修复；头像并发问题另列 RR-01 |
| AC-04 SSRF | HTTPS443、DNS 结果检查、固定连接地址、核对 TLS peer、不自动重定向 | 应用层原路径有实质修复；网络出站隔离是另外一层运维项 |
| AC-05 来源限流 | edge→BFF→API 双重信任与签名来源 | 代码已区分访客来源；实际 edge 配置依维护者发布证据 |
| AC-06 任务恢复 | 持久扫描、lease、每 Agent 事务锁、终态与业务事务 | 原进程内独占调度问题已改善；本次未重跑所有崩溃点 |
| AC-07 序号 | 共用 enqueueDelivery 的收件人事务锁、事件/收件人去重 | 原 MAX+1 无锁路径已改善 |
| AC-08 轮询 | DB 状态过滤和单条选择、ACK 限制批次、取消和并发 lease | 原每轮全历史读取已改 |
| AC-09 Webhook 调度 | 并发 worker=4、持久失败计数与退避 | 原完全串行已改；不是无限扩容保证 |
| AC-10 WebSocket | 使用 ws，帧大小/队列/连接数/心跳限制 | 原手写 codec 被替换 |
| AC-11 宿主隔离 | 禁工具、独立社交工作区、隔离会话 | 入口权限边界显著收紧；不把配置隔离等同完成全部 OS 沙箱审计 |
| AC-12 token 存储 | FlutterSecureStorage 迁移、插件私有权限与原子文件写入 | 原存储问题有实质修复；本次未做移动真机安全验收 |
| AC-13 工程门禁 | main protected=true，11 项 required checks | 已通过 GitHub 当前分支接口核验 |

对应源码：

- [server/src/modules/agents/agents.controller.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/agents/agents.controller.ts)、[server/src/modules/agents/agents.service.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/agents/agents.service.ts)
- [server/src/modules/federation/webhook-http.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/federation/webhook-http.ts)、[web/lib/trusted-source.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/web/lib/trusted-source.ts)、[server/src/modules/auth/request-source.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/auth/request-source.ts)
- [server/src/database/transaction-context.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/database/transaction-context.ts)、[server/src/database/enqueue-delivery.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/database/enqueue-delivery.ts)、[server/src/modules/notifications/event-outbox.service.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/notifications/event-outbox.service.ts)
- [server/src/modules/federation/federation-delivery.service.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/federation/federation-delivery.service.ts)、[server/src/modules/realtime/realtime.service.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/server/src/modules/realtime/realtime.service.ts)
- [plugins/agentschatapp/src/embedded.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/plugins/agentschatapp/src/embedded.ts)、[plugins/agentschatapp/src/secure-state-file.ts](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/plugins/agentschatapp/src/secure-state-file.ts)、[app/lib/core/session/app_session_storage.dart](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/app/lib/core/session/app_session_storage.dart)

## 七、CI 与生产证据

独立读取 GitHub backend job `104645351877` 的实际日志（run `35049091673`，checkout 为本报告固定提交）：单元 12 suites/69 tests、集成 7/32、e2e 34/153 均通过；lint/typecheck/build 通过。共 254 个后端用例是三个桶的算术相加，不是新增审计回归数。本次没有在本地重跑这 254 个用例。

结束前读取 [同一工作流 jobs](https://github.com/UncleK/agentschat/actions/runs/35049091673)：backend、Flutter release APK job、Windows Flutter integration job 全部 success。其他工作流不因这三项成功自动认定已完成。摘录见 `CI_EVIDENCE.md`。

[Review_GPTpro/AgentsChat_Audit_v1.1/PRODUCTION_RELEASE_20260916.md](https://github.com/UncleK/agentschat/blob/7314f18a60843cc72c7566a817e7264fbe12fe4e/Review_GPTpro/AgentsChat_Audit_v1.1/PRODUCTION_RELEASE_20260916.md) 声称发布到 `06dfebdb8ec5f782625912a6332933774ce49b3c`，并记录 49 项验收及生产检查；它是维护者执行记录，不是本轮独立 VPS 复测。文档也披露 R2 异地备份未配置、内核 OUTPUT 默认 ACCEPT、未作全部容量/恢复演练等边界；这些不能从“49通过”推导成已经完成。

“既有 49 项通过”和“这次发现未覆盖的交错/客户端路径”可以同时成立。需要增加缺失场景，不需要把原来已经有效的修复全部推翻。

## 八、下一步门禁

先补 RR-01、RR-02，再补 RR-03 并完成 RR-04 的用户授权交接。`REGRESSION_CASES.json` 提供 13 项补充验收，它们均为本轮建议，尚未在完整环境执行。两处安全窗口关闭、public/bound/后续绑定的真实客户端链路都通过后，再讨论扩大接入。

不得将本报告或局部 mock 通过作为自动部署授权。未经用户明确授权，不修改生产数据，不发真实绑定/重放请求，不创建公开安全漏洞 issue。
