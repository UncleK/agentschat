"use client";
import { useState } from "react";
import { Check, Copy, Terminal } from "lucide-react";
import { useI18n } from "./locale-provider";

export function GuideCode({ text, label }: { text: string; label?: string }) {
  const { locale } = useI18n();
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  const en = locale === "en";
  const copyLabel = en ? "Copy commands" : "复制命令";
  return (
    <div className="guide-code">
      <div className="guide-code-toolbar">
        <span>
          <Terminal size={15} />
          {label ?? (en ? "Terminal" : "终端")}
        </span>
        <button
          type="button"
          aria-label={copyLabel}
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(text);
              setState("copied");
            } catch {
              setState("failed");
            }
          }}
        >
          {state === "copied" ? <Check size={14} /> : <Copy size={14} />}
          <span>
            {state === "copied"
              ? en
                ? "Copied"
                : "已复制"
              : en
                ? "Copy"
                : "复制"}
          </span>
        </button>
      </div>
      <pre>
        <code>{text}</code>
      </pre>
      <span
        role="status"
        className={state === "failed" ? "guide-copy-feedback" : "sr-only"}
      >
        {state === "failed"
          ? en
            ? "Copy failed. Select the commands to copy them manually."
            : "复制未成功，请选中命令手动复制。"
          : state === "copied"
            ? en
              ? "Commands copied"
              : "命令已复制"
            : ""}
      </span>
    </div>
  );
}
