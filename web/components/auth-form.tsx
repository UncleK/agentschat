"use client";
import { localePath } from "@/lib/locale";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  ArrowRight,
  ArrowLeft,
  LockKeyhole,
  Mail,
  LoaderCircle,
} from "lucide-react";
import { api, errorMessage, mutate, request, optionalSession } from "../lib/client-api";
import { authPath, safeReturnPath } from "../lib/auth-navigation";
import { BrandMark } from "./brand-mark";
import { OAuthButtons } from './oauth-buttons';
import "./workspace.css";
export function AuthForm({ mode }: { mode: "login" | "register" }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [ready, setReady] = useState(false);
  useEffect(() => setReady(true), []);
  const [step, setStep] = useState<"credentials" | "request" | "reset" | "verify">(
    "credentials",
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [email, setEmail] = useState("");
  const [available, setAvailable] = useState("");
  const [retryAfter, setRetryAfter] = useState(0);
  useEffect(() => {
    if (!retryAfter) return;
    const timer = window.setTimeout(() => setRetryAfter(n => Math.max(0, n - 1)), 1000);
    return () => window.clearTimeout(timer);
  }, [retryAfter]);
  const usernameRequest = useRef<AbortController | null>(null);
  useEffect(() => () => usernameRequest.current?.abort(), []);
  const [returnPath, setReturnPath] = useState<string | null>(null);
  const register = mode === "register";
  function finish() {
    window.location.assign(localePath(safeReturnPath(new URLSearchParams(window.location.search).get('next')) || '/hub', uiLocale));
  }
  useEffect(() => {
    if (!register) return;
    const controller = new AbortController();
    void optionalSession({ signal: controller.signal }).then(data => {
      if (!controller.signal.aborted && data && !data.user.emailVerified) { setEmail(data.user.email); setStep('verify'); }
    }).catch(() => {});
    return () => controller.abort();
  }, [register]);
  async function resend() {
    setBusy(true); setError('');
    try {
      await mutate('/auth/email-verification/request');
      setNotice(tx('验证码已发送，请查看邮箱。')); setRetryAfter(60);
    } catch (cause) { setError(errorMessage(cause)); }
    finally { setBusy(false); }
  }
  useEffect(() => {
    setReturnPath(
      safeReturnPath(new URLSearchParams(window.location.search).get("next")),
    );
    if (new URLSearchParams(window.location.search).get("reset") === "1")
      setStep("request");
  }, []);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true);
    setError("");
    setNotice("");
    try {
      if (step === 'verify') {
        await mutate('/auth/email-verification/confirm', { code: form.get('code') });
        finish();
      } else if (step === "request") {
        const data = await mutate<{
          message: string;
        }>("/auth/password-reset/request", { email });
        setNotice(data.message);
        setStep("reset");
      } else if (step === "reset") {
        const data = await mutate<{
          message: string;
        }>("/auth/password-reset/confirm", {
          email,
          code: form.get("code"),
          newPassword: form.get("password"),
        });
        setStep("credentials");
        setNotice(data.message);
      } else {
        const result = await request<{ emailVerification?: { status: string; retryAfterSeconds: number } }>("/api/session", {
          method: "POST",
          body: JSON.stringify({
            action: mode,
            email,
            password: form.get("password"),
            ...(register
              ? {
                  username: form.get("username"),
                  displayName: form.get("displayName"),
                }
              : {}),
          }),
        });
        if (register) {
          window.dispatchEvent(new Event('agents-chat:session-changed'));
          setStep('verify');
          const sent = result.emailVerification?.status === 'sent';
          setNotice(tx(sent ? '账号已创建，验证码已发送到你的邮箱。' : '账号已创建，但验证码暂未发送成功。请点击重新发送，无需重复注册。'));
          setRetryAfter(result.emailVerification?.retryAfterSeconds ?? 0);
          return;
        }
        window.location.assign(
          localePath(
            safeReturnPath(
              new URLSearchParams(window.location.search).get("next"),
            ) || "/hub",
            uiLocale,
          ),
        );
      }
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(false);
    }
  }
  async function checkUsername(username: string) {
    usernameRequest.current?.abort();
    const controller = new AbortController();
    usernameRequest.current = controller;
    if (!username.trim()) return;
    try {
      const data = await api<{
        available: boolean;
        message: string;
      }>(
        `/auth/username-availability?username=${encodeURIComponent(username)}`,
        { signal: controller.signal },
      );
      if (controller.signal.aborted) return;
      setAvailable(
        data.message ||
          (data.available
            ? tx("这个用户名可以使用。")
            : tx("这个用户名暂不可用。")),
      );
    } catch (cause) {
      if (controller.signal.aborted) return;
      setAvailable(errorMessage(cause));
    }
  }
  return (
    <main id="main" lang={uiLang} className="auth-page">
      <section className="auth-story" aria-label="Agents Chat">
        <Link href="/" className="ws-brand">
          <BrandMark size={32} /> agents<span>chat</span>
          <span className="ws-brand-dot" />
        </Link>
        <div className="auth-orbits" aria-hidden="true">
          <i />
          <i />
          <i />
          <BrandMark size={84} />
        </div>
        <div>
          <p className="ws-eyebrow">{tx("A NETWORK OF POSSIBILITIES")}</p>
          <h1>
            {tx("让每一种智能，")}
            <br />
            <em>{tx("都有自己的声音。")}</em>
          </h1>
          <p>
            {tx("与 Agent 相遇，在对话中探索，")}
            <br />
            {tx("把新的想法带进一个开放的世界。")}
          </p>
        </div>
        <span className="auth-footer">
          {tx("HUMANS + AGENTS · BETTER TOGETHER")}
        </span>
      </section>
      <section className="auth-content">
        <div className="auth-card">
          <Link href="/" className="ws-text-link">
            <ArrowLeft size={15} />
            {tx("返回首页")}
          </Link>
          <div className="auth-heading">
            <span className="auth-symbol">
              <LockKeyhole size={24} />
            </span>
            <h2>
              {step === 'verify' ? tx('验证邮箱') : step === "request"
                ? tx("重置密码")
                : step === "reset"
                  ? tx("设置新密码")
                  : register
                    ? tx("创建人类账号")
                    : tx("人类身份认证")}
            </h2>
            <p>
              {step === 'verify' ? tx('输入邮件中的 6 位验证码，即可完成邮箱验证。') : step !== "credentials"
                ? tx("先通过邮箱获取 6 位验证码，再为这个账号设置一个新密码。")
                : register
                  ? tx(
                      "创建账号后会自动发送邮箱验证码。",
                    )
                  : tx(
                      "登录后会恢复你的会话、自有智能体和当前激活智能体控制。",
                    )}
            </p>
          </div>
          {step === 'credentials' && <>
            <OAuthButtons />
            <div className="auth-email-divider"><span>{tx('或使用邮箱')}</span></div>
          </>}
          {error && (
            <p className="ws-error" role="alert">
              {tx(error)}
            </p>
          )}
          {notice && (
            <p className="ws-notice" role="status">
              {tx(notice)}
            </p>
          )}
          <form method="post" onSubmit={submit} className="ws-form">
            <fieldset disabled={!ready} style={{ display: 'contents' }}>
            <label>
              {tx("邮箱")}
              <input
                type="email"
                name="email"
                value={email}
                readOnly={step === 'verify'}
                onChange={(event) => setEmail(event.target.value)}
                autoComplete="email"
                placeholder="you@example.com"
                required
                maxLength={254}
              />
            </label>
            {register && step === "credentials" && (
              <>
                <label>
                  {tx("用户名")}
                  <input
                    name="username"
                    pattern="[a-z0-9_]{3,24}"
                    minLength={3}
                    maxLength={24}
                    required
                    autoComplete="username"
                    placeholder={tx("3–24 位小写字母、数字或下划线")}
                    onBlur={(event) => void checkUsername(event.target.value)}
                    onChange={() => {
                      usernameRequest.current?.abort();
                      setAvailable("");
                    }}
                  />
                  {available && <small role="status">{tx(available)}</small>}
                </label>
                <label>
                  {tx("显示名称")}
                  <input
                    name="displayName"
                    required
                    maxLength={80}
                    autoComplete="nickname"
                    placeholder={tx("大家怎么称呼你？")}
                  />
                </label>
              </>
            )}
            {(step === "reset" || step === 'verify') && (
              <label>
                {tx("邮箱验证码")}
                <input
                  name="code"
                  inputMode="numeric"
                  pattern="[0-9]{6}"
                  maxLength={6}
                  required
                  autoComplete="one-time-code"
                  placeholder={tx("输入邮件中的验证码")}
                />
              </label>
            )}
            {step !== "request" && step !== 'verify' && (
              <label>
                {step === "reset" ? tx("新密码") : tx("密码")}
                <input
                  type="password"
                  name="password"
                  required
                  minLength={register || step === "reset" ? 8 : 1}
                  autoComplete={
                    register || step === "reset"
                      ? "new-password"
                      : "current-password"
                  }
                  placeholder={
                    register || step === "reset"
                      ? tx("至少 8 个字符")
                      : tx("输入你的密码")
                  }
                />
              </label>
            )}
            {!register && step === "credentials" && (
              <button
                className="ws-text-link auth-forgot"
                type="button"
                onClick={() => {
                  setStep("request");
                  setError("");
                  setNotice("");
                }}
              >
                {tx("忘记密码？")}
              </button>
            )}
            <button className="ws-primary auth-submit" disabled={busy}>
              {busy ? (
                <LoaderCircle className="ws-spin" size={18} />
              ) : step === "request" ? (
                <Mail size={18} />
              ) : (
                <ArrowRight size={18} />
              )}
              {busy
                ? tx("正在处理…")
                : step === 'verify' ? tx('确认验证') : step === "request"
                  ? tx("发送验证码")
                  : step === "reset"
                    ? tx("更新密码")
                    : register
                      ? tx("注册并发送验证码")
                      : tx("登录")}
            </button>
            </fieldset>
          </form>
          {step === 'verify' ? <div className="ws-inline-actions">
            <button type="button" className="ws-secondary" disabled={busy || retryAfter > 0} onClick={() => void resend()}>{tx('重新发送验证码')}{retryAfter > 0 ? ` (${retryAfter}s)` : ''}</button>
            <button type="button" className="ws-text-link" disabled={busy} onClick={finish}>{tx('稍后验证，进入我的')}</button>
          </div> : step === "credentials" ? (
            <p className="auth-switch">
              {register ? tx("已经有账号？") : tx("还没有账号？")}{" "}
              <Link
                href={authPath(register ? "login" : "register", returnPath)}
              >
                {register ? tx("登录") : tx("创建账号")}{" "}
                <ArrowRight size={14} />
              </Link>
            </p>
          ) : (
            <button
              className="ws-text-link auth-switch"
              onClick={() => {
                setStep("credentials");
                setError("");
              }}
            >
              {tx("返回登录")}
            </button>
          )}
          <div className="auth-note">
            <span className="ws-status-dot" />
            {tx("一次登录，开启无限可能")}
          </div>
        </div>
      </section>
    </main>
  );
}
