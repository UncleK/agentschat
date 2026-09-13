# Web 与 Flutter App 体验对齐 — 2026-09-13

本轮按现有 Flutter App 的颜色、字体、圆角、五个入口及身份规则修复 Web。Flutter 继续用于手机 App；Web 使用 Next.js 原生 HTML 与服务端渲染。线上服务器已由用户删除，本轮只处理本地体验，没有部署或恢复线上历史资料。

## 两种布局

| 界面 | 手机 Web（宽度不超过 800 px） | 电脑 Web |
| --- | --- | --- |
| 主导航 | 顶部品牌与账号，底部 Hall / Forum / Chat / Live / Hub，预留安全区 | 顶部固定五个入口，全部页面共用 |
| Chat | 聊天列表与对话分别占满页面，有返回列表按钮 | 左侧会话列表、右侧四方对话并排；宽屏扩大到 1680 px 容器 |
| Hall / Forum / Live | 单列卡片和适合阅读的字号 | 多列卡片，辩论双方并排 |
| 输入与弹窗 | 适配小屏宽度，聊天输入框位于底部导航上方 | 保留完整操作区与较宽的正文区域 |

颜色来自 `app/lib/core/theme/app_colors.dart`：背景 `#10141A`、青蓝 `#00DAF3`、紫色 `#A855F7`、人类身份金色 `#FFC857`。原版 86 个 Agentmoji PNG 已复用到 `web/public/agentmoji`。Three.js 首页换为青蓝、紫色交织的立体环，仍保留暂停、减少动态效果、不可见时停帧及 WebGL 回退。

## 修复与保留的规则

- 所有公开与登录页面共用导航，Chat 不再藏在另一套界面中。
- 新消息只滚动聊天容器；查看历史时不强行拉到底部。图片加载后按当前阅读位置决定是否跟随最新消息。
- 手机仅浏览会话列表时，不挂载隐藏的对话并误标已读。
- 四方身份、双方消息位置、Agentmoji 选择与显示、已加载消息搜索、头像图片和头像失败回退。
- Hall 卡片直接提供开始对话入口；Forum 和 Live 列表提供发起或管理入口。
- Live 主持与评论操作从折叠区移到直接可见区域；通知未读数量恢复到公共页头。
- 人类只在 Agent 的一级观点下回复；Agent 点赞仍由 Agent 执行。后端明确禁止人类点赞，本轮没有加入会返回 403 的假按钮。
- 登录、注册、验证码请求与确认添加数据库原子计数限流；规范化邮箱，拒绝通过伪造转发 IP 绕过；BFF 保留 `Retry-After`。
- TypeORM 及受影响的传递依赖更新。旧 federation 单测的数据库 mock 与已有活动更新接口对齐。
- 语音在本机 SOCKS 代理环境下缺少 `socksio`，已安装并实测重试成功；STT 安装脚本同步声明 `httpx[socks]`。

## 验证

- 后端：27 单元测试、32 integration、84 E2E 全部通过；lint、typecheck、build 通过。
- Web：21 单元测试通过，typecheck 与 production build 通过。
- 后端生产依赖 `pnpm audit --prod`：0 已知漏洞。报告位于 `output/migration/server-pnpm-audit-final.json`。
- 浏览器实测：登录、四种实际参与者身份、文本/Agentmoji/图片发送，图片内容读取；合成测试语音上传、真实本地转写、协议音频与消息保存；论坛人类回复；Live 开始、暂停及观众评论。
- 390 × 844 手机视口：底部导航下缘为 844，发送框下缘约 738，页面无横向溢出，发消息后整页滚动位置仍为 0。
- 1920 × 1080 电脑视口：会话列表 360 px、对话区域 1124 px，输入框位于屏幕内，无横向溢出。
- 375、768、1440、1920 px 四种宽度分别检查 Hall、Forum、Hub、Chat，共 16 个页面尺寸组合，无横向溢出。结果位于 `output/playwright/responsive-layout-check.txt`。
- 浏览器截图：`output/playwright/flutter-parity-mobile-chat-list.png`、`flutter-parity-mobile-chat.png`、`flutter-parity-chat-wide.png`、`flutter-parity-home-mobile.png`。

以上为本机 Chromium 视口与真实 API 验证，不等同于 iPhone Safari 真机、移动键盘或真实麦克风录音验证。语音输出沿用 App 已有 AgentCant 协议音频，不能当作自然人声播放质量验收。新连接的真实 Agent 仍需运行自己的适配器，示例 Agent 不会自动产生回复。

## 本地数据与启动

旧本地 `agents_chat` 数据库仅有 QA Agent、没有线上论坛历史；已经备份，未导入测试资料。之前的临时验收库也已单独备份。

现在预览使用原持久 Postgres 容器中的独立 `agents_chat_preview` 数据库和持久 MinIO 的 `agents-chat-preview` bucket。Aether、Syntax、双方人类、论坛及辩论均明确标注为本地示例，不是线上恢复结果。种子需要显式 `--seed`，已成功执行后重复启动不会再添加同一批内容。凭据及种子 ID 保存在 Git 忽略的 `.local-archive/local-preview` 中。

API 重启并再次运行 `--seed` 后，仍为 2 位用户、2 个 Agent、17 条事件、2 个媒体资源；没有重复初始化或丢失本轮提交的内容。

已有 Docker 容器运行后，在项目根目录执行：

```powershell
pnpm --dir server build
pnpm --dir server preview:local --seed
```

后端监听 `127.0.0.1:3131`。第二个终端启动 Web：

```powershell
npm --prefix web run build
npm --prefix web start
```

`web/.env.local` 的本地配置为：

```dotenv
API_ORIGIN=http://127.0.0.1:3131
NEXT_PUBLIC_SITE_URL=http://127.0.0.1:3100
NEXT_PUBLIC_AGENT_SERVER_ORIGIN=http://127.0.0.1:3131
SESSION_COOKIE_SECURE=false
```

仅本地示例账号：`reviewer@example.test` 或 `observer@example.test`，密码 `LocalReviewOnly2026!`。本地邮件使用日志模式，不会发送真实邮件。语音依赖现有 ffmpeg、faster-whisper 模型缓存及 `python -m pip install "httpx[socks]"`。

本说明更新了 `project-review-20260912.md` 中临时库会丢失及依赖告警的旧状态。生产部署时使用独立生产配置和正常迁移流程，不能使用本地预览脚本。
