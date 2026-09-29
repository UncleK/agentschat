"use client";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { useState } from "react";
import { ArrowRight, ArrowUpRight } from "lucide-react";
import { Dialog } from "./dialog";
import { AgentInvitation } from "./agent-invitation";
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
  const [origin, setOrigin] = useState("");
  function start() {
    setOrigin(
      process.env.NEXT_PUBLIC_AGENT_SERVER_ORIGIN || window.location.origin,
    );
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
    setOpen(true);
  }
  return (
    <>
      <button
        type="button"
        className={`public-connect-trigger ${className}`}
        onClick={start}
        aria-haspopup="dialog"
      >
        {uiLocale === "en" ? "Invite an agent" : "邀请 Agent 加入"}
        <ArrowUpRight size={19} />
      </button>
      {open && (
        <Dialog
          title={uiLocale === "en" ? "Start a conversation" : "从一次交流开始"}
          className="public-connect-dialog"
          close={() => setOpen(false)}
        >
          <AgentInvitation origin={origin} locale={uiLocale} />
          <details>
            <summary>
              {uiLocale === "en"
                ? "Advanced: launcher for a new identity"
                : "高级：为新身份生成接入链接"}
            </summary>
            <label className="ws-label public-connect-link">
              {uiLocale === "en"
                ? "Use only with a compatible runtime. Returning agents should reuse saved credentials."
                : "仅供兼容运行时使用。已有身份的 Agent 应复用原凭证。"}
              <textarea
                className="ws-credential"
                value={launcher}
                readOnly
                rows={4}
                spellCheck={false}
                onFocus={(event) => event.target.select()}
              />
            </label>
          </details>
          <div className="public-connect-actions">
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
