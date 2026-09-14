"use client";
import { useI18n } from "@/components/locale-provider";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import Link from "@/components/localized-link";
import { usePathname } from "next/navigation";
import { basePath, localePath } from "@/lib/locale";
import { Search } from "lucide-react";
import { Dialog } from "./dialog";
// The page owns its search state; only its trigger moves into the shared header.
export function HeaderSearch({
  label,
  open,
  disabled = false,
}: {
  label: string;
  open: () => void;
  disabled?: boolean;
}) {
  const [target, setTarget] = useState<HTMLElement | null>(null);
  useEffect(() => {
    setTarget(document.getElementById("header-page-search"));
  }, []);
  return target
    ? createPortal(
        <button
          className="header-icon page-search-action"
          aria-label={label}
          title={label}
          onClick={open}
          disabled={disabled}
        >
          <Search size={19} />
        </button>,
        target,
      )
    : null;
}
export function HeaderSearchSlot() {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const pathname = basePath(usePathname());
  const [open, setOpen] = useState(false);
  useEffect(() => {
    setOpen(false);
  }, [pathname]);
  const privatePage = /^\/(hub|messages|settings|connections)(\/|$)/.test(
    pathname,
  );
  const own = !pathname.startsWith("/messages");
  const en = uiLocale === "en";
  const label = privatePage
    ? own
      ? tx("搜索我的 Agent")
      : tx("查找对话")
    : en
      ? "Search agents"
      : tx("搜索智能体");
  return (
    <>
      <span id="header-page-search" className="header-search-slot">
        <button
          className="header-icon header-search-fallback"
          aria-label={label}
          title={label}
          onClick={() => setOpen(true)}
        >
          <Search size={19} />
        </button>
      </span>
      {open && (
        <Dialog title={label} close={() => setOpen(false)}>
          {privatePage ? (
            <p>
              {tx(
                "请先登录并加载{0}，然后即可搜索。",
                own ? tx("我的 Agent") : tx("私信"),
              )}
              <Link href={"/login?next=" + encodeURIComponent(pathname)}>
                {tx("登录")}
              </Link>
            </p>
          ) : (
            <form className="ws-form" action={localePath("/agents", uiLocale)}>
              <label>
                {en ? "Name, expertise or tag" : tx("名称、专长或标签")}
                <input
                  autoFocus
                  name="q"
                  placeholder={en ? "Find an agent" : tx("查找智能体")}
                />
              </label>
              <button className="ws-primary">
                {en ? "Search" : tx("搜索")}
              </button>
            </form>
          )}
        </Dialog>
      )}
    </>
  );
}
