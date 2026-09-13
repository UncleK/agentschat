"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { ArrowUpRight, Bell } from "lucide-react";
export function SessionNavigation() {
  const [signedIn, setSignedIn] = useState(false);
  const [unread, setUnread] = useState(0);
  const pathname = usePathname();
  useEffect(() => {
    const controller = new AbortController();
    let inFlight = false;
    const refresh = () => {
      if (inFlight || document.visibilityState !== "visible") return;
      inFlight = true;
      fetch("/api/session?status=1", {
        cache: "no-store",
        signal: controller.signal,
      })
        .then(async (result) => {
          if (!result.ok) return;
          const authenticated = (await result.json()).authenticated === true;
          if (controller.signal.aborted) return;
          setSignedIn(authenticated);
          if (!authenticated) {
            setUnread(0);
            return;
          }
          const bell = await fetch("/api/v1/notifications/bell-state", {
            cache: "no-store",
            signal: controller.signal,
          });
          if (bell.ok) {
            const state = await bell.json();
            if (!controller.signal.aborted) setUnread(state.unreadCount || 0);
          }
        })
        .catch(() => {})
        .finally(() => {
          inFlight = false;
        });
    };
    const expire = () => {
      setSignedIn(false);
      setUnread(0);
    };
    refresh();
    const timer = window.setInterval(refresh, 30000);
    window.addEventListener("focus", refresh);
    window.addEventListener("agents-chat:notifications-changed", refresh);
    window.addEventListener("agents-chat:session-expired", expire);
    return () => {
      controller.abort();
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
      window.removeEventListener("agents-chat:notifications-changed", refresh);
      window.removeEventListener("agents-chat:session-expired", expire);
    };
  }, [pathname]);
  return (
    <>
      <Link
        href="/notifications"
        className="header-icon header-notifications"
        aria-label={unread ? `通知，${unread} 条未读` : "通知"}
        title="通知"
      >
        <Bell size={19} />
        {unread > 0 && (
          <span className="header-unread" aria-hidden="true">
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </Link>
      <Link
        className="button button-small header-launch"
        href={signedIn ? "/settings" : "/login"}
      >
        {signedIn ? "账号" : "登录"} <ArrowUpRight size={15} />
      </Link>
    </>
  );
}
