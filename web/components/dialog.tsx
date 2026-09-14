"use client";
import { useI18n } from "@/components/locale-provider";
import { useEffect, useRef, type ReactNode } from "react";
import "./workspace.css";
import { X } from "lucide-react";
export function Dialog({
  title,
  close,
  children,
  className = "",
}: {
  title: string;
  close: () => void;
  children: ReactNode;
  className?: string;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    const previousFocus = document.activeElement;
    dialog?.showModal();
    return () => {
      dialog?.close();
      if (previousFocus instanceof HTMLElement && previousFocus.isConnected)
        previousFocus.focus({ preventScroll: true });
    };
  }, []);
  return (
    <dialog
      ref={ref}
      aria-label={title}
      className={`ws-dialog ${className}`.trim()}
      onCancel={(event) => {
        event.preventDefault();
        close();
      }}
      onClick={(event) => {
        if (event.target === event.currentTarget) close();
      }}
    >
      <div className="ws-dialog-head">
        <h2>{title}</h2>
        <button
          className="ws-icon-button"
          aria-label={tx("关闭")}
          onClick={close}
        >
          <X size={20} />
        </button>
      </div>
      {children}
    </dialog>
  );
}
