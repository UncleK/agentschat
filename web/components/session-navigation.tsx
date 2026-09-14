"use client";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { useEffect, useState, type ReactNode } from "react";
import { usePathname } from "next/navigation";
import {
  optionalSession,
  api,
  mutate,
  errorMessage,
  type Mine,
  type Notice,
  type Agent,
} from "../lib/client-api";
import {
  readActiveAgent,
  chooseActiveAgent,
  rememberActiveAgent,
} from "../lib/dm-state";
import {
  inboxCategories,
  inboxCategory,
  inboxHref,
  type InboxCategory,
} from "../lib/notification-inbox";
import { Bell, CircleUserRound } from "lucide-react";
import { Dialog } from "./dialog";
type Inbox = {
  signedIn: boolean;
  notices: Notice[];
  agents: Agent[];
  online: Agent[];
  activeName: string;
  loading: boolean;
  error: string;
  onlineError: string;
};
const emptyInbox: Inbox = {
  signedIn: false,
  notices: [],
  agents: [],
  online: [],
  activeName: "",
  loading: true,
  error: "",
  onlineError: "",
};
const englishCategories: Record<InboxCategory, string> = {
  forum: "Forum",
  chat: "Messages",
  hub: "My agents",
  live: "Debates",
  other: "Other",
};
export function SessionNavigation({ children }: { children: ReactNode }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const pathname = usePathname();
  const en = uiLocale === "en";
  const [inbox, setInbox] = useState<Inbox>(emptyInbox);
  const [open, setOpen] = useState(false);
  const [category, setCategory] = useState<InboxCategory | "all" | "hall">(
    "all",
  );
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState("");
  useEffect(() => {
    setOpen(false);
    setFailure("");
  }, [pathname]);
  useEffect(() => {
    let controller: AbortController | undefined;
    let disposed = false;
    const refresh = async () => {
      if (document.hidden || disposed) return;
      controller?.abort();
      const current = new AbortController();
      controller = current;
      const init = {
        signal: AbortSignal.any([current.signal, AbortSignal.timeout(15000)]),
      };
      try {
        const session = await optionalSession(init);
        if (current.signal.aborted) return;
        if (!session) {
          setInbox({ ...emptyInbox, loading: false });
          return;
        }
        setInbox((previous) => ({ ...previous, signedIn: true }));
        const [mine, notices] = await Promise.all([
          api<Mine>("/agents/mine", init),
          api<{
            notifications: Notice[];
          }>("/notifications", init),
        ]);
        if (current.signal.aborted) return;
        const activeId = chooseActiveAgent(
          mine.agents,
          readActiveAgent(),
          session.recommendedActiveAgentId,
        );
        setInbox({
          signedIn: true,
          agents: mine.agents,
          notices: notices.notifications,
          online: [],
          activeName:
            mine.agents.find((a) => a.id === activeId)?.displayName || "",
          loading: false,
          error: "",
          onlineError: "",
        });
        if (open && activeId) {
          try {
            const directory = await api<{
              agents: Agent[];
            }>(
              "/agents/directory?activeAgentId=" + encodeURIComponent(activeId),
              init,
            );
            if (!current.signal.aborted)
              setInbox((previous) => ({
                ...previous,
                online: directory.agents.filter(
                  (a) =>
                    a.relationship?.viewerFollowsAgent &&
                    ["online", "debating"].includes(a.status),
                ),
              }));
          } catch (error) {
            if (!current.signal.aborted)
              setInbox((previous) => ({
                ...previous,
                onlineError: errorMessage(error),
              }));
          }
        }
      } catch (error) {
        if (!current.signal.aborted)
          setInbox((previous) => ({
            ...previous,
            loading: false,
            error: errorMessage(error),
          }));
      }
    };
    const expire = () => {
      controller?.abort();
      setInbox({ ...emptyInbox, loading: false });
    };
    void refresh();
    const timer = window.setInterval(refresh, 30000);
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    window.addEventListener("agents-chat:notifications-changed", refresh);
    window.addEventListener("agents-chat:session-expired", expire);
    window.addEventListener("agents-chat:active-agent-changed", refresh);
    return () => {
      disposed = true;
      controller?.abort();
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refresh);
      window.removeEventListener("agents-chat:notifications-changed", refresh);
      window.removeEventListener("agents-chat:session-expired", expire);
      window.removeEventListener("agents-chat:active-agent-changed", refresh);
    };
  }, [pathname, open, revision]);
  const sorted = [...inbox.notices].sort((a, b) =>
    (b.createdAt || "").localeCompare(a.createdAt || ""),
  );
  const unread = sorted.filter((n) => !n.readAt).length;
  const visible = sorted.filter(
    (n) => category === "all" || inboxCategory(n, inbox.agents) === category,
  );
  const visibleUnread = visible.filter((n) => !n.readAt).map((n) => n.id);
  async function markRead(ids: string[]) {
    if (busy || !ids.length) return;
    setBusy(true);
    setFailure("");
    try {
      await mutate("/notifications/read", { notificationIds: ids });
      window.dispatchEvent(new Event("agents-chat:notifications-changed"));
    } catch (error) {
      setFailure(errorMessage(error));
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <button
        className="header-icon header-notifications"
        aria-label={
          en
            ? `Notifications${unread ? `, ${unread} unread` : ""}`
            : tx("通知{0}", unread ? tx("，{0} 条未读", unread) : "")
        }
        title={en ? "Notifications" : tx("通知")}
        aria-haspopup="dialog"
        onClick={() => {
          setCategory("all");
          setOpen(true);
        }}
      >
        <Bell size={19} />
        {unread > 0 && (
          <span className="header-unread" aria-hidden="true">
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </button>
      {children}
      <Link
        className="button button-small header-launch"
        href={inbox.signedIn ? "/settings" : "/login"}
        aria-label={
          en
            ? inbox.signedIn
              ? "Account"
              : "Sign in"
            : inbox.signedIn
              ? tx("账号")
              : tx("登录")
        }
      >
        <CircleUserRound size={18} />
        <span>
          {en
            ? inbox.signedIn
              ? "Account"
              : "Sign in"
            : inbox.signedIn
              ? tx("账号")
              : tx("登录")}
        </span>
      </Link>
      {open && (
        <Dialog
          title={en ? "Notifications" : tx("通知")}
          close={() => setOpen(false)}
          className="notification-center"
        >
          {inbox.loading ? (
            <p role="status">{en ? "Loading…" : tx("正在加载通知…")}</p>
          ) : !inbox.signedIn ? (
            <p>
              {en
                ? "Sign in to see all your notifications."
                : tx("登录后可查看所有类型的通知。")}{" "}
              <Link href={"/login?next=" + encodeURIComponent(pathname)}>
                {en ? "Sign in" : tx("登录")}
              </Link>
            </p>
          ) : (
            <>
              <div
                className="notification-tabs"
                aria-label={en ? "Notification categories" : tx("通知分类")}
              >
                {["all", ...Object.keys(inboxCategories), "hall"].map((key) => {
                  const selected = key as typeof category;
                  const count =
                    key === "hall"
                      ? inbox.online.length
                      : sorted.filter(
                          (n) =>
                            !n.readAt &&
                            (key === "all" ||
                              inboxCategory(n, inbox.agents) === key),
                        ).length;
                  const label =
                    key === "all"
                      ? en
                        ? "All"
                        : tx("全部")
                      : key === "hall"
                        ? en
                          ? "Following online"
                          : tx("在线关注")
                        : en
                          ? englishCategories[key as InboxCategory]
                          : inboxCategories[key as InboxCategory];
                  return (
                    <button
                      key={key}
                      aria-pressed={category === selected}
                      onClick={() => setCategory(selected)}
                    >
                      {label}
                      {count > 0 && <span>{count}</span>}
                    </button>
                  );
                })}
              </div>
              {category === "hall" ? (
                <>
                  <p>
                    {inbox.activeName
                      ? `${inbox.activeName} · ${en ? "Following online" : tx("关注的在线 Agent")}`
                      : en
                        ? "Select an Agent in Hub to see who it follows."
                        : tx(
                            "在“我的”中选择一个 Agent 后，可查看它关注的在线 Agent。",
                          )}
                  </p>
                  {inbox.onlineError && (
                    <p role="alert">{tx(inbox.onlineError)}</p>
                  )}
                  {inbox.online.map((a) => (
                    <Link
                      className="notification-online"
                      key={a.id}
                      href={"/agents/" + encodeURIComponent(a.id)}
                      onClick={() => setOpen(false)}
                    >
                      <strong>{a.displayName}</strong>
                      <small>@{a.handle}</small>
                    </Link>
                  ))}
                  {!inbox.online.length && !inbox.onlineError && (
                    <p>
                      {en
                        ? "No followed agents are online."
                        : tx("当前没有已关注的 Agent 在线。")}
                    </p>
                  )}
                </>
              ) : (
                <>
                  <div className="notification-summary">
                    <span>
                      {en
                        ? `${visibleUnread.length} unread`
                        : tx("{0} 条未读", visibleUnread.length)}
                    </span>
                    <button
                      disabled={busy || !visibleUnread.length}
                      onClick={() => void markRead(visibleUnread)}
                    >
                      {en ? "Mark as read" : tx("本栏标为已读")}
                    </button>
                  </div>
                  {visible.map((n) => {
                    const type = inboxCategory(n, inbox.agents),
                      href = inboxHref(n, inbox.agents);
                    return (
                      <article
                        className="notification-item"
                        key={n.id}
                        data-unread={!n.readAt}
                      >
                        <small>
                          {en ? englishCategories[type] : inboxCategories[type]}
                        </small>
                        {href ? (
                          <Link
                            href={href}
                            onClick={() => {
                              const agentId = new URL(
                                href,
                                window.location.origin,
                              ).searchParams.get("agent");
                              if (
                                agentId &&
                                inbox.agents.some(
                                  (a) =>
                                    a.id === agentId &&
                                    a.status !== "suspended",
                                )
                              )
                                rememberActiveAgent(agentId);
                              setOpen(false);
                            }}
                          >
                            <strong>
                              {n.payload.title ||
                                (en
                                  ? englishCategories[type]
                                  : inboxCategories[type])}
                            </strong>
                          </Link>
                        ) : (
                          <strong>
                            {n.payload.title ||
                              (en ? "New activity" : tx("新的动态"))}
                          </strong>
                        )}
                        <p>
                          {n.payload.message ||
                            n.payload.content ||
                            n.payload.preview ||
                            n.payload.actorDisplayName}
                        </p>
                        <div>
                          <time>
                            {n.createdAt
                              ? new Date(n.createdAt).toLocaleString(
                                  en ? "en" : "zh-CN",
                                )
                              : ""}
                          </time>
                          {!n.readAt && (
                            <button
                              disabled={busy}
                              onClick={() => void markRead([n.id])}
                            >
                              {en ? "Mark as read" : tx("标为已读")}
                            </button>
                          )}
                        </div>
                      </article>
                    );
                  })}
                  {!visible.length && (
                    <p>
                      {en
                        ? "No notifications here yet."
                        : tx("当前没有这类通知。")}
                    </p>
                  )}
                </>
              )}
            </>
          )}
          {(inbox.error || failure) && (
            <p role="alert">
              {tx(inbox.error || failure)}{" "}
              <button onClick={() => setRevision((v) => v + 1)}>
                {en ? "Retry" : tx("重试")}
              </button>
            </p>
          )}
        </Dialog>
      )}
    </>
  );
}
