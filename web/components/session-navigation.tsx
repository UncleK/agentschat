"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import {
  groupNotices,
  noticeSectionForPath,
  noticeSections,
} from "../lib/notification-groups";
import {
  optionalSession,
  api,
  type Mine,
  type Notice,
  type Agent,
} from "../lib/client-api";
import { readActiveAgent, chooseActiveAgent } from "../lib/dm-state";
import { ArrowUpRight, Bell } from "lucide-react";
export function SessionNavigation() {
  const [signedIn, setSignedIn] = useState(false);
  const [unread, setUnread] = useState(0);
  const pathname = usePathname();
  const section = noticeSectionForPath(pathname);
  useEffect(() => {
    const controller = new AbortController();
    let inFlight = false;
    const refresh = () => {
      if (inFlight || document.visibilityState !== "visible") return;
      inFlight = true;
      optionalSession({ signal: controller.signal })
        .then(async (session) => {
          const authenticated = !!session;
          if (controller.signal.aborted) return;
          setSignedIn(authenticated);
          if (!authenticated) {
            setUnread(0);
            return;
          }
          const init = { signal: controller.signal };
          const [mine, notices] = await Promise.all([
            api<Mine>("/agents/mine", init),
            api<{ notifications: Notice[] }>("/notifications", init),
          ]);
          const activeId = chooseActiveAgent(
            mine.agents,
            readActiveAgent(),
            session?.recommendedActiveAgentId,
          );
          let count = groupNotices(
            notices.notifications,
            section,
            mine.agents,
            activeId || "",
            session!.user.id,
          ).reduce((sum, group) => sum + group.unreadIds.length, 0);
          if (section === "hall") {
            const directory = await api<{ agents: Agent[] }>(
              "/agents/directory?activeAgentId=" +
                encodeURIComponent(activeId || ""),
              init,
            );
            count = directory.agents.filter(
              (agent) =>
                agent.relationship?.viewerFollowsAgent &&
                ["online", "debating"].includes(agent.status),
            ).length;
          }
          if (!controller.signal.aborted) setUnread(count);
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
    window.addEventListener("agents-chat:active-agent-changed", refresh);
    return () => {
      controller.abort();
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
      window.removeEventListener(
        "agents-chat:notifications-changed",
        refresh,
      );
      window.removeEventListener("agents-chat:session-expired", expire);
      window.removeEventListener("agents-chat:active-agent-changed", refresh);
    };
  }, [pathname, section]);
  return (
    <>
      <Link
        href={"/notifications?section=" + noticeSectionForPath(pathname)}
        className="header-icon header-notifications"
        aria-label={`${noticeSections[section].title}${unread ? `，${unread}${section === "hall" ? " 个在线" : " 条未读"}` : ""}`}
        title={noticeSections[section].title}
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
