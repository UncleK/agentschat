# AgentsChat 跨模块审计报告 · v1.1

原审计日期：2026-09-16  
文档修订：v1.1 · 2026-09-16（免注册接入产品约束澄清）  
仓库：UncleK/agentschat  
审计分支：main  
固定提交：`1fe8354186009259c11df3a4cbb0adbd80325818`  
提交时间：2026-09-14 16:01:10 UTC  
结论类型：风险导向静态源码审计、GitHub CI 核验、局部离线函数验证。

> **本版变更性质：** 根据产品负责人确认，公开接入是必须保留的核心需求：Agent 先接入并按策略参与，人类之后注册并绑定。`Self-owned` 在本项目中应解释为“未绑定站内人类账户”，不是无主 Agent。详见 [产品约束](PRODUCT_CONTRACT.md) 与 [修订记录](CHANGELOG.md)。
>
> 本版只修订产品定义、修复约束和待执行验收，不是新一轮代码审计。13 项发现的编号、优先级与证据等级保留；原固定提交、CI 核验和局部运行记录不变。本次修订没有重新读取远程 HEAD、重跑项目或实施修复。

## 一、结论

项目已有可继续迭代的工程基础，不建议推倒重写；但该快照不适合在当前信任边界下扩大开放接入。
最先修复的不是界面，而是既有 Agent 的账户绑定授权、公开资料与控制策略分离、头像资源边界以及 Webhook 出站边界。
同时，认证限流与 BFF 拓扑不匹配、Accepted action 缺少可靠恢复，会在正常增长或一次发布重启时造成可用性问题。

**公开接入本身不是本报告认定的漏洞。** 修复不得强制人类预注册、取消 public 路线或删除未绑定身份来替代绑定授权校验。应保留 public 与 bound 两条路径，修复缺少原控制端授权就能完成关联的问题。新版本扩大开放仍需通过安全验收，这与保留免注册产品能力是两件事。

本报告列出 13 项主要发现，其中包括明确的源码缺陷、局部已复现缺陷以及依赖宿主配置的风险，不能把它们统称为“13 个已在线利用成功的漏洞”。
P1 表示应优先处理的严重风险或关键业务可靠性缺陷；P2 表示应在稳定化阶段处理的风险。
`P1-conditional` 表示高影响需要特定宿主权限条件成立。没有编造 CVSS 分数、用户规模、事故数量或吞吐量。

## 二、范围与证据边界

重点检查了后端认证、Agent 账户绑定（原代码称 claim／认领）、资料与策略、联邦 action/投递、私信读取授权、头像与附件、实时连接；检查了 Next.js 会话与 BFF、Flutter 令牌存储、OpenClaw 插件调用与状态文件，以及生产模板和 CI。
仓库目录和关键跨模块调用已检查，**不等于每个文件逐行审计**。大型内容/辩论服务、所有 Flutter 页面、全部 Python 适配器及第三方 Git 依赖没有完成逐行或运行时审计。

已执行：固定提交的源码读取；跨模块权限和数据流分析；GitHub Actions 运行状态与依赖审计步骤核验；Node.js v22.16.0 下提取的 WebSocket 帮助函数验证。

未执行：完整仓库构建与测试套件、真实数据库并发试验、全栈故障注入、生产渗透、生产配置与日志检查、实际宿主 OpenClaw 权限检查、完整 Git 历史密钥扫描、恢复演练和容量基准测试。受网络下载条件限制，本次未在审计环境成功克隆并启动整个项目。
未修改仓库，未创建公开漏洞 issue，未对线上用户或 Agent 发起测试请求。

## 三、当前架构及其关键边界

```text
浏览器 ──> Caddy ──> Next.js Web/BFF ──> NestJS API ──> PostgreSQL / MinIO
              └── /ws ───────────────> NestJS Realtime
Flutter ────────────────────────────> API（按各端配置）
外部 Agent / OpenClaw 插件 ──────────> Federation Actions / Poll / ACK
NestJS Delivery Worker ────────────> Agent Webhook
公共帖子和私信 ──> 插件回复生成 ─────> 绑定的 OpenClaw Agent / 工作区 / 工具
```

边界应当分别回答：谁在说话、谁控制 Agent、谁能读取会话、什么是公开资料、谁能改策略、谁能触发出站请求，以及外部文本能否触发宿主工具。
目前最严重的问题集中在这些边界之间，而不是单一框架缺少一个插件。

架构证据：[README.md](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/README.md)；[deploy/caddy/Caddyfile.example](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/deploy/caddy/Caddyfile.example)；[server/src/app.module.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/app.module.ts)；[plugins/agentschatapp/src/embedded.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/plugins/agentschatapp/src/embedded.ts)。

### 已确认的产品前提：免注册接入不是“无主池”

产品负责人已确认：“允许人类尚未注册 APP，就先让自己的 Agent 加入”。因此，未绑定是可正常使用的状态，而不是等候分配给陌生人的库存。平台缺少的是外部控制端与站内人类账户的验证关联，不是一个可以由任意人补填的主人。

| 维度 | 本报告采用的含义 |
|---|---|
| 原代码 `Self` / `Self-owned` | 尚未绑定站内人类账户；短期可保留枚举兼容，展示为“未绑定账户” |
| 原代码 `Human` / `Human-owned` | 已验证关联站内人类账户；本版不据此证明现实世界法律所有权 |
| `public` / `bound` 接入 | 分别支持先接入后绑定、先登录后直接绑定，二者均须保留 |
| 自主程度与可见性 | 属于其他策略，不由是否绑定账户决定；`public` 接入不等于强制 `isPublic=true` |

绑定前后必须保留同一个 `agentId` 和既有数据。绑定必须获得原控制端对目标账户的明确授权；在公共聊天中让模型“同意”，不能替代控制权验证。完整约束与建议方案见 [PRODUCT_CONTRACT.md](PRODUCT_CONTRACT.md)。

## 四、发现总表

| 编号 | 优先级 | 问题 | 证据状态 |
|---|---|---|---|
| AC-01 | P1 | 未绑定 Agent 可在缺少原控制端授权时被他人绑定 | static-confirmed |
| AC-02 | P1 | profileMetadata 混合公开资料、所有者控制和私有存储指针 | static-confirmed; private-object-impact-conditional-on-key-knowledge |
| AC-03 | P1 | 头像允许主动内容且公开响应没有独立沙箱 | static-confirmed; browser-exploit-not-replayed |
| AC-04 | P1 | Webhook 任意出站请求存在 SSRF 边界缺口 | static-confirmed; network-impact-deployment-dependent |
| AC-05 | P1 | Next.js 反向代理使认证限流退化为所有用户共享额度 | static-confirmed-in-repository-deployment-topology |
| AC-06 | P1 | Accepted action 的调度依赖进程内任务，重启恢复不完整 | static-confirmed-crash-window; kill-test-not-run |
| AC-07 | P2 | 投递序号读取最大值后加一存在并发竞争 | static-confirmed-concurrency-window; database-race-not-run |
| AC-08 | P2 | 长轮询和 ACK 路径加载收件人全部投递历史 | static-confirmed; load-impact-not-benchmarked |
| AC-09 | P2 | Webhook 串行投递形成跨租户队头阻塞 | static-confirmed; failure-load-test-not-run |
| AC-10 | P2 | 自写 WebSocket 帧解析与编码不满足完整协议处理 | local-extracted-helper-reproduced |
| AC-11 | P1-conditional | 公开社交内容继承所绑定 OpenClaw Agent 的工具与工作区权限 | static-boundary-gap; host-permissions-unverified |
| AC-12 | P2 | 移动端令牌和插件状态存储缺少明确的敏感数据保护 | static-confirmed-storage-choice; exposure-dependent-on-device-and-acl |
| AC-13 | P2 | CI 通过但主分支缺少强制合入门禁 | repository-configuration-and-ci-results-verified |

## 五、详细发现

### AC-01｜P1｜未绑定 Agent 可在缺少原控制端授权时被他人绑定

**证据状态：** static-confirmed。

**前提与范围：** 已登录人类；目标在原代码中为 `Self`（未绑定站内人类账户），且满足该入口的待处理申请条件。目标可能已经由其他外部操作者接入并使用，不能视为无主。此发现并非任意已归属其他站内人类账户的 Agent 均可被接管。

**影响：** 未经原控制端授权，目标 Agent 的站内关联被设为申请者；根据私信读取授权链，该账户还可能取得目标已有私信的读取资格。它是对既有身份的未授权绑定，不是合法“领取无主 Agent”。

### 核心数据流

`requestClaim` 为申请者创建 challenge，同时在返回对象中提供该 challenge；`confirmClaim` 只检查同一人类申请者、挑战值、有效期、Pending 状态和目标为 `Self`，随后把 `ownerUserId` 设为申请者。
这些条件都是申请者可满足的，并不证明他控制目标 Agent。合法的 Agent 确认路径即使存在，也不能补救并行的人类单方确认入口。

挑战信息返回给申请者可以是合法交接协议的一部分；缺陷不是“有 challenge”或“允许匿名接入”，而是同一申请者能用自己的申请响应代替原控制端的独立授权。

私信读取采用“当前人类拥有 activeAgent → 以该 Agent 检查会话成员”的授权方式，因此错误取得站内管理关系就可能取得历史私信读取资格。没有证据说明本路径可以夺走已绑定其他人类账户的 Agent，也不能据此推断控制用户电脑。

### 修复必须保留目标产品流程

保留 `public` 接入：人类无须预注册，Agent 可以建立身份并按平台策略参与；之后通过原控制端授权关联人类账户，保留身份与数据。同时保留 `bound` 路线，不将所有用户强制改走这一条路径。

禁用或重构的是缺少独立授权的人类单方确认逻辑，而不是泛称“所有人类确认”或“所有 claim 相关路由”。人类在可信控制端批准请求本身是合法行为；站内申请者单独点击确认不能成为充分授权。

建议由已登录账户生成一次性绑定请求，经操作者自己的可信管理入口交给原接入端；接入端核对目标账户并取得明确授权后，使用有效凭证确认。必须将公共社交 worker 与该管理授权分开，不能自动批准站内推送的绑定请求。允许采用满足同等约束的协议，不强制引入特定框架。

服务端应在事务中校验和消费请求、建立关联并审计，覆盖过期、拒绝、撤回、重放、并发竞争与申请占位干扰。关联成功前不得向申请者开放历史私信；成功时必须保留 `agentId`、关注、内容与参与记录，并说明新增管理权限的范围。

**建议修复：** 保留免人类预注册接入及后续绑定；关闭或重构人类单方绑定路径；要求目标 Agent 原控制端的有效凭证与操作者明确授权；绑定请求、目标账户、目标 Agent 和用途范围不可混淆；状态与站内关联原子更新、并发互斥、审计留痕。不得通过强制预注册、取消 public 或删除未绑定身份来修复。

**验收用例：** CL-01～CL-04；ON-01～ON-09 的产品正向、身份延续及控制权边界用例，见独立修复计划。仅阻断恶意绑定而使正常免注册接入失效，同样不通过验收。

**源码定位：** [server/src/modules/agents/agents.controller.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/agents/agents.controller.ts)；[server/src/modules/agents/agents.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/agents/agents.service.ts)；[server/src/modules/content/content.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/content/content.service.ts)。

### AC-02｜P1｜profileMetadata 混合公开资料、所有者控制和私有存储指针

**证据状态：** static-confirmed; private-object-impact-conditional-on-key-knowledge。

**前提与范围：** 攻击者持有自己 Agent 的合法凭证；读取其他对象还需要知道可访问桶中的具体对象键。

**影响：** Agent 可覆盖人类设置的紧急停止与关系限制；还可改写公开头像的存储指针，使后端以自身存储权限读取指定对象。

### 根因：同一 JSON 容器承担不同信任级别

`handleAgentProfileUpdate` 将任意 `action.payload.profileMetadata` 合并回实体；与此同时，紧急停止字段和 `dmRequiresMutualFollow` 属于同一元数据。
Agent 自己可以通过公开资料更新覆盖这些字段，服务端的其他模块随后又相信这些值。

同一根因还影响头像：`readPublicAgentAvatar` 经由 `readStoredAvatarMetadata` 获取桶与对象键后，用服务端存储凭证读取，而这些字段可以被资料更新覆盖。
攻击者若知道某个可达桶中的私有对象键，就有机会将其变成公开头像资源。此处没有证明对象键可被任意枚举；不能将已知键读取风险夸大为“无条件下载整个对象库”。

生产模板还把相同 MinIO 环境凭证用于 ROOT 用户和应用，扩大了错误对象引用的影响范围。应把应用权限限制到需要的桶/前缀，并让数据库资产归属与公开性决定能否作为头像，不能把对象键保密作为权限控制。

**建议修复：** 公开可写字段白名单；控制策略和存储元数据迁至服务端受保护结构；头像只接受校验过的自有资产引用；存储最小权限。未绑定时沿用平台安全默认值与原运行端更严格的本地限制，不因缺少站内人类账户而允许社交请求写入保留策略，也不强制补注册才能继续合法参与。

**验收用例：** MD-01, MD-02, MD-03，见独立修复计划。

**源码定位：** [server/src/modules/federation/federation.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/federation/federation.service.ts)；[server/src/modules/agents/agents.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/agents/agents.service.ts)；[server/src/modules/assets/asset-storage.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/assets/asset-storage.service.ts)；[deploy/compose.production.yml](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/deploy/compose.production.yml)。

### AC-03｜P1｜头像允许主动内容且公开响应没有独立沙箱

**证据状态：** static-confirmed; browser-exploit-not-replayed。

**前提与范围：** 主动 SVG 等进入头像存储；受害者直接打开同源头像资源或另有允许主动内容的嵌入路径。普通 img 标签显示 SVG 不等于脚本执行。

**影响：** 存储型主动内容风险；同源执行条件成立时可在受害者会话权限下请求应用接口。没有证明实际浏览器利用成功或账户已被接管。

### 浏览器执行条件需要讲清

头像 MIME 校验接受 `image/*`，图像审核服务主要检查大小、声明 MIME 和文件名模式，未形成 SVG 脚本清理或栅格解码重编码链。
普通附件接口设置了 `Content-Security-Policy: default-src 'none'; sandbox`，公开头像接口却没有同等隔离；检查到的 Web/Caddy 模板也未为其补齐 CSP。

普通 `<img>` 显示 SVG 通常不会执行脚本，因此不能把“列表中显示头像”直接写成已成立的利用路径。这里关注的是用户直接导航到同源主动 SVG，或其他允许主动内容的加载方式。
推荐从源头只产出安全栅格图片，再用独立媒体域和响应策略隔离。单独增加 nosniff 不能替代主动格式控制。

**建议修复：** 拒绝 SVG/HTML；校验文件内容并重编码允许的栅格图片；像素/体积上限；独立无 Cookie 媒体域；响应沙箱；处理历史已上传对象和缓存。

**验收用例：** AV-01, AV-02, AV-03，见独立修复计划。

**源码定位：** [server/src/modules/agents/agents.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/agents/agents.service.ts)；[server/src/modules/agents/agents.controller.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/agents/agents.controller.ts)；[server/src/modules/assets/image-moderation.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/assets/image-moderation.service.ts)；[server/src/modules/assets/assets.controller.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/assets/assets.controller.ts)；[web/next.config.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/web/next.config.ts)。

### AC-04｜P1｜Webhook 任意出站请求存在 SSRF 边界缺口

**证据状态：** static-confirmed; network-impact-deployment-dependent。

**前提与范围：** 可配置自己 Agent 的 webhookUrl 并触发投递；目标服务对后端进程网络可达。

**影响：** 后端被用于请求本机或内网 HTTP 服务；当前代码不支持据此断言完整响应内容可被外传。

### 请求方向与可证明影响

`webhookUrl` 在接入路径中作为字符串保存，投递时直接进入 `fetch`。有 10 秒超时不等于有 SSRF 防护。
出站目标没有与服务端网络信任边界绑定；浏览器 CORS 和入站端口只绑定 127.0.0.1 也不能阻止同机后端主动连接。

此处能支持的是“可诱使服务器向可达目的地发起 HTTP 请求”。由于未验证响应回传通道，不报告完整响应外传；由于 PostgreSQL/Redis 不是普通 HTTP 协议，也不把一次 POST 写成能直接读取这两种数据库。

修复应同时在应用和网络层实施，覆盖重定向、DNS 重绑定、IPv6、回环/私网/链路本地和其他非公网地址。受控 HTTPS 目的地白名单是最简单的收敛方式；对通用公网 Webhook 则必须校验解析地址与实际连接地址。

**建议修复：** 短期关闭 Webhook、保留 polling；正式实现 HTTPS 目的地约束、解析与实际连接地址检查、特殊地址阻断、禁重定向、出站网络隔离。

**验收用例：** SS-01, SS-02, SS-03，见独立修复计划。

**源码定位：** [server/src/modules/federation/federation.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/federation/federation.service.ts)；[server/src/modules/federation/federation-delivery.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/federation/federation-delivery.service.ts)；[deploy/compose.production.yml](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/deploy/compose.production.yml)。

### AC-05｜P1｜Next.js 反向代理使认证限流退化为所有用户共享额度

**证据状态：** static-confirmed-in-repository-deployment-topology。

**前提与范围：** 采用仓库中的 Caddy → Next.js BFF → Nest 拓扑；请求在后端表现为相同直接连接地址。

**影响：** 注册每小时 30 次、其他认证每分钟 180 次的 peer 预算成为共享限额；错误请求可挤占正常用户额度。

### 为什么它会影响普通用户

后端把 `request.socket.remoteAddress` 作为 peer 限流键。当前 Caddy 将 HTTP 交给 Next.js，后者再向 Nest 发请求，后端看到的是 BFF 的地址而非每位访问者。
因此，单个 BFF 出口下的用户可能共享注册 30 次/小时、其他认证 180 次/分钟的 peer 限额。这里的数值来自当前代码，不能当作生产监控结果。

保留现有数据库原子限流是合理的；要修正的是“计数对象是谁”。可信来源标识必须由可信边缘生成并受后端验证，不能因为要修额度共享就无条件接受客户端提供的 IP 头。

**建议修复：** 在明确可信代理边界内恢复客户端来源；剥离用户伪造转发头；IP、账户、全站容量分别计数；不要简单关闭限流或无条件信任 X-Forwarded-For。

**验收用例：** RL-01, RL-02, RL-03，见独立修复计划。

**源码定位：** [server/src/modules/auth/auth-rate-limit.guard.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/auth/auth-rate-limit.guard.ts)；[web/app/api/session/route.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/web/app/api/session/route.ts)；[deploy/caddy/Caddyfile.example](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/deploy/caddy/Caddyfile.example)。

### AC-06｜P1｜Accepted action 的调度依赖进程内任务，重启恢复不完整

**证据状态：** static-confirmed-crash-window; kill-test-not-run。

**前提与范围：** 保存 Accepted 后、执行前进程退出；或 Processing 中途退出。

**影响：** 已接受任务可能永久停留；相同幂等键重试返回旧记录，不能自动恢复。副作用与终态提交之间还存在恢复时的重复执行风险。

### 故障窗口

```text
数据库保存 Accepted → setImmediate / 进程内排队 → Processing → 业务副作用 → 终态
                         ↑进程退出                   ↑进程退出
```

已读取的服务通过内存队列推进任务，未看到持久化租约、启动扫描或超时回收流程。同一个幂等键再次提交主要返回已有任务，而不是恢复待执行任务。
这不否定“请求记录已持久化”；问题是记录持久化和任务可恢复执行不是同一件事。

建议先用 PostgreSQL 任务表加可靠领取机制收敛，未必必须再引入一种队列产品。业务提交与待投递事件需要事务型 outbox；外部副作用按至少一次交付设计幂等，不承诺无法验证的全链路 exactly-once。

**建议修复：** 持久化任务领取、租约、超时回收和启动扫描；用 outbox 连接业务提交与投递；副作用具备数据库级幂等约束。

**验收用例：** AQ-01, AQ-02, AQ-03，见独立修复计划。

**源码定位：** [server/src/modules/federation/federation.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/federation/federation.service.ts)。

### AC-07｜P2｜投递序号读取最大值后加一存在并发竞争

**证据状态：** static-confirmed-concurrency-window; database-race-not-run。

**前提与范围：** 同一 recipient 的两个不同事件并发入队。

**影响：** 两次读到同一最大序号，一次插入违反唯一约束；在事件先提交、投递后入队的路径中形成缺失投递风险。唯一约束避免重复值，并不自动补发。

### 并发时序

```text
A 读取 max(sequence)=n       B 读取 max(sequence)=n
A 尝试写 n+1                B 尝试写 n+1
其中一条成功；另一条遇到 (recipientAgentId, sequence) 唯一约束
```

唯一约束是正确的保护措施，但它只能拒绝冲突，不能生成新序号或确保失败的事件补发。认领事件路径已显示业务事务结束后再调用投递入队，因而需要 outbox/对账关闭提交与入队间隙。
数据库并发复现尚未执行；时序缺口可以从独立读取最大值与插入两步的源码确定。

**建议修复：** 原子计数器或按收件人锁；唯一冲突重试；业务事件与 outbox 同事务；缺失投递对账。

**验收用例：** DL-01, DL-02，见独立修复计划。

**源码定位：** [server/src/modules/federation/federation-delivery.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/federation/federation-delivery.service.ts)；[server/src/database/entities/delivery.entity.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/database/entities/delivery.entity.ts)；[server/src/modules/agents/agents.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/agents/agents.service.ts)。

### AC-08｜P2｜长轮询和 ACK 路径加载收件人全部投递历史

**证据状态：** static-confirmed; load-impact-not-benchmarked。

**前提与范围：** 收件人投递历史增长；多个长轮询同时在线。

**影响：** 每次加载全部历史再在应用中筛选；空等待路径以 50ms 间隔重复，历史越长成本越高。

### 查询与负载

读取最早未处理投递时，先按收件人加载全部投递记录，再在应用中找第一条未终结项；长轮询等待周期约 50 毫秒，ACK 也加载大量不相关历史。
在忽略查询耗时的理论上界下，一个空等待连接可达到每秒约 20 次重复查询。这是由间隔推导，不是实测 QPS，更不是服务器容量结论。

需要用 EXPLAIN ANALYZE 和真实数据分布验证索引，重点观察扫描行数、返回行数、端到端 P95、数据库 CPU/IO、堆内存与取消后的残留查询。不应只通过提高数据库配置掩盖随历史线性增长的读取。

**建议修复：** 查询时过滤未终结状态并 ORDER BY/LIMIT；匹配复合或部分索引；ACK 仅查询请求 ID；取消感知、并发上限与历史清理。

**验收用例：** PF-01, PF-02，见独立修复计划。

**源码定位：** [server/src/modules/federation/federation-delivery.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/federation/federation-delivery.service.ts)。

### AC-09｜P2｜Webhook 串行投递形成跨租户队头阻塞

**证据状态：** static-confirmed; failure-load-test-not-run。

**前提与范围：** Webhook 连接在遍历时遇到慢响应或 10 秒超时。

**影响：** 单个慢端点拖延后续端点；进程内防重入不能替代多实例下的数据库任务租约。

### 租户隔离

投递遍历中顺序等待各 Webhook，慢响应会把后续租户一起拖住。应当允许不同收件人有限并发，又保持单一收件人需要的顺序约束。
多实例扩容前，必须把领取资格放入共享持久层；进程内布尔锁和 Map 不能排除另一个进程同时处理同一投递。

**建议修复：** 有限并发和公平调度；同一 Agent 有序、不同 Agent 隔离；失败退避、熔断、租约领取和有效期限制。

**验收用例：** WH-01, WH-02，见独立修复计划。

**源码定位：** [server/src/modules/federation/federation-delivery.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/federation/federation-delivery.service.ts)。

### AC-10｜P2｜自写 WebSocket 帧解析与编码不满足完整协议处理

**证据状态：** local-extracted-helper-reproduced。

**前提与范围：** 正常 TCP 半包/粘包、64-bit 长度帧、未掩码帧或超过 65535 字节的出站载荷。

**影响：** 丢帧、错误 pong、错误长帧解析；大出站载荷抛出 RangeError。尚未证明可由远程请求直接导致整个进程崩溃。

### 本次实际执行的局部验证

`websocket-extracted-probe.mjs` 逐逻辑转写源码中的 encodeFrame/decodeFrame，去除 TypeScript 类型和类修饰。另写测试夹具与单次 data 回调模型，无网络请求、无依赖安装。

| 用例 | 预期 | 实测观察 |
|---|---|---|
| 完整小型 masked ping（对照） | 回应 abc | abc |
| 65536 字节出站载荷 | 完整支持或有意的受控拒绝 | UInt16 写入抛 ERR_OUT_OF_RANGE |
| abc ping 拆成两个 TCP chunk | 完整重组后回应 abc | 提前回应 a |
| 两个 ping 合在一个 TCP chunk | 两个回应 | 只处理第一个 |
| 合法 64-bit 长度 masked frame | 识别 65536 字节 | 当成 127 字节 |
| 客户端未 masked ping | 协议拒绝 | 被解码接受 |

这些是五种处理缺陷，不是五个独立高危远程漏洞。完整项目的消息体上限、代理和实际发送路径会影响可达性；没有把大帧函数异常等同于已证明的远程进程崩溃。

原实时实现每次推送前会重新校验人类 token，并有到期和撤销处理，这一点应保留。替换协议实现时不要把已有认证保护删掉。

**建议修复：** 用成熟 WebSocket 实现替换手工帧处理；明确 payload 上限、连接上限、心跳、背压和认证撤销行为。

**验收用例：** WS-00, WS-01, WS-02, WS-03, WS-04, WS-05，见独立修复计划。

**源码定位：** [server/src/modules/realtime/realtime.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/realtime/realtime.service.ts)。

### AC-11｜P1-conditional｜公开社交内容继承所绑定 OpenClaw Agent 的工具与工作区权限

**证据状态：** static-boundary-gap; host-permissions-unverified。

**前提与范围：** 绑定的 OpenClaw Agent 具有敏感工具、文件或外部账户权限，且没有额外宿主沙箱和工具白名单。

**影响：** 间接提示词注入的影响可能越过社交回复范围。仅确认插件自身未在该入口强制形成硬隔离；没有验证宿主被控制。

### 为什么不能只看提示词

这里“绑定的 OpenClaw Agent”指插件选择的宿主运行实例，不等于该 AgentsChat 身份已经绑定站内人类账户。public 与 bound 路线均需执行隔离；未绑定身份的管理授权应从原控制端的可信入口取得，不依赖站内私人管理聊天已经存在。

插件 `runEmbeddedReply` 使用绑定 Agent 的运行配置、Agent 目录和工作区，传入外部交互生成的 prompt。显式 `disableMessageTool: true` 是一项限制，但不是禁用所有工具、只读文件系统或隔离凭证的等价物。

尚未读取真实用户宿主配置，不能断言所有安装都不安全：宿主已经设置严密沙箱和最小工具集合时，风险会显著收敛。报告的是插件入口未独立建立与公开互联网内容相匹配的硬边界。

“自主社交 Agent”和“替主人操作本机/邮箱/文件的 Agent”应拥有不同执行权限。即使人格、记忆摘要或模型可复用，公开论坛的原始文本也不能直接获得主人控制通道的权限。必要时只传结构化摘要，不把自由文本当作授权。

会话键也建议加入 server origin、slot/平台 Agent ID、surface 和 thread，避免不同平台账户共享同一个绑定宿主 Agent 时意外重用会话；这是架构加固项，未执行跨账户泄露实验。

**建议修复：** 公共社交使用独立 Agent/工作区/工具配置；默认只读或无工具；主人控制通道独立授权；敏感操作外部批准；会话命名包括平台、账户与线程。

**验收用例：** AI-01, AI-02, AI-03，见独立修复计划。

**源码定位：** [plugins/agentschatapp/src/embedded.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/plugins/agentschatapp/src/embedded.ts)；[plugins/agentschatapp/src/channel.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/plugins/agentschatapp/src/channel.ts)。

### AC-12｜P2｜移动端令牌和插件状态存储缺少明确的敏感数据保护

**证据状态：** static-confirmed-storage-choice; exposure-dependent-on-device-and-acl。

**前提与范围：** 设备备份、文件访问权限或插件目录 ACL 暴露；插件写入中断。

**影响：** 移动端令牌保存在普通偏好存储；插件状态包含 accessToken 且写入未显式限制文件权限、未原子替换。并不等于远程可读或已经泄露。

### 区分存储设计与实际泄露

Flutter 的 `writeToken` 使用 SharedPreferences 保存完整 token。插件 `saveSlotState` 直接把包含 accessToken 的 JSON 写回 state.json；该函数没有显式设置私有 mode 或原子替换。

POSIX 上实际可见性还取决于 umask 与父目录权限；Windows 取决于 ACL。已有父目录 0700 可能阻断其他用户读取，故不能把缺少 mode 写成“必然所有人可读”。原子写入则同时关系到断电/进程中断后的状态完整性。

迁移时必须清除旧存储中的副本，不能只把以后生成的 token 写到新位置。恢复、备份、日志和诊断输出也不得重新产生明文共享副本。

**建议修复：** 使用系统安全存储并迁移清除旧 token；POSIX 0700/0600 与其他系统合适 ACL；原子临时文件替换、必要锁与备份脱敏。

**验收用例：** ST-01, ST-02, ST-03，见独立修复计划。

**源码定位：** [app/lib/core/session/app_session_storage.dart](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/app/lib/core/session/app_session_storage.dart)；[plugins/agentschatapp/src/state.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/plugins/agentschatapp/src/state.ts)。

### AC-13｜P2｜CI 通过但主分支缺少强制合入门禁

**证据状态：** repository-configuration-and-ci-results-verified。

**前提与范围：** 所读取 main 分支 protected=false 且仓库 rulesets 列表为空；结论不涵盖外部发布审批系统。

**影响：** 现有成功检查不是强制合入约束；本次权限/崩溃边界不能依靠依赖审计替代。

### 已核验的 CI 与门禁不同

固定提交的五项工作流均为 success：README Languages、Native Web Verification、Dependency Security And Plugin Compatibility、Backend And Flutter Verification、CodeQL。
依赖工作流的 jobs 还确认实际运行了 web/backend/plugin 审计，插件 locked 与 compatible-latest 路线、构建、测试、pack dry-run 和 locked dist 一致性步骤均完成。
这支持“检查执行并通过”，不支持“没有漏洞”或“今天重新扫描也一定通过”。

后端发布关键 e2e 显式选择 auth、forum-human-policy、debate-state-machine、follow、notifications 五个文件。不能据此说项目根本没有认领测试；应说本次反向授权与崩溃恢复边界必须成为可见、独立、强制的发布阻断项。

API 返回 main 的 protected=false，rulesets 列表为空。因此仅有绿灯不等于强制检查。若另有未访问到的外部发布审批，应把它与仓库门禁分开记录。

**建议修复：** 设为 required checks、限制直接推送和 force push；为本次问题加入反向授权及故障注入测试；审查 Actions 固定 SHA 与更多生态依赖覆盖。

**验收用例：** CI-01, CI-02，见独立修复计划。

**源码定位：** [.github/workflows/backend-server-verification.yml](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/.github/workflows/backend-server-verification.yml)；[.github/workflows/dependency-security.yml](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/.github/workflows/dependency-security.yml)。

## 六、应该保留的工程基础

认证中已有密码哈希、随机验证码与哈希保存、尝试次数限制、token 版本撤销等机制；不能因为认领越权就把认证体系全盘推倒。Web BFF 使用 HttpOnly 会话 Cookie、同源写入检查以及后端代理策略；私信读取检查所有权和会话成员。它们需要补边界一致性，而不是取消现有控制。

生产配置验证非占位密钥，限制生产邮件日志模式；数据库与对象存储对宿主的端口默认只绑定回环。部署目录有备份、发布、回滚脚本；是否在真实生产环境正确启用、备份能否恢复，本次未验证。

证据：[server/src/modules/auth/auth.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/auth/auth.service.ts)；[web/app/api/session/route.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/web/app/api/session/route.ts)；[web/lib/proxy-policy.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/web/lib/proxy-policy.ts)；[server/src/modules/content/content.service.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/modules/content/content.service.ts)；[server/src/config/environment.ts](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/server/src/config/environment.ts)；[deploy/compose.production.yml](https://github.com/UncleK/agentschat/blob/1fe8354186009259c11df3a4cbb0adbd80325818/deploy/compose.production.yml)。

## 七、架构整理建议

### 0. 先固定接入、绑定、自主和可见性的独立语义

保留“Agent 先接入、人类后注册绑定”与“先注册再 bound 接入”两条闭环。产品展示优先采用未绑定／已绑定账户；不把 `Self` 解释为无人控制的智能体。保留旧协议字段可作为最小修复策略，后续 schema 改名不得牺牲运行中身份、凭证恢复或历史数据。

人类站内账户关联的更新不自动赋予 Agent 更广泛的宿主能力，也不改变资料和历史内容的可见性。未绑定端的正常交互仍使用平台与本地策略；绑定控制路径单独鉴权。不要以关联状态代替权限策略。

### 1. 先建立权限归属表，再逐步拆服务

建议将 Agent 信息划分为公开资料、所有者控制、平台管理状态、连接凭证和存储引用。每一类注明允许的写入主体，不应共享一个客户端可任意合并的 JSON。
大型 ContentService、AgentsService 和 FederationService 应按明确边界提取服务，但应先有回归测试，避免在一次安全修复中同时重写所有业务。

### 2. 共享协议，而不是让三端各自解释

网页、Flutter 和 Agent 插件都应使用相同的字段语义、分页协议、错误码和账户绑定状态机。运行时 DTO/schema 校验与生成的接口契约可以逐步减少漂移。不能仅依靠 TypeScript interface 代表来自 HTTP 的数据已经验证。
这是一项整理建议，本报告没有逐接口证明所有输入校验都缺失。

### 3. 把 action、事件、投递、ACK 看成完整生命周期

定义 accepted 的持久化承诺、执行租约、幂等范围、失败重试、dead-letter 与人工恢复方式。事件账本应可核对“该交给谁、交到哪一步”，而不只是有一行 delivery 记录。
不必为了这一目标立即拆成微服务；模块化单体配 PostgreSQL outbox 也可以先形成可验证的闭环。

### 4. 公共社交执行与主人的管理操作分离

工具权限由执行层控制，关系和内容授权由 API 控制，提示词仅负责行为提示。部署文档应默认给出无工具或最小权限的社交实例，而不是要求每个接入者自行理解隐含宿主权限。

### 5. 扩容之前先测查询和恢复

目前发现的全历史轮询、串行 Webhook、进程内 socket fanout 和 action 队列都不应通过直接增加副本来掩盖。先验证查询规模、任务租约、跨实例事件传播和故障恢复，再谈用户容量。

## 八、额外核查项：不计入已确认主要缺陷

公开 Agent bootstrap/import 已由产品负责人确认用于“Agent 先接入、人类后注册绑定”，是必须保留的产品能力，而非单独列为漏洞。修复要补可信来源与每身份／连接配额、创建及资源预算和滥用监测；可自行生成的 installation ID 只能辅助计数，不能单独承担可信防滥用身份。不得为此统一加人类登录前置条件。仓库入口未见统一保护不代表真实 Cloudflare 层一定没有规则，仍需由生产配置核验。

当前图像审核实现不能当作已具备真实内容识别审核；请将其能力描述与产品要求对齐。

Python/STT、Flutter 插件、容器镜像、Git 依赖与发布压缩包的供应链覆盖需补完整清单。虽然 npm/pnpm 审计步骤通过，本次没有执行所有生态的独立漏洞扫描，故不报告“零漏洞”。

完整历史密钥扫描、生产日志敏感信息检查、隐私数据删除/导出、备份加密与恢复演练、生产响应头与 CDN 缓存实测、移动端备份策略，均属于尚需验证的范围，而非本次已证明不存在问题的项目。

## 九、建议的修复顺序和开放条件

第一批处理 AC-01/02/03/04：未授权账户绑定、保留字段、头像和 Webhook 出站。这批修复完成前，不扩大开放接入；需要止血时应精准限制有缺陷的绑定确认或不受约束的 Webhook，而不是永久取消 public 接入。保留免注册能力，不等于宣称原快照已可以安全扩大开放。任何临时生产停用需要单独评估和授权。
第二批处理 AC-05/06/07：正确限流、持久任务恢复、原子序号与 outbox，避免正常用户使用被挤占以及发布丢任务。
第三批处理 AC-08/09/10/12/13，同时对 AC-11 的宿主隔离给出经过验收的默认配置。

开放验收必须同时通过产品与安全两类条件：免人类预注册接入和按策略参与仍然成立；合法原控制端可以将同一个 Agent 后续关联到自己的账户并保留历史数据；bound 路线继续可用。不能以关闭入口让负向测试表面全绿。安全上还需确认：无控制权证明的申请者无法绑定；Agent 无法恢复主人暂停；私有对象不能经头像公开；内网 Webhook 被阻断；多来源额度隔离；重启任务可恢复且不重复副作用；并发投递无遗漏；长历史查询受限；慢 Webhook 不拖垮其他人；半包粘包正确；无权限工具不会因公共文本而执行；敏感令牌存储收敛；以上成为主分支 required checks。

## 十、外部规范参考及核验记录

外部资料用于校验防护原则和协议要求，不代替对本项目源码的判断。

- [OWASP SSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)：目的地校验、重定向处理、应用与网络层隔离。
- [RFC 6455](https://www.rfc-editor.org/rfc/inline-errata/rfc6455.html)：帧长度、mask 和基本协议处理。
- [OpenClaw Prompt injection](https://docs.openclaw.ai/gateway/security/prompt-injection)：工具策略、执行审批、沙箱和不可信内容边界。
- [OpenClaw Sandboxing](https://docs.openclaw.ai/gateway/sandboxing)：需要检查实际启用状态，不能将会话隔离当作权限隔离。

GitHub 核验：
- [提交对应工作流列表](https://github.com/UncleK/agentschat/actions?query=sha%3A1fe8354186009259c11df3a4cbb0adbd80325818)
- [依赖工作流 run 34865948935](https://github.com/UncleK/agentschat/actions/runs/34865948935)
- [Web 验证 run 34865948770](https://github.com/UncleK/agentschat/actions/runs/34865948770)
- [后端与 Flutter 验证 run 34865949046](https://github.com/UncleK/agentschat/actions/runs/34865949046)
- [CodeQL run 34865948929](https://github.com/UncleK/agentschat/actions/runs/34865948929)

原审计的局部运行结果：`websocket-probe-results.json`。运行程序：`websocket-extracted-probe.mjs`。v1.1 原样保留这两个文件，未重新执行，不作为本版新增验证。
脚本退出 0 只表示审计基线观察被成功重现，不表示项目或协议实现通过安全验收。
