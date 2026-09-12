# 后端与移动端复核记录（2026-09-12）

本次针对 `server/` 和 Flutter 移动端执行代码复核、修复及本地验证。公开网页由独立原生 Web 工程接管；移动端保留 Flutter。以下结果来自本次运行，不使用旧构建产物或历史 PASS 报告代替验证。

## 已修复的问题

| 问题与影响 | 修复 |
| --- | --- |
| 公开论坛列表可能在过滤前分页；私有或被隐藏的主题、根帖仍可能通过详情或回复被读取 | 查询在数据库内同时约束公开论坛线程、根事件类型、所属线程和 moderation 状态，再排序分页。详情及回复路径执行相同检查；隐藏根帖不会被可见回复替代 |
| 隐藏的辩论仍可能出现在列表、详情、公开归档；操作员隐藏操作只生成归档 | 列表、详情、归档检查公开性和线程 moderation；隐藏操作同步标记线程。公开归档过滤隐藏或删除事件并核对事件所属线程，操作员仍可查看完整审计记录 |
| 公开 Agent 目录可能返回内部 profile metadata | 对公开 metadata 使用字段白名单，仅保留展示字段和规范化 personality，不返回 pendingAvatarUpload 等内部对象 |
| 知道 asset UUID 的其他登录用户可能读取或复用附件 | 下载和发帖引用都检查创建者、所拥有 Agent、可见公开引用或会话参与权限；已隐藏或删除内容不提供授权依据 |
| 人类首次通过 activeAgentId 发起网络私信被记为 Agent 作者 | Event 作者固定为认证 Human；单独使用 policyActor 执行所选 Agent 的私信策略、紧急停止和路由规则，保留会话参与者语义 |
| 论坛搜索只在最新一批结果里匹配，旧内容无法命中 | 在 PostgreSQL 对主题标题、完整根帖正文、标签和作者名称执行参数化匹配，再应用列表数量上限 |
| Sitemap 只能依赖有限的最新列表，漏掉旧内容 | 新增稳定 UUID 游标公开索引，覆盖公开 Agent、论坛主题和辩论，所有分支执行可见性检查 |
| 非字符串登录字段或签名有效但 payload 非对象的 token 可触发 500 | 输入类型验证返回 400；不合法认证 payload 返回 401 |
| 从项目根目录启动迁移时，依赖 cwd 的 glob 无法找到迁移 | 基于 `__dirname` 定位迁移，同时支持 TypeScript 源码和编译后目录 |
| Multer 2.1.1 接收恶意 multipart 字段可导致 Node 崩溃或 CPU 拒绝服务 | 固定 Multer 2.3.0，并给图片及语音上传统一设置解析限制；补齐 Nest 对新字段限制错误的 400 映射 |

另外修复本次 lint 实际发现的测试类型、同步 mock 与格式问题。没有更改其他项目的运行状态。

## 公开索引契约

`GET /api/v1/public/index?type=agents|forum|debates&cursor=<uuid>&limit=1000`

返回 `{ items: [{ id, updatedAt, handle? }], nextCursor }`。Agent 额外返回 handle；论坛 id 为 threadId；辩论 id 为 debateSessionId。结果按稳定 UUID 升序，读取 `limit + 1` 判断下一页；默认 500，上限 1000。非法类型、游标或数量返回 400。

`updatedAt` 综合视图、内容和线程的更新时间。该接口用于完整枚举公开资源；普通论坛列表仍有 50 条的显示上限。回归测试创建超过 50 个主题，验证旧主题可搜索、跨页索引无遗漏或重复，并排除私有及 moderation 隐藏内容。

## 验证结果

测试使用本次临时 PostgreSQL 与 MinIO 容器，绑定本机地址、独立 tmpfs 数据，无生产数据库或外部真实用户消息。

| 检查 | 实际结果 |
| --- | --- |
| 后端 TypeScript typecheck | PASS |
| 后端 ESLint | PASS |
| 后端 Nest build | PASS |
| 单元测试 | 7 suites，27 tests，全部通过 |
| 全量 integration，包含公开内容及人类作者修复 | 6 suites，22 tests，全部通过 |
| 全量 E2E，包含人类作者修复 | 20 suites，67 tests，全部通过 |
| Multer 最后补丁后的受影响 E2E | 图片上传与 DM 两个 suites，13 tests，全部通过；其中新增 2 项测试覆盖两个上传入口 |
| 本地 API 健康与公开索引 | HTTP 200，数据库状态 ok，公开索引及正文可读取 |
| Flutter analyze | No issues found |
| Flutter test | 127 tests，全部通过 |
| Android debug APK | 实际重新构建成功，exit 0 |

Multer 补丁后的回归分别验证图片和语音入口拒绝过深字段、过大数组下标和超过 16 个字段（400），拒绝超过 10 MiB 的文件（413），并确认 API 在拒绝后继续返回 200。既有正常图片上传和私信行为同时通过。没有将最后局部回归表述为重新执行了全量 69 项 E2E。

可复现命令，测试前需配置独立测试数据库和对象存储环境变量：

```powershell
pnpm --dir server install --frozen-lockfile
pnpm --dir server typecheck
pnpm --dir server lint
pnpm --dir server build
pnpm --dir server test:unit --runInBand
pnpm --dir server test:integration --testTimeout=30000
pnpm --dir server test:e2e
pnpm --dir server exec jest --config test/jest-e2e.json --runInBand --testTimeout=30000 --runTestsByPath test/assets/image-upload.e2e-spec.ts test/content/dm-read.e2e-spec.ts
pnpm --dir server audit --prod --json
cd app
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --no-pub
```

本次直接调用本地 TypeScript、ESLint、Nest 和 Jest 的 Node 入口执行相同脚本，确认每个进程的退出状态。Android 首次需要下载 Gradle 8.14 和 Android SDK 35，通过现有代理完成；Kotlin 插件的 C:/E: 跨盘增量缓存出现警告后自动回退，最终构建成功，无需修改移动端源码来绕过。

## Multer 补丁与剩余依赖告警

官方 [Multer 2.3.0 release](https://github.com/expressjs/multer/releases/tag/v2.3.0) 确认修复相关拒绝服务漏洞；[数组下标告警](https://github.com/advisories/GHSA-535w-7cp7-47q4) 要求升级并设置 `fieldArrayIndexLimit`。

实际运行时通过 `@nestjs/platform-express` 的模块解析位置读取到 Multer **2.3.0**。锁文件只更新该包版本、完整性值和引用，未进行全局依赖升级。`server/pnpm-workspace.yaml` 固定 `overrides.multer: 2.3.0`；同时把原有 `onlyBuiltDependencies: agentscant` 从 pnpm 已警告不再读取的 package.json 配置迁入该文件。部署必须连同这个文件使用锁文件。

`BoundedUploadInterceptor` 对两个认证上传入口统一设置：10 MiB 文件、1 个文件、16 个普通字段、18 个 parts、128 字节字段名、4096 字节字段值、4 层嵌套和最大数组下标 16。原本只能在语音服务读完整个文件后检查大小的路径，现在在 multipart 解析时即受限。

生产依赖审计从 **6 high / 7 moderate / 2 low** 降至 **3 high / 6 moderate / 1 low，0 critical**，所有 Multer 告警消失。剩余告警不等于漏洞已消失；本次按代码调用方式核对适用性：

| 剩余项目 | 范围与边界 |
| --- | --- |
| brace-expansion：3 high，经 TypeORM → glob → minimatch | 本项目只使用源码固定的迁移 glob，未发现把用户输入传入 glob/brace expansion 的接口，因此未证实当前 HTTP 请求可达；若未来开放自定义文件模式，需重新评估。对应 GHSA-3jxr-9vmj-r5cp、GHSA-mh99-v99m-4gvg、GHSA-rgw5-rvv9-x895 |
| TypeORM：2 moderate | orderBy 注入项针对 MySQL/MariaDB 的 update/soft-delete，本项目使用 PostgreSQL且排序方向固定；migration:generate 注入项要求攻击者影响 schema metadata 并执行迁移生成，本项目无自动生成迁移或用户 DDL 接口。手工针对不可信数据库生成迁移仍需单独审查 |
| qs：3 moderate | 两项依赖 stringify 特定输入和配置，一项依赖 comma=true 解析；项目未直接调用 qs.stringify 或启用 comma 解析 |
| uuid：1 moderate | 涉及 v3/v5/v6 自定义输出 buffer；项目未使用该接口，ID 使用 randomUUID/数据库生成 |
| body-parser：1 low | 需要无效的 limit 配置；项目未设置由外部输入计算的 parser limit，使用框架默认限制 |

这是调用路径核对，不是“零漏洞”或“生产安全认证”。没有以不适用告警为理由引入大版本迁移。

## 真实离线语音链路

本机默认 Python 3.14 已安装 faster-whisper 1.2.1，存在 Systran/faster-whisper-small 的完整缓存。以 `HF_HUB_OFFLINE=1`、`local_files_only=True`、CPU/int8 实际加载成功，未安装或下载模型。

隔离 API 使用现有模型 snapshot 的绝对路径，并启用离线环境。测试音频由 Windows 已安装的离线 SAPI 生成，句子为：

> This is a local voice message for the agent. Please check the public website.

上传语音接口返回 201，约 8.6 秒完成。转写文本与输入一致；消息作者为 Human，contentType=audio，voice.source=human_stt。随后通过独立 GET 读取确认持久化，授权下载返回 200、1441378 字节、RIFF 头，匿名下载返回 401。

链路包含本地 ffmpeg 归一化、faster-whisper 转写、agentscant 音频编码、隔离对象存储和私信记录。agentscant 产物是协议编码音频，不是原始朗读音频；没有将该结果表述为自然人声播放质量验收。临时合成 WAV 和验收脚本已删除。API 与临时容器保留用于 Web 联调，凭据没有写入本报告。

## 仍需外部接入的功能

Google/GitHub OAuth 登录接口有意返回 501：现有代码尚未实现 provider token 验证，不能直接相信客户端传来的 email/providerSubject。此次保持禁用，未把它们计入可用登录能力。真实邮箱验证和密码重置的邮件投递需要配置有效邮件服务；本地验收使用日志投递模式，因此不构成真实邮箱送达验收。
## 移动端决定与发布边界

**保留 Flutter 移动端。** 当前 Dart/Flutter 代码能够通过静态分析和 127 项测试，已有录音、音频、图片选择与多语言等移动功能，并已成功重新生成 Android APK。没有发现必须整体重写才能解决的移动端架构问题。公开内容的可浏览、可分享和搜索索引需求由原生 Web 工程承担。

本次环境为 Flutter 3.41.5、Dart 3.11.3；flutter doctor 检查通过。Android APK 证据：

- 路径：`app/build/app/outputs/flutter-apk/app-debug.apk`（构建目录，不作为源码提交）。
- 时间：2026-09-12 12:30:54，Asia/Shanghai。
- 大小：196575795 字节。
- SHA-256：`9E1778A4790543BF6BC44CCD0EAE7BF31C6927F383855EE8186B731CC4D54FE5`。
- 构建：`flutter build apk --debug --no-pub`，exit 0；首次 Gradle 构建约 1521.8 秒。

当前未连接 Android 真机，没有做相机、麦克风权限或后台行为的真机验收；Windows 环境不能证明 iOS 签名和上架能力。Android 仍使用 `com.example.agents_chat_app`，release 配置仍引用 debug signing。正式移动端发布前需要确定生产包名、配置签名并完成真机与 iOS 构建验收。没有把 debug APK 成功等同于已可上架。


## 第二轮修复与运行诊断（2026-09-12）

本轮仅使用临时 PostgreSQL 55439 与 MinIO 59009，测试各自创建随机数据库并在结束后删除；3131 浏览器验收库独立保留。

- 密码重置立即关闭本进程该用户全部 WebSocket；到期定时关闭；每次推送前重新检查数据库 tokenVersion，跨进程吊销后不再推送私密内容。关闭码 1008。跨进程空闲连接在下次推送时关闭，没有新增跨节点广播基础设施。
- ACK、投递尝试、成功/失败、重连绑定和死信更新使用匹配状态/尝试次数的条件更新，避免旧实体覆盖已确认状态。真实 HTTP 接收器先 ACK，再返回 200、503 或断开连接，三种情况均保持 acked，且无重复投递。请求超时为生产 10 秒、测试 200 毫秒；同一进程不再重叠扫描。保留按 recipient 顺序投递及有限重试规则。
- 私信通知动态加入 Agent Member 的现任 Human owner，不信任旧 spectator；独立 Human Member 保留。历史私信通知和未读数也按当前关系过滤。真实 WebSocket 验证新 owner 尚无 participant 行仍收到消息，旧 owner 不收到且看不到历史通知预览。
- TypeORM save 返回实体的 eventId/threadId 因已初始化 nullable relation 字段变空，而数据库关联正确。通知保存后重读实体，恢复实时通知的详情关联；回归明确检查实际事件 ID。
- 目录关注数及双向关系改为批量读取。新增 `GET /api/v1/agents/public-directory/:handle` 直接查询公开 profile；私有、停用、不存在均 404，复用脱敏序列化。查询回归确认 follows 计数和关系只需两次批量查询，不随目录条数增长。

`GET /api/v1/agents/:agentId/runtime-status` 仅 owner 可读：匿名 401，非 owner/不存在 404，非法 UUID 400。提供 Agent 状态、最近通讯/heartbeat、新鲜度阈值、连接方式、各投递状态行数、最近尝试/确认/下次重试时间及脱敏最后错误。不返回 token、签名 secret、webhook URL、capabilities 或消息内容。

`presence.state` 中 disconnected 表示无连接记录；never_seen 表示有连接但没有通讯时间；recent/stale 按服务端阈值计算。计数是保留在数据库中的全部行的当前状态：pending/sent/retrying 为积压，acked/deadLetter 含保留历史。acked 只证明对端确认收取，不证明 Agent 执行或成功回复。lastError 为最近仍有错误的投递记录；null 只表示无未清除错误记录。

验证：新增 runtime-boundaries **10/10**；受影响原有 auth、notifications、agent-read、public-bootstrap、agent-safety-policy、realtime-fanout 与 federation/delivery **18/18**；unit **27/27**；typecheck、改动范围 ESLint 和 `pnpm build` 均通过。回归使用真实 WebSocket、本地 HTTP Webhook 与 PostgreSQL；浏览器验收由主报告补充。


### 最终真实动作复核

通过 Web 代理连续提交资料更新、同键重放和冲突请求时，实测动作结果为 succeeded 且结果 bio 正确，数据库 Agent.bio 却回到 null。根因为动作和轮询记录活跃时间时保存了整份旧 Agent/connection 实体。

新增 `agent-activity.ts` 将两条路径统一为精确列更新，通讯时间使用 GREATEST，只有 offline 可转 online；不写资料、所有权或原连接凭据，不恢复已删除连接。资料更新事务取得 Agent 行锁。回归模拟旧读取与资料更新、封禁、token rotation 交错，并执行真实动作重放与轮询。

最终 runtime-boundaries **13/13**；额外重跑受影响 delivery/agent-read/public-bootstrap **5/5**（属于前述既有回归的子集）。最终服务端完整 lint、typecheck、build 通过。经 3100 BFF 的完整 HTTP 探针最终确认 succeeded 后资料持久化正确，8组验收全部通过。
