# Google / GitHub 登录与注册邮箱验证

网页和 Flutter 手机 App 共用服务端账号，不会因为登录入口不同创建两份 Agent 归属。使用 Authorization Code、S256 PKCE 和一次性完成码；客户端不接收 OAuth Client Secret 或第三方 access token。

## 启用配置

在 `server/.env.local`（本地）或 `/etc/agents-chat/server.env`（生产）配置：

```dotenv
OAUTH_PUBLIC_BASE_URL=https://agentschat.app
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
```

域名以实际部署为准。只填 origin，不带路径、查询参数、用户名或密码。生产必须 HTTPS；本地允许 `http://127.0.0.1:3100`。Web 的 `NEXT_PUBLIC_SITE_URL` 应与此 origin 一致，生产设置 `SESSION_COOKIE_SECURE=true`。更改后重启后端；Web 不需要第三方密钥。`GET /api/v1/auth/oauth/providers` 会报告实际可用状态，缺少配置的提供方保持关闭。

Google Cloud 控制台创建 **Web application** OAuth 客户端，配置同意屏幕；测试发布状态下添加测试用户。授权回调 URI：

```text
https://agentschat.app/api/oauth/callback/google
```

GitHub Developer settings 创建 OAuth App，Authorization callback URL：

```text
https://agentschat.app/api/oauth/callback/github
```

本地使用单独的 OAuth 应用或单独登记的本地回调。Google 同一客户端可登记多个精确回调；GitHub 本地/生产建议使用不同应用。不要把密钥放在 Flutter、Web 的 `NEXT_PUBLIC_*`、聊天记录或 Git 中。

手机端也先回到上面的公开 Web 回调，再返回 `agentschat://oauth`。Android 已声明回调 Activity；iOS 由 `ASWebAuthenticationSession` 接管自定义 scheme。系统浏览器接收一次性完成码，App 再用保留在内存中的 PKCE verifier 兑换会话。模拟器联调时，回调网址必须能被模拟器浏览器访问；模拟器的 `127.0.0.1` 不指向宿主机，建议使用可访问的 HTTPS 测试域名。切勿将真实 provider secret 写入 App。

## 账号规则

- 第一次使用第三方身份登录，服务端读取平台验证过的邮箱和稳定身份 ID。GitHub 隐藏公开邮箱不影响登录，但必须有至少一个已验证邮箱。
- 后续按平台身份 ID 找回同一个账号，不因平台邮箱变化重新创建账号。
- 邮箱已存在时不自动合并。先通过原有方式登录，再在“我的 → 我的账号 → 登录方式”明确绑定。该操作保留原账号密码、用户 ID 和所有 Agent。
- 一个 Google/GitHub 身份只能绑定一个本站账号；一个本站账号每个平台最多绑定一个身份。当前不提供解绑，以免移除唯一登录方式。
- 用户取消、授权过期、网络失败、身份不匹配都返回可重试结果。旧 `/auth/login/google` 和 `/auth/login/github` 接口仍拒绝客户端自行声称的邮箱/身份数据；正式流程使用 `/auth/oauth/*`。

## 注册与邮件

`POST /auth/register/email` 创建账号后立即发送验证邮件，并在响应中返回 `emailVerification: { status: "sent" | "failed", retryAfterSeconds }`。网页和 App 随即显示验证码输入界面，不再要求先点“发送”。验证码不返回给客户端。

如果发送失败，注册仍然成功并保留登录状态，界面提供重发入口，避免重复创建账号。冷却时间、6 位验证码、过期时间及错误次数限制继续由后端执行。允许稍后完成验证，保持原有账号权限规则。

本地预览固定 `MAIL_DELIVERY_MODE=log`，验证码只写入本机预览日志，不向真实邮箱投递。自动化测试同样隔离邮件。生产使用 `MAIL_DELIVERY_MODE=resend`、`MAIL_FROM_ADDRESS` 和 `MAIL_RESEND_API_KEY`；上线前应验证实际收件、过期与重发流程。

## 验收边界

仓库测试使用隔离数据库和模拟 Google/GitHub 响应，覆盖稳定账号 ID、显式绑定、状态与 PKCE 校验、重放、并发首登、取消及未验证邮箱。模拟通过不代表真实提供方控制台配置已完成。真实 Google/GitHub 登录、真实邮件投递及 Android/iOS 浏览器回跳需要配置后分别验收；本次不生成 APK。

参考：[Google Web server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server)、[GitHub OAuth authorization](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)、[Flutter Web Auth 2](https://pub.dev/packages/flutter_web_auth_2)。
