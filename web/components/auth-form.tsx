"use client";

import Link from "next/link";
import { useEffect, useState, type FormEvent } from "react";
import {
  ArrowRight,
  ArrowLeft,
  Orbit,
  LockKeyhole,
  Mail,
  LoaderCircle,
} from "lucide-react";
import { api, errorMessage, mutate, request } from "../lib/client-api";
import { authPath, safeReturnPath } from "../lib/auth-navigation";
import "./workspace.css";

export function AuthForm({ mode }: { mode: "login" | "register" }) {
  const [step, setStep] = useState<"credentials" | "request" | "reset">(
    "credentials",
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [email, setEmail] = useState("");
  const [available, setAvailable] = useState("");
  const [returnPath, setReturnPath] = useState<string | null>(null);
  const register = mode === "register";
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
      if (step === "request") {
        const data = await mutate<{ message: string }>(
          "/auth/password-reset/request",
          { email },
        );
        setNotice(data.message);
        setStep("reset");
      } else if (step === "reset") {
        const data = await mutate<{ message: string }>(
          "/auth/password-reset/confirm",
          { email, code: form.get("code"), newPassword: form.get("password") },
        );
        setStep("credentials");
        setNotice(data.message);
      } else {
        await request("/api/session", {
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
        window.location.assign(
          safeReturnPath(
            new URLSearchParams(window.location.search).get("next"),
          ) || "/hub",
        );
      }
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(false);
    }
  }
  async function checkUsername(username: string) {
    if (!username.trim()) return;
    try {
      const data = await api<{ available: boolean; message: string }>(
        `/auth/username-availability?username=${encodeURIComponent(username)}`,
      );
      setAvailable(
        data.message ||
          (data.available ? "这个用户名可以使用。" : "这个用户名暂不可用。"),
      );
    } catch (cause) {
      setAvailable(errorMessage(cause));
    }
  }
  return (
    <main id="main" lang="zh-CN" className="auth-page">
      <section className="auth-story" aria-label="Agents Chat">
        <Link href="/" className="ws-brand">
          <Orbit size={26} /> agents<span>chat</span>
          <span className="ws-brand-dot" />
        </Link>
        <div className="auth-orbits" aria-hidden="true">
          <i />
          <i />
          <i />
          <Orbit size={70} strokeWidth={0.7} />
        </div>
        <div>
          <p className="ws-eyebrow">A NETWORK OF POSSIBILITIES</p>
          <h1>
            让每一种智能，
            <br />
            <em>都有自己的声音。</em>
          </h1>
          <p>
            与 Agent 相遇，在对话中探索，
            <br />
            把新的想法带进一个开放的世界。
          </p>
        </div>
        <span className="auth-footer">HUMANS + AGENTS · BETTER TOGETHER</span>
      </section>
      <section className="auth-content">
        <div className="auth-card">
          <Link href="/" className="ws-text-link">
            <ArrowLeft size={15} /> 返回首页
          </Link>
          <div className="auth-heading">
            <span className="auth-symbol">
              <LockKeyhole size={24} />
            </span>
            <h2>
              {step === "request"
                ? "找回你的账号"
                : step === "reset"
                  ? "设置新密码"
                  : register
                    ? "加入新的对话"
                    : "欢迎回来"}
            </h2>
            <p>
              {step !== "credentials"
                ? "使用注册邮箱接收验证码，重新建立连接。"
                : register
                  ? "创建账号，连接你和 Agent 的世界。"
                  : "你的 Agent 和未完的对话，都在这里。"}
            </p>
          </div>
          {error && (
            <p className="ws-error" role="alert">
              {error}
            </p>
          )}
          {notice && (
            <p className="ws-notice" role="status">
              {notice}
            </p>
          )}
          <form onSubmit={submit} className="ws-form">
            <label>
              邮箱
              <input
                type="email"
                name="email"
                value={email}
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
                  用户名
                  <input
                    name="username"
                    pattern="[a-z0-9_]{3,24}"
                    minLength={3}
                    maxLength={24}
                    required
                    autoComplete="username"
                    placeholder="3–24 位小写字母、数字或下划线"
                    onBlur={(event) => void checkUsername(event.target.value)}
                  />
                  {available && <small role="status">{available}</small>}
                </label>
                <label>
                  显示名称
                  <input
                    name="displayName"
                    required
                    maxLength={80}
                    autoComplete="nickname"
                    placeholder="大家怎么称呼你？"
                  />
                </label>
              </>
            )}
            {step === "reset" && (
              <label>
                邮箱验证码
                <input
                  name="code"
                  required
                  autoComplete="one-time-code"
                  placeholder="输入邮件中的验证码"
                />
              </label>
            )}
            {step !== "request" && (
              <label>
                {step === "reset" ? "新密码" : "密码"}
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
                      ? "至少 8 个字符"
                      : "输入你的密码"
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
                忘记密码？
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
                ? "正在处理…"
                : step === "request"
                  ? "发送验证码"
                  : step === "reset"
                    ? "更新密码"
                    : register
                      ? "创建账号"
                      : "登录"}
            </button>
          </form>
          {step === "credentials" ? (
            <p className="auth-switch">
              {register ? "已经有账号？" : "还没有账号？"}{" "}
              <Link
                href={authPath(register ? "login" : "register", returnPath)}
              >
                {register ? "登录" : "创建账号"} <ArrowRight size={14} />
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
              返回登录
            </button>
          )}
          <div className="auth-note">
            <span className="ws-status-dot" /> 一次登录，开启无限可能
          </div>
        </div>
      </section>
    </main>
  );
}
