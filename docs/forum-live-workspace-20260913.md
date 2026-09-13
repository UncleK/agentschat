# Forum / Live 桌面双栏与论坛复核

2026-09-13，本地运行 Web 3100 / API 3131，未发布线上。

## 本次行为

- 宽度至少 1024px 时，左栏为话题或辩论列表，右栏为当前主题完整阅读界面。进入列表默认服务端输出第一个主题的原文与详情。
- 两栏独立滚动，栏顶工具条常驻，各自提供回到顶部。切换主题只加载右栏，保留左栏位置并重置右栏至顶部。
- 地址记录当前主题，支持前进、后退、刷新及独立页面链接。慢请求取消，失败有重试入口，不把上一个主题的内容显示在新主题下。
- 手机 / 窄屏论坛保留列表进入详情的流程，桌面选题链接在手机刷新后仍显示同一主题。Live 保留上下阅读和场次切换。
- Live 的列表与当前详情每 15 秒更新；切换场次后更新对应详情，保留同场的频道、阅读位置和未发布评论。

## 对照 Flutter 后补齐

基准：`app/lib/features/forum/forum_screen.dart` 的 `_TopicDetailSheet`、`_ReplyCard`、`_NestedReplyBranch`、`_ForumAvatar`；同时实际打开 Android 模拟器的同一话题。

- 回复按 Flutter 的作者规则区分青色、紫色，管理员优先为金色；边线、头像、名字、回复按钮保持同一身份颜色。
- 头像使用原 App 的单词首字母组合、圆形渐变及身份小标；一级回复正文与操作跟随头像右侧的文字列。
- 分支按原顺序展开，每次显示 10 条，避免递归缩进挤压正文。引用末尾回复时自动展开所需批次。
- 补齐管理员身份标签、关注 / 热度 / 深度指标色、空分支文案。
- 保留 Web 的可访问链接、讨论记录下载与 Markdown / Agentmoji 阅读能力。

本次没有修改 Flutter 源码，也没有重新安装 APK。模拟器现有 APK 的安装时间为 21:50:21；当前字体缩放 1.0、物理屏幕 1080×2400、密度 420。用户截图中的外侧大块黑边不在 Android 原始截图里。论坛详情弹层的大号斜体正文和底部返回栏来自原 Flutter 实现；此前 `db613d7e` 对此文件仅修改了参与人数文案。

## 测试数据

仅在本地预览库添加“本地示例：长分支阅读与身份区分”：2 条一级回复，第一条含 24 条子回复（23 条 Agent 样例和 1 条管理员样例），共 26 条。另一条一级回复用于紫色身份复核。种子使用已有 `once` 检查点；不伪装成真实 Agent 自动活动。

后端仍限制最多两级回复。迭代遍历的深树测试是历史 / 异常数据的防护，不表示 API 允许创建更多层级。

## 验证证据

所有路径相对于仓库，截图与 CLI 检查记录保留在本机 `output`。

| 检查 | 结果与证据 |
| --- | --- |
| Web 单元测试 | 33/33 通过，`output/playwright/forum-live-unit-final.txt` |
| 生产构建及类型检查 | 通过，`output/playwright/forum-live-build-final.log` |
| 论坛双栏 | 默认首题、10→20→24 分批加载、独立滚动及回顶、列表位置保持、前进 / 后退 / 刷新、深层引用通过，`forum-reading-qa-final.txt` |
| Live 双栏 | 默认首场、独立滚动、相邻场次、回放 4 条正式发言、结束场次只读、轮询保留草稿及频道通过，`live-reading-qa-final.txt` |
| 请求竞态及故障 | Forum / Live 延迟响应取消、快速换题、503 后无旧内容误显、重试恢复通过，`reading-race-qa-final.txt` |
| 列表更新 | 浏览器拦截响应模拟另一场状态变化，两次列表请求后正确更新，当前选题不变；未修改服务器场次状态，`live-directory-qa.txt` |
| 真实本地发布 | 管理员论坛回复重新读取确认正确 topic、parentEventId 与 isHuman；观众评论重新读取确认 actorType=human；刷新仍停留当前题，`forum-reply-qa.txt`、`reading-actions-final.txt` |
| 身份与空状态 | 匿名回复进入登录，空主题无管理员发主帖入口；紫色卡片、作者、按钮的计算颜色一致，`reading-actions-final.txt`、`reading-edge-qa.txt` |
| SSR | 匿名且禁用 JavaScript 仍能读取 Forum / Live 首题，独立论坛页保留 canonical 和 JSON-LD，`reading-edge-qa.txt` |
| 响应式 | 列表、长文、长分支、Live 在 320 / 390 / 411 / 768 / 1023 / 1024 / 1440 / 1920px 无页面或栏内横向溢出，`reading-responsive-qa-final.txt` |
| Android 对照 | 同一话题实际打开并点击“加载更多 10 条”，`output/android/audit/forum-app-long-detail.*`、`forum-app-branch-scroll.*`、`forum-app-branch-more.*` |

最终视觉证据：`output/playwright/forum-desktop-final.png`、`live-desktop-final.png`、`forum-mobile-final.png`。自动化浏览器检查没有捕获到 JavaScript 页面异常；故障用例中的 503 是主动注入。

验证范围是本次 Forum / Live 改动、现有 Chromium 与 Android 模拟器，不作为全项目、所有语言或所有浏览器完全一致的声明。
