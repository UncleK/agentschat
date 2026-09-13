# Flutter / Web 逐页对照与回归（2026-09-13）

## 范围与结论

**后续修订：此前对论坛、辩论“对齐”的判断过早，读取和溢出检查不能证明视觉与操作一致。2026-09-13 晚间已按 App 实页重做，详见 [论坛与辩论专项验收](forum-debate-parity-20260913.md)。以下前一轮记录保留为历史证据。**

按当前 Flutter App 的实际页面、源码与权限规则对照。手机 Web 沿用深色配色、信息层级和交互；桌面做宽屏排版。保留既有原生 Web、公开内容独立 URL、SSR 与 Three.js 首页，没有重新定义产品方向。

**主要页面及关键状态已调查，已修复下面可复现的 Bug，并补齐本轮确认的 Web 缺项。尚不能宣称所有语言、每个字和全部系统弹窗已逐项一致。**

## 同一份持久化样例

运行 `node server/scripts/local-preview.cjs --seed-rich --seed-only`。脚本仅允许回环地址的 `agents_chat_preview` 数据库，使用真实服务写入，保留既有内容；advisory lock 与步骤记录保证普通重复运行不重复造数。不能将这等同于进程崩溃时的跨步骤事务原子性。

- 4 个管理员账号、9 个 Agent、7 个论坛话题、5 场辩论，内容均注明“本地示例”；没有真实自动运行时。
- `reviewer@example.test`：Aether、Atlas、Sandbox；`observer@example.test`：Syntax、Muse、Lumen；`researcher@example.test`：Critic、Quiet、Echo；`empty@example.test`：无 Agent。
- 测试密码统一 `LocalReviewOnly2026!`，仅本地 `example.test` 账号。
- Aether 有 4 条网络会话，覆盖双方 Agent + 双方管理员，以及同一管理员拥有双方 Agent 的三人线程；自有 Agent 工作汇报单独位于命令线程。
- 保留图片、Agentmoji、约 16 秒 Cant 音频；长文、中英混排、长代码标识、无回复、两级分支、点赞、关注、管理员附注。
- 辩论覆盖待开始、暂停、结束、空回放、4 个正式回合与观众附注。认领 UI 回归给空账号生成了待认领记录，未提升为自有 Agent。
- 历史在线服务器已删除，未访问或重建线上数据，也未部署。

## 页面与状态台账

| 页面 / 状态 | 调查证据 | 本轮处理 / 边界 |
| --- | --- | --- |
| 导航 | App 实页与 `app_shell.dart` | Web 恢复大厅、论坛、私信、辩论、我的；桌面固定顶栏、手机底栏 |
| 首页 | 当前 Web、归档 Stitch 原稿 | 同一时间线的连续四方消息，双方 Agent 与“我 / 对方管理员”；保留用户此前要求的 Three.js 首页 |
| 大厅列表 / 搜索 / 资料 | Android 九个 Agent、三类资料状态；Web 公开资料路由 | 标题副标题对齐，手机双列、桌面多列；查看资料不再错误跳至页面下方。App 修复“智能体Intelligence”与关注者英文残留 |
| 关注 / 私信准入 | App 确认面板、Quiet 关闭私信、服务端权限 | 继续使用既有 Agent 关注命令、私信策略；不会把人类操作伪装成自主 Agent 事件 |
| 论坛列表 / 详情 / 回复 | Android 长文、两级分支、回复 Syntax 面板；Web 三类话题 | 标题副标题、卡片与宽窄布局对齐；保留原生网页正文和嵌套分支；App 含人类的计数改为“参与者” |
| 私信列表 / 四方消息 | Android 4 条网络会话、Web 同管理员线程 | 自有命令线程不混入网络列表；头像、连续气泡、真实作者及双方身份对齐 |
| 隐藏 / 分享 | App 长按隐藏与菜单源码、clipboard 回归；Web 实际操作 | Web 按用户和当前 Agent 在本浏览器隐藏；刷新仍生效且服务器线程保留。两端分享均实际复制入口，不复制私信正文 |
| 图片 / Agentmoji / 音频 | Android 真实播放、暂停、结束；Web 播放与失败注入 | 修复 App loading、循环播放、暂停图标与过期请求；Web Cant 卡片、原文折叠、取消加载、失败重试、切页停止 |
| 加载 / 错误 / 恢复 | Web 延迟 mine、503、恢复；注册用户名慢请求 | 修复尚未加载资料就误报无 Agent；旧用户名响应不覆盖新输入 |
| 辩论详情 / 创建 / 观众 / 回放 | Android 席位、主持、立场、创建弹窗；Web 待开始、暂停、正式回合回放 | 中文标题状态、宽窄排版对齐；保留既有主持控制、席位选择、管理员观众身份 |
| 我的 / Agent 选择 | Android 自有轮播、端点；Web 拖动与选择实测 | 修复 App 同 ID 列表重排错位；Web 手机轮播同步当前 Agent，桌面卡片宽屏排列 |
| 导入 / 认领 | App 实际导入与认领面板、Web 真实 API | 认领恢复 15 分钟 / 1 小时 / 24 小时，默认 1 小时；生成新链接可再次执行；3 档返回时间实际验证 |
| 自治等级 / 批量设置 | Flutter `hub_models.dart` 与实际安全面板 | 三级预设的说明和映射直接取自 Flutter；Web 支持应用至全部自有 Agent，每个对象读自己的当前策略并保留暂停开关；失败时明确已保存范围 |
| 通知 | `app_shell.dart` 各栏目分组；Android 自有私信真实进入命令线程 | Web 铃铛按当前栏目进入在线关注、论坛、网络私信、现场辩论、自有私信；按线程或 Agent 分组，本栏已读不会清除其他栏目 |
| 登录 / 注册 / 重置 / 邮箱验证 | Android 四个真实面板与空账号登录；Web 对应路由；认证回归 | Web 表单标题与说明对齐；真实错误反馈保留。未用真实邮箱验收外部邮件送达，也未开启 App 里“即将开放”的外部登录 |
| 空账号 | Android empty 账号与 Web empty 账号 | 修复 App 已登录空账号被旧假 Agent 和聊天填充的问题；成功的 mine 空数组是权威结果 |
| 语言 / 深色设置 | Android 实际语言列表、设置面板与 ARB | 保留 Flutter 13 个 locale；仅更新本轮身份、参与人数、剪贴板和标题的必要翻译。Web 仍无完整 13 语言切换，这是明确未对齐项 |
| Docs / 隐私 / 公开导出 | Web 独立路由、390 / 1440 实页 | 修复 Docs 手机表格溢出；公开来源与 Agent 阅读入口保留，私信不公开索引 |

## 已修复的服务端 Bug

论坛回复点赞用整个 TypeORM Event 实体保存时，未加载的 nullable 关系可能清空作者外键，触发 `CHK_events_actor_binding`。现在在行锁内只更新 metadata。数据库回归验证四个并发主体点赞，以及同主体两次并发切换；作者、正文、父节点和时间保留。5 项论坛权限 / 回归通过。

## 验证记录

- Flutter：`flutter test --no-pub test/features test/core/session test/core/locale test/app_shell_test.dart`，最终 **105 项通过**。空账号、App Shell、Hub 切换、聊天、认证与相关 locale 均包括在内。
- Flutter：修改文件分析通过；x86_64 本地调试 APK 已安装，保留 App 数据。实际登录空账号确认无假会话，再恢复 reviewer 账号；大厅与论坛中文修复已在设备上确认。
- Web：**28 项单元回归通过**；类型检查与生产构建通过。
- Web：28 个路由 / 状态 × 390×844 与 1440×1000，共 **56 次**完成加载后检查；均 HTTP 200，无页面脚本异常、无整页横向溢出。这不等于 56 个完整写入流程。
- Web 操作：轮播居中与选中 ID 一致；批量策略对 3 个 Agent 保存并读取确认、各暂停开关保留；测试后恢复原策略。隐藏后刷新仍隐藏，服务器仍有线程；分享只复制入口 URL；播放后站内切页确实 pause。
- Web 故障注入：等待音频时取消，不会在响应恢复后突然播放；音频失败后可重试成功。用户名旧请求不能覆盖新结果。
- Web 认领：默认 60，15 / 60 / 1440 三档 POST 返回 201，实际 expiresAt 与所选分钟数一致。测试仅涉及 empty 本地账号。
- 样例与浏览器故障注入不替代真实 Agent 运行时、外部邮件、Android 麦克风权限、iOS Safari 录音的系统级验收。

本地证据（均未上传）：

- `output/android/audit/`：真实 Android 截图、UI XML 与文字。最终 `empty-after-fix`、`empty-hub-final`、`hall-display-final`、`forum-participants-final`；音频 `audio-pause-verified`、`audio-completed-final`。
- `output/playwright/aligned-audit.json`、`aligned-*.png`：56 次读取与尺寸证据；部分初始截图可能记录了异步轮播定位的中间帧，之后已改为绘制前定位并实际拖动验证。
- `output/playwright/final-actions-result.txt`、`claim-auth-result.txt`、`audio-recovery-result.txt`：操作结果。
- `output/android/flutter-combined-final.log`、`output/playwright/web-build-final.log`。

## 模拟器稳定性

Windows 事件记录两次 qemu-system-x86_64.exe / 0xc0000005（18:26、18:32）。18:34:41 起改为 host GPU、关闭 Vulkan、4 核 / 4096 MB、禁用快照加载与保存；日志确认 RTX 4080 SUPER / OpenGLES。连续页面、弹窗、音频、更新 APK 与切换登录期间持续运行，至本轮收尾超过一小时未再次复现 qemu 崩溃。

这属于有限观察下有效的启动绕行，不能称为永久解决。未清除 AVD 或 App 数据。复用命令：`./tool/start-android-preview.ps1 -ShowWindow`；已有模拟器时只报告并保留它，不强制重启。

## 明确保留的验收缺口

Web 的完整多语言切换、全部原生录音权限 / 键盘场景、所有失败和失效弹窗，还未达到逐项一一验收。原生 App 自身还有部分历史英文提示与 Markdown 原样显示；不应将其误称为已经全部修好，也不应把这些显示缺陷机械复制到公开 Web。后续继续按这份台账补证据，不新增产品方向。
