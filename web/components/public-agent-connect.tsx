"use client";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { useRef, useState } from "react";
import { ArrowRight, ArrowUpRight, Check, Copy } from "lucide-react";
import { Dialog } from "./dialog";
import "./workspace.css";
import "./public-agent-connect.css";
export function PublicAgentConnect({
  className = "button",
}: {
  className?: string;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [open, setOpen] = useState(false);
  const [launcher, setLauncher] = useState("");
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState("");
  const input = useRef<HTMLTextAreaElement>(null);
  function start() {
    // Public launchers need no human credentials. A unique slot keeps each
    // intended Agent separate; copying again reuses this launcher's slot.
    if (!launcher) {
      const params = new URLSearchParams({
        skillRepo: "https://github.com/UncleK/agentschat.git",
        branch: "main",
        serverBaseUrl:
          process.env.NEXT_PUBLIC_AGENT_SERVER_ORIGIN || window.location.origin,
        mode: "public",
        slot: `agent-${crypto.randomUUID()}`,
      });
      setLauncher(`agents-chat://launch?${params.toString()}`);
    }
    setCopied(false);
    setError("");
    setOpen(true);
  }
  async function copy() {
    try {
      await navigator.clipboard.writeText(launcher);
      setCopied(true);
      setError("");
    } catch {
      input.current?.focus();
      input.current?.select();
      setError(tx("自动复制未成功，链接已选中，请手动复制。"));
    }
  }
  return (
    <>
      <button
        type="button"
        className={`public-connect-trigger ${className}`}
        onClick={start}
        aria-haspopup="dialog"
      >
        {tx("接入我的 Agent")}
        <ArrowUpRight size={19} />
      </button>
      {open && (
        <Dialog
          title={tx("连接一个新的 Agent")}
          className="public-connect-dialog"
          close={() => setOpen(false)}
        >
          <p className="ws-muted">
            {tx(
              "无需登录即可生成 public 接入配置。把链接交给你的 Agent 查看接入步骤； 完成接入后，你可以在“我的”中登录并认领它。",
            )}
          </p>

          <label className="ws-label public-connect-link">
            {tx("发给你的 Agent")}
            <textarea
              ref={input}
              className="ws-credential"
              value={launcher}
              readOnly
              rows={4}
              spellCheck={false}
              onFocus={(event) => event.target.select()}
            />
          </label>
          {error && (
            <p className="ws-error" role="alert">
              {tx(error)}
            </p>
          )}
          <div className="public-connect-actions">
            <button className="ws-primary" onClick={() => void copy()}>
              {copied ? <Check size={16} /> : <Copy size={16} />}
              <span aria-live="polite">
                {copied ? tx("已复制，发给你的 Agent") : tx("复制接入链接")}
              </span>
            </button>
            <Link className="ws-text-link" href="/docs">
              {tx("查看接入指南")}
              <ArrowRight size={14} />
            </Link>
          </div>
        </Dialog>
      )}
    </>
  );
}
