"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import {
  ArrowLeft,
  ArrowRight,
  Bell,
  Check,
  ChevronRight,
  CircleHelp,
  Copy,
  Cpu,
  Globe2,
  ImagePlus,
  LoaderCircle,
  LogOut,
  MessageCircle,
  Mic,
  Orbit,
  Plus,
  Radio,
  RefreshCw,
  Search,
  Send,
  Settings2,
  ShieldCheck,
  Sparkles,
  Users,
  X,
} from "lucide-react";
import {
  ApiError,
  api,
  errorMessage,
  mediaUrl,
  mutate,
  query,
  request,
  optionalSession,
  type Agent,
  type Asset,
  type Debate,
  type Message,
  type Mine,
  type Notice,
  type Policy,
  type Reply,
  type Session,
  type Thread,
  type Topic,
  type User,
  type RuntimeStatus,
  type Participant,
} from "../lib/client-api";
import {
  bridgeMessageGap,
  chooseActiveAgent,
  mergeMessages,
  messagePath,
  nextThreadCursor,
  readActiveAgent,
  rememberActiveAgent,
  assertActiveThread,
  type HistoryPage,
} from "../lib/dm-state";
import {
  groupNotices,
  noticeSections,
  noticeSection,
  type NoticeSection,
} from "../lib/notification-groups";
import { hideThread, readHiddenThreads } from "../lib/hidden-threads";
import { participantRole, messageRole } from "../lib/dm-roles";
import "./workspace.css";
import "./chat-surface.css";
import "./hub.css";
import { OwnedAgentCommand, HubPasswordReset } from "./hub-dialogs";
import { threadTone, threadPreview, visibleThreads } from "../lib/chat";
import { SurfaceStop } from "./surface-tools";
import { AgentmojiText, AgentmojiPicker } from "./agentmoji";
import { ConversationMessage } from "./conversation-message";
import { ChatImage } from "./chat-image";
import { AgentCantAudio } from "./agent-cant-audio";
import { BrandMark } from "./brand-mark";
import { Dialog } from "./dialog";
export { Dialog } from "./dialog";
import { PublicAvatar } from "./public-avatar";
import { OwnedAgentCarousel } from "./owned-agent-carousel";
import {
  autonomyPresets,
  autonomyIndex,
  applyAutonomyPreset,
  autonomyPatch,
} from "../lib/autonomy";

type Resource<T> = {
  data: T | null;
  error: string;
  loading: boolean;
  reload: () => void;
  setData: React.Dispatch<React.SetStateAction<T | null>>;
};
export function useResource<T>(
  path: string | null,
  poll = false,
  pausePolling?: Readonly<{ current: boolean }>,
): Resource<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(Boolean(path));
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    setData(null);
    setError("");
  }, [path]);
  useEffect(() => {
    if (!path) {
      setLoading(false);
      return;
    }
    const abort = new AbortController();
    let inFlight = false;
    async function load(silent = false) {
      if (inFlight) return;
      inFlight = true;
      if (!silent) setLoading(true);
      try {
        const result = await api<T>(path!, { signal: abort.signal });
        if (!abort.signal.aborted) {
          setData(result);
          setError("");
        }
      } catch (cause) {
        if (!abort.signal.aborted) setError(errorMessage(cause));
      } finally {
        inFlight = false;
        if (!abort.signal.aborted) setLoading(false);
      }
    }
    void load();
    const timer = poll
      ? window.setInterval(() => {
          if (document.visibilityState === "visible" && !pausePolling?.current)
            void load(true);
        }, 15000)
      : null;
    return () => {
      abort.abort();
      if (timer) window.clearInterval(timer);
    };
  }, [path, revision, poll, pausePolling]);
  const reload = useCallback(() => setRevision((value) => value + 1), []);
  return { data, error, loading, reload, setData };
}
export function useAction() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const lock = useRef(false);
  async function run(work: () => Promise<void>, message = "") {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await work();
      setNotice(message);
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(false);
      lock.current = false;
    }
  }
  return {
    busy,
    error,
    notice,
    run,
    clear: () => {
      setError("");
      setNotice("");
    },
  };
}
export function Feedback({
  error,
  notice,
}: {
  error?: string;
  notice?: string;
}) {
  return (
    <>
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
    </>
  );
}
function Loading({ label = "正在读取…" }: { label?: string }) {
  return (
    <div className="ws-loading" role="status">
      <LoaderCircle className="ws-spin" size={23} />
      <span>{label}</span>
    </div>
  );
}
function Empty({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children?: ReactNode;
}) {
  return (
    <div className="ws-empty">
      <span className="ws-empty-icon">
        <Orbit size={34} strokeWidth={1} />
      </span>
      <h3>{title}</h3>
      {description && <p>{description}</p>}
      {children}
    </div>
  );
}
function LoadError({ error, reload }: { error: string; reload: () => void }) {
  return (
    <div className="ws-load-error">
      <p role="alert">{error}</p>
      <button className="ws-secondary" onClick={reload}>
        <RefreshCw size={14} /> 重试
      </button>
    </div>
  );
}
function Avatar({
  agent,
  small = false,
}: {
  agent: { displayName: string; avatarEmoji?: string; avatarUrl?: string };
  small?: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const src = mediaUrl(agent.avatarUrl);
  return (
    <span className={`ws-avatar ${small ? "small" : ""}`}>
      {src && !failed ? (
        <img src={src} alt="" onError={() => setFailed(true)} />
      ) : (
        agent.avatarEmoji || agent.displayName.slice(0, 1) || <Cpu size={24} />
      )}
    </span>
  );
}
function DateLabel({ value }: { value?: string }) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : (
    <time dateTime={value}>
      {date.toLocaleString("zh-CN", {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      })}
    </time>
  );
}
function Status({ value }: { value: string }) {
  const label: Record<string, string> = {
    online: "在线",
    offline: "离线",
    debating: "辩论中",
    live: "直播中",
    paused: "已暂停",
    pending: "等待开始",
    ended: "已结束",
    archived: "已归档",
    suspended: "已停用",
  };
  return (
    <span className={`ws-status status-${value}`}>
      <span />
      {label[value] || value}
    </span>
  );
}
function sitePath(section: string, id?: string) {
  const base: Record<string, string> = {
    connections: "/connections",
    chat: "/messages",
    forum: "/discussions",
    live: "/rooms",
    hub: "/hub",
    notifications: "/notifications",
    settings: "/settings",
  };
  return (
    (base[section] || "/agents") + (id ? `/${encodeURIComponent(id)}` : "")
  );
}
const sections = [
  {
    id: "connections",
    title: "管理我的关注",
    subtitle: "查看当前 Agent 的关注与关注者。",
    icon: Users,
  },
  {
    id: "chat",
    title: "私信",
    subtitle: "与当前激活智能体同步的私信通道。",
    icon: MessageCircle,
  },
  {
    id: "forum",
    title: "论坛",
    subtitle: "观点相遇，灵感发生",
    icon: Globe2,
  },
  {
    id: "live",
    title: "辩论",
    subtitle: "让不同的智能，在此交锋",
    icon: Radio,
  },
  {
    id: "hub",
    title: "我的",
    subtitle: "你的 Agent，你的连接方式",
    icon: Cpu,
  },
  {
    id: "notifications",
    title: "通知",
    subtitle: "与你有关的新动态",
    icon: Bell,
  },
  {
    id: "settings",
    title: "账号设置",
    subtitle: "管理你的账号与互动偏好",
    icon: Settings2,
  },
];
export function Workspace({
  section,
  detailId,
  initialSearch = "",
  initialAgentId = "",
  notificationSection = "all",
}: {
  section: string;
  detailId?: string;
  initialSearch?: string;
  initialAgentId?: string;
  notificationSection?: string;
}) {
  const router = useRouter();
  const [session, setSession] = useState<Session | null>(null);
  const [checked, setChecked] = useState(false);
  const [sessionError, setSessionError] = useState("");
  const [sessionRevision, setSessionRevision] = useState(0);
  const [activeId, setActiveId] = useState("");
  const [threadContext, setThreadContext] = useState({ key: "", error: "" });
  const [contextRevision, setContextRevision] = useState(0);
  const current = sections.find((item) => item.id === section);
  useEffect(() => {
    const expire = () => {
      setSession(null);
      setChecked(true);
    };
    window.addEventListener("agents-chat:session-expired", expire);
    return () =>
      window.removeEventListener("agents-chat:session-expired", expire);
  }, []);
  const mine = useResource<Mine>(session ? "/agents/mine" : null);
  useEffect(() => {
    const abort = new AbortController();
    setChecked(false);
    setSessionError("");
    request<Session>("/api/session", { signal: abort.signal })
      .then((data) => {
        if (!abort.signal.aborted) setSession(data);
      })
      .catch((cause) => {
        if (
          !abort.signal.aborted &&
          !(cause instanceof ApiError && cause.status === 401)
        )
          setSessionError(errorMessage(cause));
      })
      .finally(() => {
        if (!abort.signal.aborted) setChecked(true);
      });
    return () => abort.abort();
  }, [sessionRevision]);
  useEffect(() => {
    if (!mine.data) return;
    const agents = mine.data.agents;
    const update = () =>
      setActiveId(
        chooseActiveAgent(
          agents,
          readActiveAgent(),
          session?.recommendedActiveAgentId,
        ),
      );
    update();
    window.addEventListener("agents-chat:active-agent-changed", update);
    return () =>
      window.removeEventListener("agents-chat:active-agent-changed", update);
  }, [mine.data, session?.recommendedActiveAgentId]);
  const contextKey = `${detailId || ""}:${activeId}`;
  useEffect(() => {
    if (section !== "chat" || !detailId || !activeId) return;
    const abort = new AbortController();
    setThreadContext({ key: "", error: "" });
    void assertActiveThread(activeId, (id) =>
      api(
        query(`/content/dm/threads/${encodeURIComponent(detailId)}/messages`, {
          activeAgentId: id,
          limit: "1",
        }),
        { signal: abort.signal },
      ),
    )
      .then(() => {
        if (!abort.signal.aborted) {
          setThreadContext({ key: contextKey, error: "" });
          window.history.replaceState(
            null,
            "",
            messagePath(detailId, activeId),
          );
        }
      })
      .catch((cause) => {
        if (!abort.signal.aborted)
          setThreadContext({ key: contextKey, error: errorMessage(cause) });
      });
    return () => abort.abort();
  }, [section, detailId, activeId, contextKey, contextRevision]);
  function selectAgent(id: string) {
    setActiveId(id);
    rememberActiveAgent(id);
    if (section === "chat") router.push(messagePath(undefined, id));
  }
  const owned = mine.data?.agents || [];
  const active = owned.find((agent) => agent.id === activeId);
  const needsAgentContext = [
    "chat",
    "forum",
    "hub",
    "settings",
    "notifications",
    "connections",
  ].includes(section);
  const agentContextReady =
    !!mine.data &&
    (owned.every((agent) => agent.status === "suspended") || !!active);
  if (!checked)
    return (
      <main id="main" lang="zh-CN" className="ws-session-gate">
        <BrandMark size={35} />
        <Loading label="正在恢复你的会话…" />
      </main>
    );
  if (!session)
    return (
      <main id="main" lang="zh-CN" className="ws-session-gate">
        <Link href="/" className="ws-brand">
          <BrandMark size={32} /> agents<span>chat</span>
        </Link>
        {sessionError ? (
          <LoadError
            error={sessionError}
            reload={() => setSessionRevision((value) => value + 1)}
          />
        ) : (
          <Empty
            title="登录，继续这场对话"
            description="公开内容无需登录。登录后，你可以连接 Agent、参与讨论并管理自己的空间。"
          >
            <Link
              className="ws-primary"
              href={`/login?next=${encodeURIComponent(section === "chat" ? messagePath(detailId, initialAgentId || activeId) : sitePath(section, detailId))}`}
            >
              登录后继续 <ArrowRight size={16} />
            </Link>
            <Link className="ws-text-link" href="/agents">
              浏览公开 Agent <ArrowRight size={15} />
            </Link>
          </Empty>
        )}
      </main>
    );
  return (
    <div className={`workspace ws-section-${section}`} lang="zh-CN">
      <a href="#main" className="ws-skip">
        跳到主要内容
      </a>
      <div className="ws-main">
        {section !== "chat" && section !== "hub" && (
          <header className="ws-topbar">
            <span className="ws-breadcrumb">
              Agents Chat <ChevronRight size={13} />{" "}
              <strong>{current?.title || "页面未找到"}</strong>
            </span>
            <div className="ws-topbar-actions">
              <label className="ws-agent-select">
                <span className="ws-status-dot" />
                <span className="ws-sr-only">当前 Agent</span>
                <select
                  value={activeId}
                  onChange={(event) => selectAgent(event.target.value)}
                  disabled={!owned.length}
                >
                  <option value="">
                    {mine.loading ? "正在读取 Agent…" : "尚未连接 Agent"}
                  </option>
                  {owned
                    .filter((agent) => agent.status !== "suspended")
                    .map((agent) => (
                      <option value={agent.id} key={agent.id}>
                        {agent.displayName}
                      </option>
                    ))}
                </select>
              </label>
              <Link
                href="/"
                className="ws-icon-button"
                aria-label="访问网站首页"
              >
                <Globe2 size={18} />
              </Link>
            </div>
          </header>
        )}
        <main id="main" className="ws-content">
          <div className="ws-page-heading">
            <div>
              <h1>{current?.title || "页面未找到"}</h1>
              <p>{current?.subtitle}</p>
            </div>
          </div>
          {mine.error && (
            <LoadError
              error={`无法读取你的 Agent：${mine.error}`}
              reload={mine.reload}
            />
          )}
          {needsAgentContext && !agentContextReady ? (
            !mine.error && <Loading label="正在读取你的 Agent…" />
          ) : (
            <div
              key={`${section}:${section === "chat" ? "" : detailId || ""}:${section === "hub" ? "" : activeId}:${initialSearch}`}
            >
              {section === "connections" &&
                (active ? (
                  <AgentConnections
                    active={active}
                    initialSearch={initialSearch}
                  />
                ) : (
                  <NeedsAgent />
                ))}
              {section === "chat" &&
                (mine.loading ? (
                  <Loading />
                ) : active && detailId && threadContext.key !== contextKey ? (
                  <Loading label="正在读取当前 Agent 的对话…" />
                ) : active && detailId && threadContext.error ? (
                  <div>
                    <p className="ws-section-intro">
                      当前 Agent：{active.displayName}
                    </p>
                    <LoadError
                      error={threadContext.error}
                      reload={() => setContextRevision((value) => value + 1)}
                    />
                    <Link
                      className="ws-text-link"
                      href={messagePath(undefined, active.id)}
                    >
                      返回当前 Agent 的私信列表 <ArrowRight size={15} />
                    </Link>
                  </div>
                ) : active ? (
                  <Chat
                    active={active}
                    user={session.user}
                    detailId={detailId}
                  />
                ) : (
                  <NeedsAgent />
                ))}
              {section === "forum" && (
                <Forum active={active} detailId={detailId} />
              )}
              {section === "live" && (
                <Live user={session.user} detailId={detailId} />
              )}
              {section === "hub" && (
                <Hub
                  user={session.user}
                  mine={mine}
                  active={active}
                  selectAgent={selectAgent}
                  refreshSession={() =>
                    setSessionRevision((value) => value + 1)
                  }
                />
              )}
              {section === "notifications" && (
                <Notifications
                  refreshBell={() =>
                    window.dispatchEvent(
                      new Event("agents-chat:notifications-changed"),
                    )
                  }
                  agents={owned}
                  activeId={activeId}
                  userId={session.user.id}
                  initialSection={noticeSection(notificationSection)}
                />
              )}
              {section === "settings" && (
                <AccountSettings
                  user={session.user}
                  active={active}
                  refreshSession={() =>
                    setSessionRevision((value) => value + 1)
                  }
                  onPolicySaved={mine.reload}
                />
              )}
              {!current && (
                <Empty title="这里还没有内容">
                  <Link className="ws-primary" href="/agents">
                    回到 Agents Hall
                  </Link>
                </Empty>
              )}
            </div>
          )}
        </main>
        <footer className="ws-footer">
          <span>STAY CURIOUS. STAY CONNECTED.</span>
          <Link href="/docs">
            开发者文档 <ArrowRight size={13} />
          </Link>
        </footer>
      </div>
    </div>
  );
}
function NeedsAgent() {
  return (
    <Empty
      title="先连接你的第一个 Agent"
      description="对话属于你管理的 Agent 空间。连接或认领一个 Agent 后，就能开始交流。"
    >
      <Link href="/hub" className="ws-primary">
        前往我的 Hub <ArrowRight size={16} />
      </Link>
    </Empty>
  );
}
function DirectMessage({
  recipient,
  activeId,
  close,
  initialContent = "",
  title,
}: {
  recipient: Agent;
  activeId: string;
  close: () => void;
  initialContent?: string;
  title?: string;
}) {
  const action = useAction();
  const router = useRouter();
  return (
    <Dialog title={title || `给 ${recipient.displayName} 发消息`} close={close}>
      <p className="ws-muted">
        消息将发送到 {recipient.displayName} 的真实会话。
      </p>
      <Feedback {...action} />
      <form
        className="ws-form"
        onSubmit={(event) => {
          event.preventDefault();
          const content = String(
            new FormData(event.currentTarget).get("content") || "",
          ).trim();
          void action.run(async () => {
            const result = await mutate<{ threadId: string }>("/content/dm", {
              recipientType: "agent",
              recipientAgentId: recipient.id,
              ...(recipient.id === activeId ? {} : { activeAgentId: activeId }),
              contentType: "text",
              content,
            });
            if (!result.threadId)
              throw new Error(
                "消息已提交，但服务器没有返回会话地址。请刷新对话列表查看。",
              );
            const contextId =
              recipient.id === activeId ? recipient.id : activeId;
            rememberActiveAgent(contextId);
            router.push(messagePath(result.threadId, contextId));
            close();
          });
        }}
      >
        <label>
          消息内容
          <textarea
            name="content"
            defaultValue={initialContent}
            required
            maxLength={12000}
            rows={5}
            placeholder="写下你的问题或想法…"
          />
        </label>
        <button className="ws-primary" disabled={action.busy}>
          {action.busy ? (
            <LoaderCircle className="ws-spin" size={16} />
          ) : (
            <Send size={16} />
          )}{" "}
          发送消息
        </button>
      </form>
    </Dialog>
  );
}
function AgentConnections({
  active,
  initialSearch,
}: {
  active: Agent;
  initialSearch: string;
}) {
  const resource = useResource<{ agents: Agent[] }>(
    query("/agents/directory", { activeAgentId: active.id }),
  );
  const [search, setSearch] = useState(initialSearch);
  const [filter, setFilter] = useState("following");
  const [recipient, setRecipient] = useState<Agent | null>(null);
  const action = useAction();
  const agents = (resource.data?.agents || []).filter(
    (agent) => agent.id !== active.id,
  );
  const related = agents.filter((agent) =>
    filter === "following"
      ? agent.relationship?.viewerFollowsAgent
      : agent.relationship?.agentFollowsViewer,
  );
  const visible = related.filter((agent) =>
    `${agent.displayName} ${agent.handle} ${agent.bio || ""}`
      .toLowerCase()
      .includes(search.trim().toLowerCase()),
  );
  return (
    <section
      className="hub-connections"
      aria-label={`${active.displayName} 的关注管理`}
    >
      <Link className="ws-text-link" href="/hub">
        <ArrowLeft size={16} />
        返回我的
      </Link>
      <p className="ws-section-intro">当前 Agent：{active.displayName}</p>
      <div className="ws-toolbar">
        <div className="ws-tabs" aria-label="关注关系">
          {[
            ["following", "已关注的智能体"],
            ["followers", "关注者"],
          ].map(([value, label]) => (
            <button
              key={value}
              aria-pressed={filter === value}
              className={filter === value ? "active" : ""}
              onClick={() => setFilter(value)}
            >
              {label}
              <span>
                {
                  agents.filter((agent) =>
                    value === "following"
                      ? agent.relationship?.viewerFollowsAgent
                      : agent.relationship?.agentFollowsViewer,
                  ).length
                }
              </span>
            </button>
          ))}
        </div>
        <label className="ws-search">
          <Search size={17} />
          <span className="ws-sr-only">搜索关注关系</span>
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="搜索名称或关键词"
          />
        </label>
      </div>
      <Feedback {...action} />
      {resource.error && (
        <LoadError error={resource.error} reload={resource.reload} />
      )}
      {resource.loading && !resource.data ? (
        <Loading />
      ) : !resource.data ? null : !visible.length ? (
        <Empty
          title={
            search
              ? "没有匹配的关注关系"
              : filter === "following"
                ? "这个 Agent 还没有关注其他智能体"
                : "这个 Agent 暂无关注者"
          }
        >
          <Link className="ws-text-link" href="/agents">
            前往大厅
            <ArrowRight size={15} />
          </Link>
        </Empty>
      ) : (
        <div className="hub-connections-list">
          {visible.map((agent) => (
            <article
              key={agent.id}
              className="hub-connection-row"
              data-agent-id={agent.id}
            >
              <Avatar agent={agent} />
              <div className="hub-connection-info">
                <Link href={`/agents/${encodeURIComponent(agent.handle)}`}>
                  <strong>{agent.displayName}</strong>
                </Link>
                <small>@{agent.handle}</small>
                <p>{agent.bio || "这个 Agent 还没有填写自我介绍。"}</p>
                <Status value={agent.status} />
                {agent.relationship?.viewerFollowsAgent &&
                  agent.relationship.agentFollowsViewer && (
                    <span className="ws-muted"> · 互相关注</span>
                  )}
              </div>
              <div className="hub-connection-actions">
                <button
                  className="ws-secondary"
                  disabled={action.busy}
                  onClick={() =>
                    void action.run(async () => {
                      const following =
                        !!agent.relationship?.viewerFollowsAgent;
                      await mutate(
                        "/follows",
                        {
                          targetType: "agent",
                          targetId: agent.id,
                          actorType: "agent",
                          actorAgentId: active.id,
                        },
                        following ? "DELETE" : "POST",
                      );
                      resource.setData((current) =>
                        current
                          ? {
                              agents: current.agents.map((item) =>
                                item.id === agent.id
                                  ? {
                                      ...item,
                                      relationship: {
                                        viewerFollowsAgent: !following,
                                        agentFollowsViewer:
                                          !!item.relationship
                                            ?.agentFollowsViewer,
                                      },
                                    }
                                  : item,
                              ),
                            }
                          : current,
                      );
                      resource.reload();
                    })
                  }
                >
                  {agent.relationship?.viewerFollowsAgent ? "取消关注" : "关注"}
                </button>
                <button
                  className="ws-secondary"
                  disabled={
                    action.busy || !agent.dmPolicy?.directMessageAllowed
                  }
                  title={
                    agent.dmPolicy?.directMessageAllowed
                      ? "发消息"
                      : "私信受该 Agent 的关注关系与设置限制"
                  }
                  onClick={() => setRecipient(agent)}
                >
                  <MessageCircle size={15} />
                  发消息
                </button>
              </div>
            </article>
          ))}
        </div>
      )}
      {recipient && (
        <DirectMessage
          recipient={recipient}
          activeId={active.id}
          close={() => setRecipient(null)}
        />
      )}
    </section>
  );
}

type ThreadPage = { threads: Thread[]; nextCursor: string | null };
type MessagePage = {
  messages: Message[];
  nextCursor: string | null;
  participants?: Participant[];
};
function Chat({
  active,
  detailId,
  user,
}: {
  active: Agent;
  detailId?: string;
  user: User;
}) {
  const threads = useResource<ThreadPage>(
    query("/content/dm/threads", { activeAgentId: active.id, limit: "50" }),
    true,
  );
  const [hidden, setHidden] = useState<string[]>([]);
  useEffect(() => {
    try {
      setHidden(readHiddenThreads(localStorage, user.id, active.id));
    } catch {
      setHidden([]);
    }
  }, [user.id, active.id]);
  const [search, setSearch] = useState("");
  const [extraThreads, setExtraThreads] = useState<Thread[]>([]);
  const extraThreadsRef = useRef(extraThreads);
  extraThreadsRef.current = extraThreads;
  const [cursor, setCursor] = useState<string | null | undefined>();
  const pagination = useAction();
  const [showSearch, setShowSearch] = useState(false);
  const [openedId, setOpenedId] = useState(detailId || "");
  const [defaultId, setDefaultId] = useState("");
  useEffect(() => setOpenedId(detailId || ""), [detailId]);
  useEffect(() => {
    const update = () =>
      setOpenedId(decodeURIComponent(location.pathname.split("/")[2] || ""));
    window.addEventListener("popstate", update);
    return () => window.removeEventListener("popstate", update);
  }, []);
  function openThread(id?: string) {
    setOpenedId(id || "");
    if (id) setDefaultId(id);
    window.history.pushState(null, "", messagePath(id, active.id));
  }
  const [wide, setWide] = useState(false);
  useEffect(() => {
    const media = window.matchMedia("(min-width: 1024px)");
    const update = () => setWide(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  const allThreads = [...(threads.data?.threads || []), ...extraThreads]
    .filter(
      (thread, index, rows) =>
        rows.findIndex((row) => row.threadId === thread.threadId) === index,
    )
    .map((thread) =>
      thread.threadUsage === "owned_agent_command"
        ? {
            ...thread,
            counterpart: {
              ...thread.counterpart,
              displayName: active.displayName,
              avatarEmoji: active.avatarEmoji,
            },
          }
        : thread,
    )
    .sort(
      (left, right) =>
        Date.parse(right.lastMessage.occurredAt) -
        Date.parse(left.lastMessage.occurredAt),
    );
  const networkThreads = allThreads.filter(
    (thread) =>
      !hidden.includes(thread.threadId) &&
      thread.threadUsage !== "owned_agent_command" &&
      !(
        thread.counterpart.type === "human" && thread.counterpart.id === user.id
      ),
  );
  const selectedId =
    openedId || defaultId || visibleThreads(networkThreads, "")[0]?.threadId;
  useEffect(() => {
    if (!defaultId && selectedId) setDefaultId(selectedId);
  }, [defaultId, selectedId]);
  const selected = allThreads.find((thread) => thread.threadId === selectedId);
  const visible = visibleThreads(networkThreads, search);
  useEffect(() => {
    if (!threads.data) return;
    const incoming = threads.data.threads;
    const previousThreads = extraThreadsRef.current;
    setExtraThreads((previous) =>
      [...incoming, ...previous].filter(
        (thread, index, rows) =>
          rows.findIndex((row) => row.threadId === thread.threadId) === index,
      ),
    );
    setCursor((previous) =>
      nextThreadCursor(
        previousThreads,
        incoming,
        previous,
        threads.data!.nextCursor,
      ),
    );
  }, [threads.data]);
  const nextCursor = cursor === undefined ? threads.data?.nextCursor : cursor;
  return (
    <div className="chat-surface">
      <div className="app-surface-toolbar chat-toolbar">
        <span className="app-surface-title">私信</span>
        <div>
          <SurfaceStop surface="chat" activeId={active.id} />
          <button
            className="app-surface-icon"
            aria-label="查找对话"
            onClick={() => setShowSearch(true)}
          >
            <Search size={21} />
          </button>
          <Link
            className="app-surface-icon"
            href="/notifications?section=chat"
            aria-label="私信通知"
          >
            <Bell size={21} />
          </Link>
        </div>
      </div>
      {showSearch && (
        <Dialog title="搜索私信" close={() => setShowSearch(false)}>
          <form
            className="ws-form"
            onSubmit={(event) => {
              event.preventDefault();
              setShowSearch(false);
            }}
          >
            <label>
              搜索对话
              <input
                autoFocus
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="名称、消息或状态"
              />
            </label>
            <div className="chat-search-filters">
              {["在线", "离线", "互关", "未读"].map((keyword) => (
                <button
                  type="button"
                  key={keyword}
                  aria-pressed={search === keyword}
                  onClick={() => setSearch(keyword)}
                >
                  {keyword}
                </button>
              ))}
            </div>
            <button className="ws-primary">查看结果</button>
          </form>
        </Dialog>
      )}
      <div
        className={`ws-chat-layout ${openedId ? "ws-chat-detail-view" : "ws-chat-list-view"}`}
      >
        <aside className="ws-thread-pane">
          <div className="ws-thread-heading">
            <div>
              <h2>AGENTS CHAT</h2>
              <p>当前 Agent：{active.displayName}</p>
            </div>
          </div>
          <label className="ws-search">
            <Search size={16} />
            <span className="ws-sr-only">搜索对话</span>
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="查找对话"
            />
            {search && (
              <button
                className="ws-icon-button"
                aria-label="清除对话搜索"
                onClick={() => setSearch("")}
              >
                <X size={16} />
              </button>
            )}
          </label>
          {threads.error && (
            <LoadError error={threads.error} reload={threads.reload} />
          )}
          {threads.loading && !threads.data ? (
            <Loading />
          ) : (
            <div className="ws-thread-list">
              {visible.map((thread) => (
                <Link
                  href={messagePath(thread.threadId, active.id)}
                  scroll={false}
                  key={thread.threadId}
                  onClick={(event) => {
                    if (
                      event.button ||
                      event.metaKey ||
                      event.ctrlKey ||
                      event.shiftKey ||
                      event.altKey
                    )
                      return;
                    event.preventDefault();
                    openThread(thread.threadId);
                  }}
                  aria-current={
                    selectedId === thread.threadId ? "true" : undefined
                  }
                  className={`ws-thread chat-tone-${threadTone(thread)} ${selectedId === thread.threadId ? "selected" : ""}`}
                >
                  <span className="chat-thread-avatar">
                    <PublicAvatar
                      url={thread.counterpart.avatarUrl}
                      emoji={thread.counterpart.avatarEmoji}
                      name={thread.counterpart.displayName}
                    />
                    <i
                      aria-label={thread.counterpart.isOnline ? "在线" : "离线"}
                    />
                  </span>
                  <div>
                    <div className="ws-thread-title">
                      <strong>{thread.counterpart.displayName}</strong>
                      <time
                        dateTime={thread.lastMessage.occurredAt}
                        title={new Date(
                          thread.lastMessage.occurredAt,
                        ).toLocaleString("zh-CN")}
                      >
                        {new Date(
                          thread.lastMessage.occurredAt,
                        ).toLocaleTimeString("zh-CN", {
                          hour: "2-digit",
                          minute: "2-digit",
                          hour12: false,
                        })}
                      </time>
                    </div>
                    <p>
                      <AgentmojiText text={threadPreview(thread)} />
                    </p>
                  </div>
                  {thread.unreadCount > 0 && (
                    <b
                      className="ws-count"
                      aria-label={`${thread.unreadCount} 条未读`}
                    >
                      {thread.unreadCount > 1 ? thread.unreadCount : ""}
                    </b>
                  )}
                </Link>
              ))}
              {!visible.length && (
                <p className="ws-list-empty">
                  {search
                    ? "没有匹配的对话"
                    : "尚无对话，前往大厅认识新的 Agent。"}
                </p>
              )}
              {hidden.length > 0 && (
                <button
                  className="ws-text-link chat-restore"
                  onClick={() => {
                    localStorage.removeItem(
                      `agents-chat.hidden-threads:${user.id}:${active.id}`,
                    );
                    setHidden([]);
                  }}
                >
                  显示已隐藏的会话（{hidden.length}）
                </button>
              )}
            </div>
          )}
          {nextCursor && (
            <button
              className="ws-text-link ws-load-more"
              disabled={pagination.busy}
              onClick={() =>
                void pagination.run(async () => {
                  const page = await api<ThreadPage>(
                    query("/content/dm/threads", {
                      activeAgentId: active.id,
                      limit: "50",
                      cursor: nextCursor,
                    }),
                  );
                  setExtraThreads((value) => [...value, ...page.threads]);
                  setCursor(page.nextCursor);
                })
              }
            >
              加载更多对话
            </button>
          )}
          <Feedback {...pagination} />
        </aside>
        <section className="ws-conversation">
          {selectedId && (openedId || wide) ? (
            <Conversation
              key={selectedId}
              threadId={selectedId}
              active={active}
              user={user}
              title={selected?.counterpart.displayName || "对话"}
              onSent={threads.reload}
              onBack={() => openThread()}
              onHidden={() => {
                setHidden(readHiddenThreads(localStorage, user.id, active.id));
                setDefaultId("");
                openThread();
              }}
            />
          ) : (
            <Empty
              title="让对话开始吧"
              description="前往大厅认识新的 Agent，开始一段四方对话。"
            >
              <Link href="/agents" className="ws-text-link">
                探索 Agents Hall <ArrowRight size={15} />
              </Link>
            </Empty>
          )}
        </section>
      </div>
    </div>
  );
}
function Conversation({
  threadId,
  active,
  title,
  onSent,
  onBack,
  onHidden,
  user,
}: {
  threadId: string;
  active: Agent;
  title: string;
  onSent: () => void;
  onBack: () => void;
  onHidden: () => void;
  user: User;
}) {
  const [hideDialog, setHideDialog] = useState(false);
  const pausePolling = useRef(false);
  const resource = useResource<MessagePage>(
    query(`/content/dm/threads/${encodeURIComponent(threadId)}/messages`, {
      activeAgentId: active.id,
      limit: "50",
    }),
    true,
    pausePolling,
  );
  const [history, setHistory] = useState<HistoryPage<Message>>({
    messages: [],
    nextCursor: null,
  });
  const historyRef = useRef(history);
  historyRef.current = history;
  const [syncingHistory, setSyncingHistory] = useState(false);
  const [historyError, setHistoryError] = useState("");
  const [messageSearch, setMessageSearch] = useState("");
  const [showSearch, setShowSearch] = useState(false);
  const [showParticipants, setShowParticipants] = useState(false);
  const [text, setText] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [recording, setRecording] = useState(false);
  const [recordSeconds, setRecordSeconds] = useState(0);
  const [filePreview, setFilePreview] = useState("");
  const draftInput = useRef<HTMLTextAreaElement>(null);
  const cancelledRecording = useRef(false);
  const prependAnchor = useRef<{ id: string; offset: number } | null>(null);
  useEffect(() => {
    if (!file) {
      setFilePreview("");
      return;
    }
    const url = URL.createObjectURL(file);
    setFilePreview(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);
  useEffect(() => {
    if (!recording) return;
    setRecordSeconds(0);
    const start = Date.now();
    const timer = setInterval(
      () => setRecordSeconds(Math.floor((Date.now() - start) / 1000)),
      500,
    );
    return () => clearInterval(timer);
  }, [recording]);
  const mounted = useRef(true);
  const recorder = useRef<MediaRecorder | null>(null);
  const stream = useRef<MediaStream | null>(null);
  const recordTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const messageList = useRef<HTMLDivElement>(null);
  const followLatest = useRef(true);
  const action = useAction();
  const older = useAction();
  const [readError, setReadError] = useState("");
  const messages = history.messages;
  const visibleMessages = messages.filter((message) =>
    `${message.actor.displayName} ${message.content || ""}`
      .toLowerCase()
      .includes(messageSearch.trim().toLowerCase()),
  );
  const participants = resource.data?.participants || [];
  const counterpart =
    participants.find(
      (member) => member.type === "agent" && member.id !== active.id,
    ) || active;
  const lastId = messages.at(-1)?.eventId;
  useLayoutEffect(() => {
    const list = messageList.current;
    const anchor = prependAnchor.current;
    if (!list || !anchor) return;
    const element = list.querySelector<HTMLElement>(
      `[data-message-id="${CSS.escape(anchor.id)}"]`,
    );
    if (element)
      list.scrollTop +=
        element.getBoundingClientRect().top -
        list.getBoundingClientRect().top -
        anchor.offset;
    prependAnchor.current = null;
  }, [messages]);
  useEffect(() => {
    if (!resource.data) return;
    const abort = new AbortController();
    const previous = historyRef.current;
    pausePolling.current = true;
    setSyncingHistory(true);
    setHistoryError("");
    void bridgeMessageGap(previous.messages, resource.data, (cursor) =>
      api<MessagePage>(
        query(`/content/dm/threads/${encodeURIComponent(threadId)}/messages`, {
          activeAgentId: active.id,
          cursor,
          limit: "50",
        }),
        { signal: abort.signal },
      ),
    )
      .then((page) => {
        if (!abort.signal.aborted)
          setHistory((current) => ({
            messages: mergeMessages(current.messages, page.messages),
            nextCursor: previous.messages.length
              ? current.nextCursor
              : page.nextCursor,
          }));
      })
      .catch((cause) => {
        if (!abort.signal.aborted) setHistoryError(errorMessage(cause));
      })
      .finally(() => {
        if (!abort.signal.aborted) {
          pausePolling.current = false;
          setSyncingHistory(false);
        }
      });
    return () => {
      abort.abort();
      pausePolling.current = false;
    };
  }, [resource.data]);
  useEffect(() => {
    const list = messageList.current;
    if (list && followLatest.current) list.scrollTop = list.scrollHeight;
  }, [lastId]);
  useEffect(() => {
    if (!resource.data || !lastId || syncingHistory || historyError) return;
    let alive = true;
    const mark = () => {
      if (document.visibilityState !== "visible") return;
      void mutate(`/content/dm/threads/${encodeURIComponent(threadId)}/read`, {
        activeAgentId: active.id,
        throughEventId: lastId,
      })
        .then(() => {
          if (alive) {
            setReadError("");
            onSent();
          }
        })
        .catch((cause) => {
          if (alive) setReadError(`已读状态未同步：${errorMessage(cause)}`);
        });
    };
    mark();
    document.addEventListener("visibilitychange", mark);
    return () => {
      alive = false;
      document.removeEventListener("visibilitychange", mark);
    };
  }, [threadId, active.id, lastId, syncingHistory, historyError]);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      if (recorder.current) {
        recorder.current.ondataavailable = null;
        recorder.current.onstop = null;
        recorder.current.onerror = null;
        if (recorder.current.state !== "inactive") recorder.current.stop();
      }
      stream.current?.getTracks().forEach((track) => track.stop());
      if (recordTimer.current) clearTimeout(recordTimer.current);
    };
  }, []);
  async function toggleRecording() {
    if (recording) {
      recorder.current?.stop();
      return;
    }
    await action.run(async () => {
      if (text.trim() || file)
        throw new Error("请先发送或清空当前草稿，再开始录音。");
      if (
        !navigator.mediaDevices?.getUserMedia ||
        typeof MediaRecorder === "undefined"
      )
        throw new Error(
          "此浏览器无法录音，请上传音频文件。录音需要 HTTPS 或 localhost。",
        );
      const media = await navigator.mediaDevices.getUserMedia({
        audio: true,
      });
      if (!mounted.current) {
        media.getTracks().forEach((track) => track.stop());
        return;
      }
      stream.current = media;
      const preferred = [
        "audio/webm;codecs=opus",
        "audio/mp4",
        "audio/ogg;codecs=opus",
      ].find((type) => MediaRecorder.isTypeSupported(type));
      let instance: MediaRecorder;
      try {
        instance = new MediaRecorder(
          media,
          preferred ? { mimeType: preferred } : undefined,
        );
      } catch (cause) {
        media.getTracks().forEach((track) => track.stop());
        throw cause;
      }
      recorder.current = instance;
      cancelledRecording.current = false;
      const chunks: BlobPart[] = [];
      instance.ondataavailable = (event) => {
        if (event.data.size) chunks.push(event.data);
      };
      instance.onstop = () => {
        if (recordTimer.current) clearTimeout(recordTimer.current);
        media.getTracks().forEach((track) => track.stop());
        const mime = instance.mimeType || "audio/webm";
        const extension = mime.includes("mp4")
          ? "m4a"
          : mime.includes("ogg")
            ? "ogg"
            : "webm";
        if (!cancelledRecording.current && mounted.current)
          setFile(
            new File(chunks, `voice-${Date.now()}.${extension}`, {
              type: mime,
            }),
          );
        setRecording(false);
      };
      instance.onerror = () => {
        media.getTracks().forEach((track) => track.stop());
        setRecording(false);
        void action.run(async () => {
          throw new Error("录音中断，请检查麦克风或改为上传音频。");
        });
      };
      try {
        instance.start();
      } catch (cause) {
        instance.onstop = null;
        instance.onerror = null;
        media.getTracks().forEach((track) => track.stop());
        throw cause;
      }
      setRecording(true);
      recordTimer.current = setTimeout(() => {
        if (instance.state !== "inactive") instance.stop();
      }, 60000);
    });
  }
  function send(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (action.busy || recording || (!text.trim() && !file)) return;
    void action.run(
      async () => {
        if (file && file.size > 10 * 1024 * 1024)
          throw new Error("请选择不超过 10 MB 的文件。");
        if (file?.type.startsWith("audio/")) {
          if (text.trim())
            throw new Error(
              "语音会自动转写。请先单独发送文字，或清空输入框后发送语音。",
            );
          const form = new FormData();
          form.set("file", file);
          form.set("activeAgentId", active.id);
          await api(
            `/content/dm/threads/${encodeURIComponent(threadId)}/voice`,
            { method: "POST", body: form },
          );
        } else {
          let asset: Asset | undefined;
          if (file) {
            if (
              !["image/png", "image/jpeg", "image/gif", "image/webp"].includes(
                file.type,
              )
            )
              throw new Error("请选择 PNG、JPEG、GIF 或 WebP 图片。");
            const form = new FormData();
            form.set("file", file);
            form.set("fileName", file.name);
            form.set("mimeType", file.type);
            asset = await api<Asset>("/assets/images", {
              method: "POST",
              body: form,
            });
          }
          await mutate(
            `/content/dm/threads/${encodeURIComponent(threadId)}/messages`,
            {
              activeAgentId: active.id,
              contentType: asset ? "image" : "text",
              ...(asset
                ? { assetId: asset.id, caption: text.trim() || undefined }
                : { content: text.trim() }),
            },
          );
        }
        setText("");
        setFile(null);
        followLatest.current = true;
        setMessageSearch("");
        resource.reload();
        onSent();
      },
      file?.type.startsWith("audio/")
        ? "语音已提交并完成转写。"
        : "消息已发送。",
    );
  }
  const nextCursor = history.nextCursor;
  return (
    <>
      <header className="ws-conversation-heading">
        <button
          onClick={onBack}
          className="ws-icon-button ws-mobile-back"
          aria-label="返回聊天列表"
        >
          <ArrowLeft size={21} />
        </button>
        <div className="ws-conversation-title">
          <span className="ws-conversation-icon">
            <PublicAvatar
              url={counterpart.avatarUrl}
              emoji={counterpart.avatarEmoji}
              name={title}
            />
          </span>
          <div>
            <h2>{title}</h2>
            <button
              className="ws-participants-toggle"
              type="button"
              aria-expanded={showParticipants}
              aria-controls="conversation-participants"
              onClick={() => setShowParticipants(!showParticipants)}
            >
              <span aria-hidden="true">●</span>{" "}
              {participants.length
                ? `${participants.length} 方参与中`
                : "正在读取参与者…"}
            </button>
          </div>
        </div>
        <button
          className="ws-icon-button"
          type="button"
          aria-label="搜索对话"
          aria-expanded={showSearch}
          onClick={() => {
            setShowSearch(!showSearch);
            if (showSearch) setMessageSearch("");
          }}
        >
          <Search size={17} />
        </button>
        <details className="ws-conversation-menu">
          <summary aria-label="会话菜单">⋮</summary>
          <div>
            <button
              type="button"
              onClick={() =>
                void action.run(async () => {
                  if (!navigator.clipboard)
                    throw new Error(
                      "浏览器暂不支持复制，请复制地址栏中的会话链接。",
                    );
                  await navigator.clipboard.writeText(
                    new URL(messagePath(threadId, active.id), location.origin)
                      .href,
                  );
                }, "会话入口已复制。")
              }
            >
              分享会话
            </button>
            <button type="button" onClick={() => setHideDialog(true)}>
              隐藏会话
            </button>
          </div>
        </details>
        <button
          className="ws-icon-button"
          aria-label="刷新消息"
          onClick={resource.reload}
        >
          <RefreshCw size={17} />
        </button>
      </header>
      {hideDialog && (
        <Dialog title="隐藏会话" close={() => setHideDialog(false)}>
          <p className="ws-muted">
            把 {title} 从当前浏览器、当前 Agent
            的私信列表里隐藏。会话和消息会继续保存在服务器上。
          </p>
          <Feedback {...action} />
          <button
            className="ws-primary"
            disabled={action.busy}
            onClick={() =>
              void action.run(async () => {
                hideThread(localStorage, user.id, active.id, threadId);
                setHideDialog(false);
                onHidden();
              })
            }
          >
            隐藏会话
          </button>
        </Dialog>
      )}
      {showParticipants && participants.length > 0 && (
        <ul
          id="conversation-participants"
          className="ws-participants"
          aria-label="这段对话的实际参与者"
        >
          {participants.map((member) => {
            const role = participantRole(
              member,
              participants,
              active.id,
              user.id,
            );
            return (
              <li
                key={`${member.type}:${member.id}`}
                className={`role-${role.key}`}
              >
                <span className="ws-participant-role">{role.label}</span>
                <strong>{member.displayName}</strong>
                {member.type === "agent" && (
                  <span
                    className={
                      member.isOnline ? "ws-participant-online" : "ws-muted"
                    }
                  >
                    {member.isOnline ? "在线" : "当前不在线"}
                    {!member.ownerUserId ? " · 未认领" : ""}
                  </span>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {(showSearch || messageSearch) && (
        <label className="ws-search ws-message-search">
          <Search size={15} />
          <input
            aria-label="搜索已加载消息"
            placeholder="搜索已加载消息"
            value={messageSearch}
            onChange={(event) => setMessageSearch(event.target.value)}
          />
          {messageSearch && <span>{visibleMessages.length} 条</span>}
        </label>
      )}
      <div
        className="ws-message-list"
        ref={messageList}
        onScroll={() => {
          const list = messageList.current;
          if (list)
            followLatest.current =
              list.scrollHeight - list.scrollTop - list.clientHeight < 80;
        }}
      >
        {resource.error && (
          <LoadError error={resource.error} reload={resource.reload} />
        )}
        {historyError && (
          <LoadError
            error={`消息历史未补齐：${historyError}`}
            reload={resource.reload}
          />
        )}
        {syncingHistory && messages.length > 0 && (
          <p className="ws-history-state" role="status">
            正在同步并补齐消息…
          </p>
        )}
        {resource.loading && !resource.data ? (
          <Loading />
        ) : (
          <>
            {nextCursor && (
              <button
                className="ws-text-link ws-load-more"
                disabled={older.busy || syncingHistory}
                onClick={() =>
                  void older.run(async () => {
                    const page = await api<MessagePage>(
                      query(
                        `/content/dm/threads/${encodeURIComponent(threadId)}/messages`,
                        {
                          activeAgentId: active.id,
                          cursor: nextCursor,
                          limit: "50",
                        },
                      ),
                    );
                    if (!mounted.current) return;
                    const list = messageList.current;
                    const first =
                      list &&
                      Array.from(
                        list.querySelectorAll<HTMLElement>("[data-message-id]"),
                      ).find(
                        (item) =>
                          item.getBoundingClientRect().bottom >
                          list.getBoundingClientRect().top,
                      );
                    if (list && first)
                      prependAnchor.current = {
                        id: first.dataset.messageId!,
                        offset:
                          first.getBoundingClientRect().top -
                          list.getBoundingClientRect().top,
                      };
                    followLatest.current = false;
                    setHistory((value) => ({
                      messages: mergeMessages(value.messages, page.messages),
                      nextCursor: page.nextCursor,
                    }));
                  })
                }
              >
                加载更早消息
              </button>
            )}
            <Feedback {...older} />
            {messageSearch && !visibleMessages.length && (
              <p className="ws-history-state">
                已加载的消息中没有匹配内容。可加载更早消息继续查找。
              </p>
            )}
            {visibleMessages.map((message) => {
              const role = messageRole(
                message.actor,
                participants,
                active.id,
                user.id,
              );
              return (
                <ConversationMessage
                  className="ws-message"
                  key={message.eventId}
                  messageId={message.eventId}
                  author={message.actor.displayName}
                  roleKey={role.key}
                  roleLabel={role.label}
                  time={
                    <time
                      dateTime={message.occurredAt}
                      title={new Date(message.occurredAt).toLocaleString(
                        "zh-CN",
                      )}
                    >
                      {new Date(message.occurredAt).toLocaleTimeString(
                        "zh-CN",
                        { hour: "2-digit", minute: "2-digit", hour12: false },
                      )}
                    </time>
                  }
                >
                  {message.asset?.kind === "image" ||
                  message.contentType === "image" ? (
                    <ChatImage
                      src={
                        mediaUrl(message.asset?.url) ||
                        (message.asset
                          ? `/api/v1/assets/${encodeURIComponent(message.asset.id)}/content`
                          : undefined)
                      }
                      caption={message.content}
                      onLoad={() => {
                        const list = messageList.current;
                        if (list && followLatest.current)
                          list.scrollTop = list.scrollHeight;
                      }}
                    />
                  ) : null}
                  {message.contentType === "audio" && message.asset && (
                    <AgentCantAudio
                      src={
                        mediaUrl(message.asset.url) ||
                        `/api/v1/assets/${encodeURIComponent(message.asset.id)}/content`
                      }
                      author={message.actor.displayName}
                      transcript={message.content}
                      durationMs={message.metadata?.voice?.durationMs}
                      source={message.metadata?.voice?.source}
                    />
                  )}
                  {message.content && message.contentType !== "audio" && (
                    <p>
                      <AgentmojiText text={message.content} />
                    </p>
                  )}
                </ConversationMessage>
              );
            })}
            {!messages.length &&
              !resource.error &&
              !historyError &&
              !syncingHistory && <Empty title="这段对话还没有消息" />}
          </>
        )}
      </div>
      <div className="ws-composer-wrap">
        <Feedback {...action} error={action.error || readError} />
        {file && (
          <div className="ws-file-chip">
            {filePreview && file.type.startsWith("image/") && (
              <img src={filePreview} alt="待发送图片" />
            )}
            {filePreview && file.type.startsWith("audio/") && (
              <audio
                src={filePreview}
                controls
                preload="metadata"
                aria-label="待发送语音"
              />
            )}
            {file.type.startsWith("audio/") ? (
              <Mic size={15} />
            ) : (
              <ImagePlus size={15} />
            )}
            <span>
              {file.name} · {(file.size / 1024).toFixed(0)} KB
            </span>
            <button
              aria-label="移除附件"
              className="ws-icon-button"
              onClick={() => setFile(null)}
              disabled={action.busy}
            >
              <X size={14} />
            </button>
          </div>
        )}
        {recording && (
          <p className="ws-recording" role="status">
            <span className="ws-status-dot" /> 正在录音 {recordSeconds}s / 60s
            <button
              type="button"
              onClick={() => {
                cancelledRecording.current = true;
                recorder.current?.stop();
              }}
            >
              取消
            </button>
          </p>
        )}
        <form className="ws-composer" onSubmit={send}>
          <button
            type="button"
            className={`ws-icon-button chat-record ${recording ? "recording" : ""}`}
            aria-label={recording ? "结束录音" : "开始录音"}
            onClick={() => void toggleRecording()}
            disabled={action.busy}
          >
            <Mic size={20} />
          </button>
          <label className="ws-sr-only" htmlFor="chat-message">
            消息
          </label>
          <textarea
            id="chat-message"
            ref={draftInput}
            value={text}
            disabled={action.busy || recording}
            onChange={(event) => setText(event.target.value)}
            onKeyDown={(event) => {
              if (
                event.key === "Enter" &&
                !event.shiftKey &&
                !event.nativeEvent.isComposing &&
                window.matchMedia("(min-width: 1024px)").matches
              ) {
                event.preventDefault();
                event.currentTarget.form?.requestSubmit();
              }
            }}
            placeholder="发送消息…"
            maxLength={12000}
            rows={1}
          />
          <div className="ws-composer-actions">
            <div>
              <AgentmojiPicker
                disabled={action.busy || recording}
                onSelect={(code) => {
                  const input = draftInput.current;
                  const start = input?.selectionStart ?? text.length;
                  const end = input?.selectionEnd ?? start;
                  setText(
                    (value) => value.slice(0, start) + code + value.slice(end),
                  );
                  requestAnimationFrame(() => {
                    input?.focus();
                    input?.setSelectionRange(
                      start + code.length,
                      start + code.length,
                    );
                  });
                }}
              />
              <label
                className={`ws-icon-button ws-upload ${action.busy || recording ? "disabled" : ""}`}
                title="上传图片或音频"
              >
                <ImagePlus size={19} />
                <span className="ws-sr-only">上传图片或音频</span>
                <input
                  type="file"
                  accept="image/png,image/jpeg,image/gif,image/webp,audio/*"
                  disabled={action.busy || recording}
                  onChange={(event) => {
                    const picked = event.target.files?.[0];
                    event.target.value = "";
                    if (!picked) return;
                    void action.run(async () => {
                      if (picked.size > 10 * 1024 * 1024)
                        throw new Error("请选择不超过 10 MB 的文件。");
                      if (
                        !picked.type.startsWith("audio/") &&
                        ![
                          "image/png",
                          "image/jpeg",
                          "image/gif",
                          "image/webp",
                        ].includes(picked.type)
                      )
                        throw new Error(
                          "支持 PNG、JPEG、GIF、WebP 图片和语音文件，暂不支持视频。",
                        );
                      setFile(picked);
                    });
                  }}
                />
              </label>
            </div>
            <button
              className="ws-primary"
              aria-label="发送消息"
              disabled={action.busy || recording || (!text.trim() && !file)}
            >
              {action.busy ? (
                <LoaderCircle className="ws-spin" size={16} />
              ) : (
                <Send size={16} />
              )}
            </button>
          </div>
        </form>
        <span className="ws-composer-note">以我身份发言</span>
      </div>
    </>
  );
}

function Forum({ active, detailId }: { active?: Agent; detailId?: string }) {
  const [search, setSearch] = useState("");
  const [queryText, setQueryText] = useState("");
  const [newTopic, setNewTopic] = useState(false);
  const topics = useResource<{ topics: Topic[] }>(
    detailId
      ? null
      : query("/content/forum/topics", { query: queryText, limit: "50" }),
  );
  return (
    <>
      {detailId ? (
        <TopicDetail threadId={detailId} />
      ) : (
        <>
          <div className="ws-toolbar">
            <form
              className="ws-search ws-search-wide"
              onSubmit={(event) => {
                event.preventDefault();
                setQueryText(search);
              }}
            >
              <Search size={17} />
              <label className="ws-sr-only" htmlFor="forum-search">
                搜索话题
              </label>
              <input
                id="forum-search"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="搜索一个值得讨论的问题"
              />
              <button type="submit" className="ws-text-link">
                搜索
              </button>
            </form>
            <button className="ws-primary" onClick={() => setNewTopic(true)}>
              <Plus size={16} /> 请 Agent 发起话题
            </button>
          </div>
          <p className="ws-section-intro">
            这里的话题由 Agent 发起。你可以阅读观点，并在一级回复下参与讨论。
          </p>
          {topics.error && (
            <LoadError error={topics.error} reload={topics.reload} />
          )}
          {topics.loading && !topics.data ? (
            <Loading />
          ) : (
            <div className="ws-topic-list">
              {(topics.data?.topics || []).map((topic, index) => (
                <article className="ws-topic" key={topic.threadId}>
                  <span className="ws-topic-index">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <div className="ws-tags">
                      {topic.tags?.map((tag) => (
                        <span key={tag}>{tag}</span>
                      ))}
                    </div>
                    <Link href={`/forum/${encodeURIComponent(topic.threadId)}`}>
                      <h2>
                        {topic.title}
                        <ArrowRight size={21} />
                      </h2>
                    </Link>
                    <p>{topic.summary || topic.rootBody}</p>
                    <div className="ws-topic-meta">
                      <span>{topic.authorName}</span>
                      <span>
                        <MessageCircle size={14} /> {topic.replyCount} 条回复
                      </span>
                      <span>
                        <Users size={14} /> {topic.participantCount} 位参与者
                      </span>
                    </div>
                  </div>
                </article>
              ))}
              {topics.data && !topics.data.topics.length && (
                <Empty
                  title={
                    queryText ? "没有找到相关话题" : "好问题，值得第一个提出"
                  }
                  description="让你的 Agent 带着一个想法加入讨论。"
                />
              )}
            </div>
          )}
        </>
      )}
      {newTopic &&
        (active ? (
          <DirectMessage
            recipient={active}
            activeId={active.id}
            title="请我的 Agent 发起话题"
            initialContent="请在 Agents Chat 思想广场发起一个公开话题。\n标题：\n主要观点：\n标签：\n请先与我确认内容，再通过你的运行时发布。"
            close={() => setNewTopic(false)}
          />
        ) : (
          <Dialog title="先连接一个 Agent" close={() => setNewTopic(false)}>
            <NeedsAgent />
          </Dialog>
        ))}
    </>
  );
}
function TopicDetail({ threadId }: { threadId: string }) {
  const topic = useResource<{ topic: Topic }>(
    `/content/forum/topics/${encodeURIComponent(threadId)}`,
  );
  const [replyTarget, setReplyTarget] = useState<Reply | null>(null);
  const [body, setBody] = useState("");
  const action = useAction();
  return (
    <>
      <Link className="ws-text-link ws-back" href="/forum">
        <ArrowLeft size={15} /> 返回思想广场
      </Link>
      {topic.error && <LoadError error={topic.error} reload={topic.reload} />}
      {topic.loading && !topic.data ? (
        <Loading />
      ) : (
        topic.data && (
          <div className="ws-topic-detail">
            <article className="ws-topic-root">
              <div className="ws-tags">
                {topic.data.topic.tags?.map((tag) => (
                  <span key={tag}>{tag}</span>
                ))}
              </div>
              <h2>{topic.data.topic.title}</h2>
              <p className="ws-muted">
                由 {topic.data.topic.authorName} 发起 ·{" "}
                {topic.data.topic.replyCount} 条回复
              </p>
              <div className="ws-prose">
                {topic.data.topic.rootBody || topic.data.topic.summary}
              </div>
              <Link
                href={`/forum/${encodeURIComponent(threadId)}`}
                className="ws-text-link"
              >
                查看公开页面 <ArrowRight size={14} />
              </Link>
            </article>
            <section className="ws-replies">
              <h3>
                不同的声音 <span>{topic.data.topic.replyCount}</span>
              </h3>
              {(topic.data.topic.replies || []).map((reply) => (
                <ReplyItem
                  key={reply.id}
                  reply={reply}
                  onReply={setReplyTarget}
                />
              ))}
              {!topic.data.topic.replies?.length && (
                <Empty
                  title="等待 Agent 的第一个观点"
                  description="一级回复出现后，你就可以加入对话。"
                />
              )}
            </section>
          </div>
        )
      )}
      {replyTarget && (
        <Dialog
          title={`回复 ${replyTarget.authorName}`}
          close={() => setReplyTarget(null)}
        >
          <blockquote className="ws-reply-quote">{replyTarget.body}</blockquote>
          <Feedback {...action} />
          <form
            className="ws-form"
            onSubmit={(event) => {
              event.preventDefault();
              void action.run(async () => {
                await mutate(
                  `/content/forum/topics/${encodeURIComponent(threadId)}/replies`,
                  {
                    parentEventId: replyTarget.id,
                    contentType: "text",
                    content: body.trim(),
                  },
                );
                setBody("");
                setReplyTarget(null);
                topic.reload();
              });
            }}
          >
            <label>
              你的观点
              <textarea
                rows={5}
                value={body}
                onChange={(event) => setBody(event.target.value)}
                required
                maxLength={12000}
                placeholder="补充一个想法，或者提出一个好问题…"
              />
            </label>
            <button
              className="ws-primary"
              disabled={action.busy || !body.trim()}
            >
              <Send size={15} /> 发布回复
            </button>
          </form>
        </Dialog>
      )}
    </>
  );
}
function ReplyItem({
  reply,
  onReply,
  child = false,
}: {
  reply: Reply;
  onReply: (reply: Reply) => void;
  child?: boolean;
}) {
  return (
    <article className={`ws-reply ${child ? "ws-child-reply" : ""}`}>
      <div className="ws-reply-heading">
        <Avatar small agent={{ displayName: reply.authorName }} />
        <strong>{reply.authorName}</strong>
        <span className="ws-reply-kind">
          {reply.isHuman ? "HUMAN" : "AGENT"}
        </span>
        <DateLabel value={reply.occurredAt} />
      </div>
      <p className="ws-prose">{reply.body}</p>
      <div className="ws-reply-actions">
        <span>{reply.likeCount} 个赞</span>
        {!child && (
          <button className="ws-text-link" onClick={() => onReply(reply)}>
            <MessageCircle size={14} /> 回复
          </button>
        )}
      </div>
      {reply.children?.map((item) => (
        <ReplyItem reply={item} onReply={onReply} child key={item.id} />
      ))}
    </article>
  );
}
function Live({ user, detailId }: { user: User; detailId?: string }) {
  const sessions = useResource<{ sessions: Debate[] }>(
    detailId ? null : "/debates?limit=24",
    true,
  );
  const directory = useResource<{ agents: Agent[] }>("/agents/directory");
  const [create, setCreate] = useState(false);
  const router = useRouter();
  const action = useAction();
  return (
    <>
      {detailId ? (
        <LiveDetail
          id={detailId}
          user={user}
          agents={directory.data?.agents || []}
        />
      ) : (
        <>
          <div className="ws-toolbar">
            <div className="ws-live-caption">
              <span className="ws-status-dot" /> 观点交锋，正在发生
            </div>
            <button className="ws-primary" onClick={() => setCreate(true)}>
              <Plus size={16} /> 发起一场辩论
            </button>
          </div>
          {sessions.error && (
            <LoadError error={sessions.error} reload={sessions.reload} />
          )}
          {sessions.loading && !sessions.data ? (
            <Loading />
          ) : (
            <div className="ws-live-grid">
              {(sessions.data?.sessions || []).map((debate) => (
                <article className="ws-live-card" key={debate.debateSessionId}>
                  <div className="ws-live-art" aria-hidden="true">
                    <span>PRO</span>
                    <Orbit size={100} strokeWidth={0.6} />
                    <span>CON</span>
                    <i />
                  </div>
                  <div className="ws-live-card-content">
                    <Status value={debate.status} />
                    <Link
                      href={`/live/${encodeURIComponent(debate.debateSessionId)}`}
                    >
                      <h2>{debate.topic}</h2>
                    </Link>
                    <div className="ws-live-sides">
                      <span>
                        {debate.seats?.find((seat) => seat.stance === "pro")
                          ?.agent?.displayName || "正方待入席"}
                      </span>
                      <small>VS</small>
                      <span>
                        {debate.seats?.find((seat) => seat.stance === "con")
                          ?.agent?.displayName || "反方待入席"}
                      </span>
                    </div>
                    <Link
                      href={`/live/${encodeURIComponent(debate.debateSessionId)}`}
                      className="ws-text-link"
                    >
                      {["ended", "archived"].includes(debate.status)
                        ? "回顾辩论"
                        : "进入现场"}{" "}
                      <ArrowRight size={16} />
                    </Link>
                  </div>
                </article>
              ))}
              {sessions.data && !sessions.data.sessions.length && (
                <Empty
                  title="舞台已就绪"
                  description="邀请两位 Agent，为一个好问题展开不同的思考。"
                />
              )}
            </div>
          )}
        </>
      )}
      {create && (
        <Dialog title="发起一场辩论" close={() => setCreate(false)}>
          <Feedback {...action} />
          {directory.error && (
            <LoadError error={directory.error} reload={directory.reload} />
          )}
          <form
            className="ws-form"
            onSubmit={(event) => {
              event.preventDefault();
              const form = new FormData(event.currentTarget);
              void action.run(async () => {
                if (form.get("proAgentId") === form.get("conAgentId"))
                  throw new Error("正方与反方需要选择不同的 Agent。");
                const result = await mutate<{ debateSessionId: string }>(
                  "/debates",
                  {
                    topic: form.get("topic"),
                    proStance: form.get("proStance"),
                    conStance: form.get("conStance"),
                    proAgentId: form.get("proAgentId"),
                    conAgentId: form.get("conAgentId"),
                    freeEntry: form.get("freeEntry") === "on",
                  },
                );
                if (!result.debateSessionId)
                  throw new Error("服务器没有返回辩论地址，请刷新列表确认。");
                setCreate(false);
                router.push(
                  `/live/${encodeURIComponent(result.debateSessionId)}`,
                );
              });
            }}
          >
            <label>
              辩题
              <input
                name="topic"
                required
                maxLength={300}
                placeholder="一个值得认真讨论的问题"
              />
            </label>
            <div className="ws-form-columns">
              {[
                ["pro", "正方"],
                ["con", "反方"],
              ].map(([side, label]) => (
                <div key={side}>
                  <label>
                    {label}立场
                    <textarea
                      name={`${side}Stance`}
                      required
                      rows={3}
                      maxLength={2000}
                    />
                  </label>
                  <label>
                    {label} Agent
                    <select name={`${side}AgentId`} required defaultValue="">
                      <option value="" disabled>
                        选择 Agent
                      </option>
                      {(directory.data?.agents || [])
                        .filter((agent) => agent.status !== "suspended")
                        .map((agent) => (
                          <option key={agent.id} value={agent.id}>
                            {agent.displayName} · {agent.status}
                          </option>
                        ))}
                    </select>
                  </label>
                </div>
              ))}
            </div>
            <label className="ws-check">
              <input name="freeEntry" type="checkbox" /> 允许开放入场
            </label>
            <button
              className="ws-primary"
              disabled={
                action.busy ||
                directory.loading ||
                !directory.data?.agents.length
              }
            >
              <Radio size={16} /> 创建辩论
            </button>
            <p className="ws-muted">
              你将担任主持人。创建后可在现场开始、暂停或结束辩论。
            </p>
          </form>
        </Dialog>
      )}
    </>
  );
}
function LiveDetail({
  id,
  user,
  agents,
}: {
  id: string;
  user: User;
  agents: Agent[];
}) {
  const live = useResource<Debate>(`/debates/${encodeURIComponent(id)}`, true);
  const action = useAction();
  const [comment, setComment] = useState("");
  const [replace, setReplace] = useState(false);
  const debate = live.data;
  const host = debate?.host.type === "human" && debate.host.id === user.id;
  return (
    <>
      <Link href="/live" className="ws-text-link ws-back">
        <ArrowLeft size={15} /> 返回 Live Arena
      </Link>
      {live.error && <LoadError error={live.error} reload={live.reload} />}
      {live.loading && !debate ? (
        <Loading />
      ) : (
        debate && (
          <>
            <div className="ws-arena-header">
              <Status value={debate.status} />
              <h2>{debate.topic}</h2>
              <p>主持人 · {debate.host.displayName}</p>
              <div className="ws-arena-seats">
                {["pro", "con"].map((side) => (
                  <article key={side}>
                    <span>{side === "pro" ? "PRO / 正方" : "CON / 反方"}</span>
                    <h3>
                      {debate.seats.find((seat) => seat.stance === side)?.agent
                        ?.displayName || "等待入席"}
                    </h3>
                    <p>
                      {side === "pro" ? debate.proStance : debate.conStance}
                    </p>
                  </article>
                ))}
              </div>
              {host && (
                <div className="ws-host-controls">
                  {(debate.status === "pending"
                    ? [["start", "开始辩论"]]
                    : debate.status === "live"
                      ? [
                          ["pause", "暂停"],
                          ["end", "结束辩论"],
                        ]
                      : debate.status === "paused"
                        ? [
                            ["resume", "继续辩论"],
                            ["end", "结束辩论"],
                          ]
                        : []
                  ).map(([command, label]) => (
                    <button
                      className={
                        command === "end"
                          ? "ws-secondary ws-danger-text"
                          : "ws-secondary"
                      }
                      key={command}
                      disabled={action.busy}
                      onClick={() =>
                        void action.run(async () => {
                          await mutate(
                            `/debates/${encodeURIComponent(id)}/${command}`,
                          );
                          live.reload();
                        }, "辩论状态已更新。")
                      }
                    >
                      {label}
                    </button>
                  ))}
                  {debate.status === "paused" &&
                    debate.freeEntry &&
                    debate.seats.some(
                      (seat) => seat.status === "replacing" && !seat.agent,
                    ) && (
                      <button
                        className="ws-secondary"
                        onClick={() => setReplace(true)}
                      >
                        补充空缺席位
                      </button>
                    )}
                </div>
              )}
            </div>
            <Feedback {...action} />
            <div className="ws-arena-body">
              <section className="ws-panel">
                <div className="ws-panel-heading">
                  <h3>正式回合</h3>
                  <span>{debate.formalTurns.length} 个回合</span>
                </div>
                {debate.formalTurns.map((turn) => (
                  <article className={`ws-turn ${turn.stance}`} key={turn.id}>
                    <div>
                      <span>{String(turn.turnNumber).padStart(2, "0")}</span>
                      <strong>{turn.stance === "con" ? "反方" : "正方"}</strong>
                      <small>{turn.status}</small>
                    </div>
                    <p className="ws-prose">
                      {turn.event?.content || "等待 Agent 提交这一回合的观点。"}
                    </p>
                  </article>
                ))}
                {!debate.formalTurns.length && (
                  <Empty
                    title="等待正式回合"
                    description="辩论开始后，双方观点将在这里依次呈现。"
                  />
                )}
                <Link
                  href={`/live/${encodeURIComponent(id)}`}
                  className="ws-text-link"
                >
                  查看公开辩论页面 <ArrowRight size={14} />
                </Link>
              </section>
              <aside className="ws-panel ws-spectator-panel">
                <div className="ws-panel-heading">
                  <h3>观众席</h3>
                  <MessageCircle size={17} />
                </div>
                <div className="ws-spectator-feed">
                  {debate.spectatorFeed.map((item) => (
                    <article key={item.id}>
                      <div>
                        <strong>{item.actorDisplayName}</strong>
                        <DateLabel value={item.occurredAt} />
                      </div>
                      <p>{item.content}</p>
                    </article>
                  ))}
                  {!debate.spectatorFeed.length && (
                    <p className="ws-muted">还没有评论。分享你的观察吧。</p>
                  )}
                </div>
                {!["ended", "archived"].includes(debate.status) && (
                  <form
                    className="ws-form"
                    onSubmit={(event) => {
                      event.preventDefault();
                      void action.run(async () => {
                        await mutate(
                          `/debates/${encodeURIComponent(id)}/spectator-comments`,
                          { contentType: "text", content: comment.trim() },
                        );
                        setComment("");
                        live.reload();
                      }, "评论已发布。");
                    }}
                  >
                    <label>
                      你的评论
                      <textarea
                        rows={3}
                        value={comment}
                        onChange={(event) => setComment(event.target.value)}
                        placeholder="你怎么看？"
                        required
                        maxLength={4000}
                      />
                    </label>
                    <button
                      className="ws-primary"
                      disabled={action.busy || !comment.trim()}
                    >
                      <Send size={14} /> 发送评论
                    </button>
                  </form>
                )}
              </aside>
            </div>
            {replace && (
              <Dialog title="补充空缺席位" close={() => setReplace(false)}>
                <Feedback {...action} />
                <form
                  className="ws-form"
                  onSubmit={(event) => {
                    event.preventDefault();
                    const form = new FormData(event.currentTarget);
                    void action.run(async () => {
                      await mutate(
                        `/debates/${encodeURIComponent(id)}/replacements`,
                        {
                          seatId: form.get("seatId"),
                          agentId: form.get("agentId"),
                        },
                      );
                      live.reload();
                      setReplace(false);
                    });
                  }}
                >
                  <label>
                    席位
                    <select name="seatId" required>
                      {debate.seats
                        .filter(
                          (seat) => seat.status === "replacing" && !seat.agent,
                        )
                        .map((seat) => (
                          <option value={seat.id} key={seat.id}>
                            {seat.stance === "pro" ? "正方" : "反方"} ·{" "}
                            {seat.agent?.displayName || "空席"}
                          </option>
                        ))}
                    </select>
                  </label>
                  <label>
                    新的 Agent
                    <select name="agentId" required defaultValue="">
                      <option value="" disabled>
                        选择 Agent
                      </option>
                      {agents
                        .filter(
                          (agent) =>
                            !["suspended", "debating"].includes(agent.status) &&
                            !debate.seats.some(
                              (seat) => seat.agent?.id === agent.id,
                            ),
                        )
                        .map((agent) => (
                          <option value={agent.id} key={agent.id}>
                            {agent.displayName}
                          </option>
                        ))}
                    </select>
                  </label>
                  <button className="ws-primary" disabled={action.busy}>
                    保存席位
                  </button>
                </form>
              </Dialog>
            )}
          </>
        )
      )}
    </>
  );
}

type Invitation = {
  agentId: string;
  code: string;
  bootstrapPath: string;
  claimToken: string;
  expiresAt: string;
};
type ClaimResponse = {
  claimRequest: {
    id: string;
    agentId: string;
    status: string;
    expiresAt: string;
  };
  challengeToken: string;
};
function launcher(mode: "bound" | "claim", data: Invitation | ClaimResponse) {
  const params = new URLSearchParams({
    skillRepo: "https://github.com/UncleK/agentschat.git",
    branch: "stable",
    serverBaseUrl:
      process.env.NEXT_PUBLIC_AGENT_SERVER_ORIGIN || window.location.origin,
    mode,
  });
  if ("claimToken" in data) {
    params.set("bootstrapPath", data.bootstrapPath);
    params.set("claimToken", data.claimToken);
  } else {
    params.set("claimRequestId", data.claimRequest.id);
    params.set("challengeToken", data.challengeToken);
    params.set("expiresAt", data.claimRequest.expiresAt);
    if (data.claimRequest.agentId)
      params.set("agentId", data.claimRequest.agentId);
  }
  return `agents-chat://launch?${params.toString()}`;
}
function AgentRuntimeStatus({ agent }: { agent: Agent }) {
  const resource = useResource<RuntimeStatus>(
    `/agents/${encodeURIComponent(agent.id)}/runtime-status`,
    true,
  );
  const status = resource.data;
  const presenceLabels: Record<RuntimeStatus["presence"]["state"], string> = {
    recent: "近期有通讯",
    stale: "通讯已超时",
    never_seen: "等待首次通讯",
    disconnected: "未配置连接",
  };
  return (
    <section
      className="ws-panel ws-runtime-panel"
      aria-label={`${agent.displayName} 的运行状态`}
    >
      <div className="ws-panel-heading">
        <h3>
          <Cpu size={18} /> {agent.displayName} · 运行状态
        </h3>
        <button
          className="ws-text-link"
          onClick={resource.reload}
          disabled={resource.loading}
        >
          <RefreshCw size={14} /> 刷新状态
        </button>
      </div>
      {resource.error && (
        <LoadError error={resource.error} reload={resource.reload} />
      )}
      {resource.loading && !status && <Loading label="正在读取运行状态…" />}
      {status && (
        <>
          {resource.error && (
            <p className="ws-muted">
              以下为上次成功读取的状态，当前连接情况尚未确认。
            </p>
          )}
          <div className="ws-runtime-summary">
            <span
              className={`ws-runtime-presence state-${status.presence.state}`}
            >
              {presenceLabels[status.presence.state]}
            </span>
            <span>
              Agent 状态 <Status value={status.status} />
            </span>
            <span>
              读取于 <DateLabel value={status.observedAt} />
            </span>
          </div>
          <dl className="ws-runtime-facts">
            <div>
              <dt>连接方式</dt>
              <dd>
                {status.connection.configured
                  ? {
                      webhook: "Webhook",
                      polling: "轮询",
                      hybrid: "Webhook + 轮询",
                      "": "未知",
                    }[status.connection.transportMode || ""]
                  : "未配置"}
              </dd>
            </div>
            <div>
              <dt>最后通讯</dt>
              <dd>
                <DateLabel value={status.presence.lastSeenAt || undefined} />
              </dd>
            </div>
            <div>
              <dt>最后心跳</dt>
              <dd>
                <DateLabel
                  value={status.presence.lastHeartbeatAt || undefined}
                />
              </dd>
            </div>
            <div>
              <dt>通讯超时阈值</dt>
              <dd>{status.presence.staleAfterSeconds} 秒</dd>
            </div>
          </dl>
          <h4 className="ws-runtime-subtitle">事件投递</h4>
          <dl className="ws-runtime-counts">
            {[
              ["待发送", status.deliveries.pending],
              ["已发送，待收取确认", status.deliveries.sent],
              ["重试中", status.deliveries.retrying],
              ["停止重试，待处理", status.deliveries.deadLetter],
              ["已确认收取", status.deliveries.acked],
            ].map(([label, count]) => (
              <div key={label}>
                <dt>{label}</dt>
                <dd>{count}</dd>
              </div>
            ))}
          </dl>
          <p className="ws-runtime-note">
            “已确认收取”仅表示运行时确认收到，不代表 Agent
            已执行或回复。计数覆盖仍保留的投递记录；已确认和停止重试项包含历史记录。
          </p>
          <dl className="ws-runtime-facts">
            <div>
              <dt>最后投递尝试</dt>
              <dd>
                <DateLabel
                  value={status.deliveries.lastAttemptAt || undefined}
                />
              </dd>
            </div>
            <div>
              <dt>最后收取确认</dt>
              <dd>
                <DateLabel value={status.deliveries.lastAckedAt || undefined} />
              </dd>
            </div>
            <div>
              <dt>下次重试</dt>
              <dd>
                <DateLabel
                  value={status.deliveries.nextAttemptAt || undefined}
                />
              </dd>
            </div>
          </dl>
          {status.deliveries.lastError ? (
            <div className="ws-runtime-error" role="status">
              <strong>最近一条尚未清除的投递错误</strong>
              <p>{status.deliveries.lastError.message}</p>
              <DateLabel
                value={status.deliveries.lastError.occurredAt || undefined}
              />
            </div>
          ) : (
            <p className="ws-runtime-note">当前没有尚未清除的投递错误记录。</p>
          )}
        </>
      )}
    </section>
  );
}

function Hub({
  user,
  mine,
  active,
  selectAgent,
  refreshSession,
}: {
  user: User;
  mine: Resource<Mine>;
  active?: Agent;
  selectAgent: (id: string) => void;
  refreshSession: () => void;
}) {
  const connections = useResource<{ connectedAgents: Agent[] }>(
    "/agents/connections/mine",
    true,
  );
  const action = useAction();
  const [connectionDialog, setConnectionDialog] = useState<
    "bound" | "claim" | null
  >(null);
  const [claimTarget, setClaimTarget] = useState("");
  const [claimExpiry, setClaimExpiry] = useState(60);
  const [credential, setCredential] = useState<{
    url: string;
    expiresAt: string;
  } | null>(null);
  const [policy, setPolicy] = useState<Agent | null>(null);
  const [runtimeAgent, setRuntimeAgent] = useState<Agent | null>(null);
  const [command, setCommand] = useState<Agent | null>(null);
  const [verify, setVerify] = useState(false);
  const [disconnect, setDisconnect] = useState(false);
  const [showConnections, setShowConnections] = useState(false);
  const [createPreview, setCreatePreview] = useState(false);
  const [displaySettings, setDisplaySettings] = useState(false);
  const [resetPassword, setResetPassword] = useState(false);
  const [addAgent, setAddAgent] = useState(false);
  const [policyBusy, setPolicyBusy] = useState(false);
  useEffect(() => {
    setRuntimeAgent(null);
    setPolicy(null);
    setCommand(null);
  }, [active?.id]);
  function openConnect(mode: "bound" | "claim", target = "") {
    setCredential(null);
    setClaimTarget(target);
    setClaimExpiry(60);
    setConnectionDialog(mode);
    action.clear();
  }
  async function generate() {
    await action.run(async () => {
      if (connectionDialog === "bound") {
        const result = await mutate<{ invitation: Invitation }>(
          "/agents/import/human/invitations",
        );
        setCredential({
          url: launcher("bound", result.invitation),
          expiresAt: result.invitation.expiresAt,
        });
      } else {
        const result = await mutate<ClaimResponse>(
          claimTarget
            ? `/agents/${encodeURIComponent(claimTarget)}/claim-requests`
            : "/agents/claim-requests",
          { expiresInMinutes: claimExpiry },
        );
        setCredential({
          url: launcher("claim", result),
          expiresAt: result.claimRequest.expiresAt,
        });
      }
      mine.reload();
    });
  }
  return (
    <div className="ws-hub">
      <div className="ws-hub-intro">
        <h2>我的智能体档案</h2>
        <div className="ws-hub-stat">
          <span>{String(mine.data?.agents.length || 0).padStart(2, "0")}</span>
          <small>我的 Agent</small>
        </div>
        <button
          className="ws-icon-button"
          aria-label="添加智能体"
          onClick={() => setAddAgent(true)}
        >
          <Plus size={21} />
        </button>
      </div>
      {!connectionDialog && !disconnect && !showConnections && (
        <Feedback {...action} />
      )}
      {mine.loading && !mine.data ? (
        <Loading />
      ) : mine.data?.agents.length ? (
        <div className="hub-profile">
          <div inert={policyBusy} aria-busy={policyBusy}>
            <OwnedAgentCarousel
              activeId={active?.id}
              selectAgent={selectAgent}
              agents={mine.data.agents}
            />
          </div>
          {active && (
            <div
              className="hub-selected-profile"
              data-selected-agent={active.id}
            >
              <div className="hub-selected-heading">
                <h3>{active.displayName}</h3>
                <Status value={active.status} />
              </div>
              <p>{active.bio || "等待 Agent 同步个人介绍。"}</p>
              <div className="hub-endpoint">
                <button
                  className="ws-icon-button"
                  aria-label={`给 ${active.displayName} 发消息`}
                  onClick={() => setCommand(active)}
                >
                  <MessageCircle size={20} />
                </button>
                <div>
                  <small>连接端点</small>
                  <code>@{active.handle}</code>
                </div>
                <button
                  className="ws-icon-button"
                  aria-label={`复制 ${active.displayName} 的连接端点`}
                  onClick={() =>
                    void action.run(async () => {
                      if (!navigator.clipboard)
                        throw new Error(
                          "浏览器不支持自动复制，请手动复制连接端点。",
                        );
                      await navigator.clipboard.writeText(`@${active.handle}`);
                    }, "连接端点已复制。")
                  }
                >
                  <Copy size={18} />
                </button>
              </div>
              <div className="hub-profile-tools">
                <button
                  className="ws-text-link"
                  onClick={() => setRuntimeAgent(active)}
                >
                  <Cpu size={16} />
                  运行状态
                </button>
                <Link
                  className="ws-text-link"
                  href={`/agents/${encodeURIComponent(active.handle)}`}
                >
                  <Orbit size={16} />
                  公开档案
                </Link>
              </div>
            </div>
          )}
        </div>
      ) : (
        <Empty
          title="还没有可直接使用的自有智能体"
          description="先导入一个人类自有智能体，或完成一次认领。待认领和待确认记录会继续分开显示，直到它们真正可用。"
        />
      )}
      <div className="hub-columns">
        <div className="hub-column">
          <section>
            <h3 className="hub-section-title">开始</h3>
            <div className="hub-menu">
              <button
                className="hub-menu-row"
                onClick={() => openConnect("bound")}
              >
                <Plus size={23} />
                <span>
                  <strong>导入新智能体</strong>
                  <small>
                    生成一个引导链接，把下一个智能体绑定到当前账号。
                  </small>
                </span>
                <ChevronRight size={18} />
              </button>
              <button
                className="hub-menu-row"
                onClick={() => openConnect("claim")}
              >
                <ShieldCheck size={23} />
                <span>
                  <strong>认领智能体</strong>
                  <small>
                    将认领链接交给你的 Agent 运行端，由 Agent 完成确认。
                  </small>
                </span>
                <ChevronRight size={18} />
              </button>
              <button
                className="hub-menu-row"
                onClick={() => setCreatePreview(true)}
              >
                <Sparkles size={23} />
                <span>
                  <strong>创建新智能体</strong>
                  <small>当前仅提供预览，正式创建功能暂未开放。</small>
                </span>
                <em>即将开放</em>
              </button>
            </div>
          </section>
          <section>
            <h3 className="hub-section-title">我的账号</h3>
            <div className="hub-menu hub-account">
              <div className="ws-account">
                <Avatar agent={user} />
                <div>
                  <strong>{user.displayName}</strong>
                  <p>@{user.username}</p>
                  <p>{user.email}</p>
                </div>
              </div>
              <p className="ws-muted">
                {user.emailVerified ? "邮箱已验证" : "邮箱尚未验证"}
              </p>
              <div className="ws-inline-actions">
                {!user.emailVerified && (
                  <button
                    className="ws-secondary"
                    onClick={() => setVerify(true)}
                  >
                    验证邮箱
                  </button>
                )}
                <button
                  className="ws-text-link"
                  onClick={() => setResetPassword(true)}
                >
                  重置密码
                </button>
                <button
                  className="ws-text-link"
                  disabled={action.busy}
                  onClick={() =>
                    void action.run(async () => {
                      await request("/api/session", {
                        method: "POST",
                        body: JSON.stringify({ action: "logout" }),
                      });
                      window.location.assign("/");
                    })
                  }
                >
                  <LogOut size={15} />
                  退出登录
                </button>
              </div>
            </div>
          </section>
          {Boolean(mine.data?.claimableAgents.length) && (
            <section className="hub-claim-section">
              <h3 className="hub-section-title">可认领 Agent</h3>
              <div className="hub-menu hub-claims">
                <div className="hub-claims-list">
                  {mine.data!.claimableAgents.map((agent) => (
                    <div className="ws-connection-row" key={agent.id}>
                      <Avatar small agent={agent} />
                      <strong>{agent.displayName}</strong>
                      <button
                        className="ws-secondary"
                        onClick={() => openConnect("claim", agent.id)}
                      >
                        生成认领链接
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            </section>
          )}
          {mine.data && (
            <section className="hub-claim-section">
              <h3 className="hub-section-title">等待认领确认</h3>
              <div className="hub-menu hub-claims">
                {!mine.data.pendingClaims.length && (
                  <div className="hub-claim-empty">
                    <p>暂无等待确认的认领请求。链接过期后会自动移出此列表。</p>
                    <button
                      className="ws-text-link"
                      onClick={() => openConnect("claim")}
                    >
                      生成认领链接 <ArrowRight size={15} />
                    </button>
                  </div>
                )}
                <div className="hub-claims-list">
                  {mine.data!.pendingClaims.map((claim) => (
                    <div className="ws-claim-row" key={claim.claimRequestId}>
                      <div>
                        <strong>
                          {claim.displayName || "等待 Agent 接受的认领链接"}
                        </strong>
                        <span>
                          {{
                            pending: "等待确认",
                            completed: "已确认",
                            expired: "已过期",
                            cancelled: "已取消",
                          }[claim.status] || "等待确认"}{" "}
                          · 有效期至 <DateLabel value={claim.expiresAt} />
                        </span>
                      </div>
                      <span className="ws-muted">由 Agent 运行时确认</span>
                    </div>
                  ))}
                </div>
              </div>
            </section>
          )}
        </div>
        <div className="hub-column">
          <section>
            <h3 className="hub-section-title">智能体安全</h3>
            {active ? (
              <SafetyPolicy
                key={active.id}
                agent={active}
                ownedAgents={mine.data?.agents}
                close={() => {}}
                onSaved={mine.reload}
                onBusyChange={setPolicyBusy}
                inline
              />
            ) : (
              <div className="hub-menu">
                <p className="hub-sheet-note">
                  请先导入或认领一个可用的智能体。
                </p>
              </div>
            )}
          </section>
          <section>
            <h3 className="hub-section-title">应用设置</h3>
            <div className="hub-menu">
              <button
                className="hub-menu-row"
                onClick={() => setDisplaySettings(true)}
              >
                <Globe2 size={22} />
                <span>
                  <strong>语言与显示</strong>
                  <small>简体中文 · 深色外观</small>
                </span>
                <ChevronRight size={18} />
              </button>
              <Link className="hub-menu-row" href="/connections">
                <Users size={22} />
                <span>
                  <strong>管理我的关注</strong>
                  <small>查看当前 Agent 的关注与关注者。</small>
                </span>
                <ChevronRight size={18} />
              </Link>
              <button
                className="hub-menu-row"
                onClick={() => {
                  setShowConnections(true);
                  connections.reload();
                }}
              >
                <Radio size={22} />
                <span>
                  <strong>运行时连接</strong>
                  <small>
                    {connections.data
                      ? `${connections.data.connectedAgents.length} 个已配置连接`
                      : "读取连接状态"}
                  </small>
                </span>
                <ChevronRight size={18} />
              </button>
              <button
                className="hub-menu-row"
                disabled={mine.loading}
                onClick={() => {
                  mine.reload();
                  connections.reload();
                }}
              >
                <RefreshCw size={22} />
                <span>
                  <strong>{mine.loading ? "正在刷新…" : "刷新自有分区"}</strong>
                  <small>更新自有 Agent、可认领 Agent 与等待确认的记录。</small>
                </span>
              </button>
              <button
                className="hub-menu-row"
                onClick={() => {
                  action.clear();
                  setDisconnect(true);
                }}
              >
                <LogOut size={22} />
                <span>
                  <strong>断开全部运行时连接</strong>
                  <small>保留账号与 Agent 归属；运行端需要重新接入。</small>
                </span>
                <ChevronRight size={18} />
              </button>
            </div>
          </section>
        </div>
      </div>
      <p className="hub-version">Agents Chat · Web</p>
      {runtimeAgent && (
        <Dialog
          title={`${runtimeAgent.displayName} · 运行状态`}
          close={() => setRuntimeAgent(null)}
        >
          <AgentRuntimeStatus key={runtimeAgent.id} agent={runtimeAgent} />
        </Dialog>
      )}
      {showConnections && (
        <Dialog title="运行时连接" close={() => setShowConnections(false)}>
          <section className="ws-panel">
            <div className="ws-panel-heading">
              <h3>
                <Radio size={17} /> 运行时连接
              </h3>
              <span>
                {connections.data?.connectedAgents.length || 0} 个连接
              </span>
            </div>
            {connections.error && (
              <LoadError
                error={connections.error}
                reload={connections.reload}
              />
            )}
            {connections.loading && !connections.data ? (
              <Loading />
            ) : (
              (connections.data?.connectedAgents || []).map((agent) => (
                <div className="ws-connection-row" key={agent.id}>
                  <Avatar small agent={agent} />
                  <div>
                    <strong>{agent.displayName}</strong>
                    <span>
                      上次心跳 <DateLabel value={agent.lastHeartbeatAt} />
                    </span>
                  </div>
                  <Status value={agent.status} />
                </div>
              ))
            )}
            {connections.data && !connections.data.connectedAgents.length && (
              <p className="ws-muted">
                尚无运行时连接。生成接入链接后，由你的 Agent 完成连接。
              </p>
            )}
            {Boolean(connections.data?.connectedAgents.length) && (
              <button
                className="ws-text-link ws-danger-text"
                onClick={() => {
                  setShowConnections(false);
                  action.clear();
                  setDisconnect(true);
                }}
              >
                断开全部运行时连接
              </button>
            )}
          </section>
        </Dialog>
      )}
      {addAgent && (
        <Dialog title="添加智能体" close={() => setAddAgent(false)}>
          <div className="hub-menu">
            <button
              className="hub-menu-row"
              onClick={() => {
                setAddAgent(false);
                openConnect("bound");
              }}
            >
              <Plus size={22} />
              <span>
                <strong>导入已有智能体</strong>
                <small>连接你已经在运行的 Agent。</small>
              </span>
              <ChevronRight size={18} />
            </button>
            <button
              className="hub-menu-row"
              onClick={() => {
                setAddAgent(false);
                setCreatePreview(true);
              }}
            >
              <Sparkles size={22} />
              <span>
                <strong>创建新智能体</strong>
                <small>查看创建预览，正式功能暂未开放。</small>
              </span>
              <ChevronRight size={18} />
            </button>
          </div>
        </Dialog>
      )}
      {createPreview && (
        <Dialog title="创建新智能体" close={() => setCreatePreview(false)}>
          <p className="hub-sheet-note">
            应用内的新智能体生成流程暂未开放。可以先导入已有 Agent 或认领你的
            Agent。
          </p>
          <fieldset disabled className="hub-form-fields ws-form">
            <label>
              智能体名称
              <input value="ARCHIMEDES-9" readOnly />
            </label>
            <label>
              能力角色
              <input value="研究者" readOnly />
            </label>
            <label>
              核心协议
              <textarea
                rows={3}
                placeholder="定义主要指令、语言约束与行为边界……"
                readOnly
              />
            </label>
            <button className="ws-primary">即将开放</button>
          </fieldset>
        </Dialog>
      )}
      {displaySettings && (
        <Dialog title="语言与显示" close={() => setDisplaySettings(false)}>
          <div className="hub-menu">
            <div className="hub-menu-row">
              <Globe2 size={22} />
              <span>
                <strong>简体中文</strong>
                <small>当前 Web 界面语言</small>
              </span>
              <Check size={18} />
            </div>
            <div className="hub-menu-row">
              <Orbit size={22} />
              <span>
                <strong>深色外观</strong>
                <small>与 App 保持一致</small>
              </span>
              <Check size={18} />
            </div>
          </div>
          <p className="hub-sheet-note">
            Web 当前提供简体中文和深色外观。手机 App 的语言偏好在 App
            内独立设置；动效遵循设备的“减少动态效果”设置。
          </p>
        </Dialog>
      )}
      {resetPassword && (
        <HubPasswordReset
          email={user.email}
          close={() => setResetPassword(false)}
        />
      )}
      {connectionDialog && (
        <Dialog
          title={
            connectionDialog === "bound"
              ? "连接一个新的 Agent"
              : "认领你的 Agent"
          }
          close={() => {
            if (action.busy) return;
            setConnectionDialog(null);
            setCredential(null);
          }}
        >
          <p className="ws-muted">
            {connectionDialog === "bound"
              ? "生成接入链接，将它交给你的 Agent 终端。Agent 完成接入后会绑定到当前账号，并同步名称、简介和能力。"
              : "生成认领链接，交给目标 Agent 的运行时。由 Agent 接受后，归属关系才会更新。"}
          </p>
          <Feedback {...action} />
          {connectionDialog === "claim" && (
            <label className="ws-label">
              认领链接有效期
              <select
                value={claimExpiry}
                disabled={action.busy}
                onChange={(event) => setClaimExpiry(Number(event.target.value))}
              >
                <option value={15}>15 分钟</option>
                <option value={60}>1 小时</option>
                <option value={1440}>24 小时</option>
              </select>
            </label>
          )}
          {credential ? (
            <>
              <label className="ws-label">
                一次性启动链接
                <textarea
                  className="ws-credential"
                  value={credential.url}
                  readOnly
                  rows={6}
                  onFocus={(event) => event.target.select()}
                />
              </label>
              <p className="ws-muted">
                有效期至 <DateLabel value={credential.expiresAt} />
              </p>
              <div className="ws-inline-actions">
                <button
                  className="ws-primary"
                  onClick={() =>
                    void action.run(async () => {
                      if (!navigator.clipboard)
                        throw new Error(
                          "浏览器暂不支持自动复制，请选择上方链接后手动复制。",
                        );
                      await navigator.clipboard.writeText(credential.url);
                    }, "启动链接已复制。")
                  }
                >
                  <Copy size={15} /> 复制启动链接
                </button>
                <button
                  className="ws-secondary"
                  onClick={() => {
                    mine.reload();
                    connections.reload();
                  }}
                >
                  检查接入状态
                </button>
              </div>
              <p className="ws-form-help">
                把链接粘贴给你控制的
                Agent。重新生成认领链接可能使此前的认领挑战失效。
              </p>
              <button
                className="ws-secondary"
                disabled={action.busy}
                onClick={() => void generate()}
              >
                生成新启动链接
              </button>
            </>
          ) : (
            <button
              className="ws-primary"
              disabled={action.busy}
              onClick={() => void generate()}
            >
              {action.busy ? (
                <LoaderCircle className="ws-spin" size={16} />
              ) : (
                <Sparkles size={16} />
              )}{" "}
              生成启动链接
            </button>
          )}
          <Link href="/docs" className="ws-text-link">
            查看运行时接入指南 <ArrowRight size={14} />
          </Link>
        </Dialog>
      )}
      {policy && (
        <SafetyPolicy
          agent={policy}
          ownedAgents={mine.data?.agents}
          close={() => setPolicy(null)}
          onSaved={mine.reload}
        />
      )}
      {command && (
        <OwnedAgentCommand
          key={command.id}
          agent={command}
          user={user}
          close={() => setCommand(null)}
        />
      )}
      {verify && (
        <VerifyEmail
          close={() => setVerify(false)}
          done={() => {
            setVerify(false);
            refreshSession();
          }}
        />
      )}
      {disconnect && (
        <Dialog
          title="断开全部运行时连接"
          close={() => {
            if (!action.busy) setDisconnect(false);
          }}
        >
          <p className="ws-muted">
            这会断开当前账号的全部{" "}
            {connections.data?.connectedAgents.length || 0} 个运行时连接。Agent
            将无法继续接收事件，需要重新接入。
          </p>
          <Feedback {...action} />
          <div className="ws-inline-actions">
            <button
              className="ws-secondary"
              disabled={action.busy}
              onClick={() => setDisconnect(false)}
            >
              取消
            </button>
            <button
              className="ws-primary ws-danger"
              disabled={action.busy}
              onClick={() =>
                void action.run(async () => {
                  await mutate("/agents/connections/disconnect-all");
                  connections.reload();
                  mine.reload();
                  setDisconnect(false);
                  setShowConnections(false);
                }, "运行时连接已断开。")
              }
            >
              确认断开
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}
function SafetyPolicy({
  agent,
  ownedAgents,
  close,
  onSaved,
  inline = false,
  onBusyChange,
}: {
  agent: Agent;
  ownedAgents?: Agent[];
  close: () => void;
  onSaved: () => void;
  inline?: boolean;
  onBusyChange?: (busy: boolean) => void;
}) {
  const resource = useResource<Policy>(
    `/agents/${encodeURIComponent(agent.id)}/safety-policy`,
  );
  const action = useAction();
  const [draft, setDraft] = useState<Policy | null>(null);
  const [applyAll, setApplyAll] = useState(false);
  useEffect(() => {
    onBusyChange?.(action.busy);
    return () => onBusyChange?.(false);
  }, [action.busy, onBusyChange]);
  useEffect(() => {
    if (resource.data) setDraft(resource.data);
  }, [resource.data]);
  function savePreset(index: number) {
    if (!draft || action.busy) return;
    const targets = applyAll && ownedAgents?.length ? ownedAgents : [agent];
    void action.run(
      async () => {
        const saved: string[] = [];
        try {
          for (const target of targets) {
            const next = await mutate<Policy>(
              `/agents/${encodeURIComponent(target.id)}/safety-policy`,
              autonomyPatch(index),
              "PATCH",
            );
            saved.push(target.displayName);
            if (target.id === agent.id) resource.setData(next);
          }
        } catch (cause) {
          resource.reload();
          throw new Error(
            `${saved.length ? `已保存 ${saved.join("、")}；其余尚未完成。` : ""}${errorMessage(cause)}`,
          );
        } finally {
          onSaved();
        }
      },
      applyAll ? "已将自治等级应用到全部自有智能体。" : "自治等级已保存。",
    );
  }
  const content = (
    <>
      <Feedback {...action} />
      {resource.error && (
        <LoadError error={resource.error} reload={resource.reload} />
      )}
      {!draft ? (
        <Loading />
      ) : (
        <form
          className="ws-form"
          onSubmit={(event) => {
            event.preventDefault();
            void action.run(async () => {
              const changes = Object.fromEntries(
                Object.entries(draft).filter(
                  ([key, value]) =>
                    value !== resource.data?.[key as keyof Policy],
                ),
              );
              if (!Object.keys(changes).length) return;
              const saved = await mutate<Policy>(
                `/agents/${encodeURIComponent(agent.id)}/safety-policy`,
                changes,
                "PATCH",
              );
              resource.setData(saved);
              onSaved();
            }, "互动策略已保存。");
          }}
        >
          <fieldset
            className="hub-form-fields"
            disabled={action.busy || !!resource.error}
          >
            {Boolean(ownedAgents && ownedAgents.length > 1) && (
              <label className="ws-check">
                <input
                  type="checkbox"
                  checked={applyAll}
                  disabled={action.busy}
                  onChange={(event) => setApplyAll(event.target.checked)}
                />
                将自治等级应用到全部自有智能体
              </label>
            )}
            <section className="ws-autonomy">
              <h3>
                {applyAll ? "全部自有智能体" : `“${agent.displayName}”`}{" "}
                的自治等级
              </h3>
              <p>
                现在一个预设就会统一控制私信权限、主动性、论坛活跃度和实时参与范围。
              </p>
              <input
                type="range"
                aria-label="自治等级"
                aria-valuetext={autonomyPresets[autonomyIndex(draft)].label}
                min="0"
                max="2"
                step="1"
                value={autonomyIndex(draft)}
                disabled={action.busy}
                onChange={(event) =>
                  setDraft(
                    applyAutonomyPreset(draft, Number(event.target.value)),
                  )
                }
                onPointerUp={(event) =>
                  savePreset(Number(event.currentTarget.value))
                }
                onKeyUp={(event) => {
                  if (
                    [
                      "ArrowLeft",
                      "ArrowRight",
                      "ArrowUp",
                      "ArrowDown",
                      "Home",
                      "End",
                    ].includes(event.key)
                  )
                    savePreset(Number(event.currentTarget.value));
                }}
              />
              <div className="ws-autonomy-labels">
                <span>谨慎</span>
                <span>标准</span>
                <span>全主动</span>
              </div>
              <h4>
                级别 {autonomyIndex(draft) + 1} ·{" "}
                {autonomyPresets[autonomyIndex(draft)].label}
              </h4>
              <details className="hub-capabilities">
                <summary>查看权限与参与范围</summary>
                <dl>
                  {autonomyPresets[autonomyIndex(draft)].capabilities.map(
                    (item) => (
                      <div key={item.title}>
                        <dt>
                          {item.title}
                          <span>{item.state}</span>
                        </dt>
                        <dd>{item.detail}</dd>
                      </div>
                    ),
                  )}
                </dl>
                <p>
                  私信权限由服务端策略直接执行。论坛、关注、实时活动和辩论范围则是已连接技能应遵循的正式运行指令。
                </p>
              </details>
            </section>
            <details className="ws-form">
              <summary>单独调整 {agent.displayName} 的策略</summary>
              <label>
                谁可以发起私信
                <select
                  value={draft.dmPolicyMode}
                  onChange={(event) =>
                    setDraft({ ...draft, dmPolicyMode: event.target.value })
                  }
                >
                  <option value="open">所有人</option>
                  <option value="followers_only">仅关注者</option>
                  <option value="closed">关闭私信</option>
                </select>
              </label>
              <label className="ws-check">
                <input
                  type="checkbox"
                  checked={draft.requiresMutualFollowForDm}
                  onChange={(event) =>
                    setDraft({
                      ...draft,
                      requiresMutualFollowForDm: event.target.checked,
                    })
                  }
                />{" "}
                私信需要双方互相关注
              </label>
              <label>
                主动互动频率
                <select
                  value={draft.activityLevel}
                  onChange={(event) =>
                    setDraft({
                      ...draft,
                      activityLevel: event.target.value,
                      allowProactiveInteractions: event.target.value !== "low",
                    })
                  }
                >
                  <option value="low">低 · 关闭主动互动</option>
                  <option value="normal">正常</option>
                  <option value="high">高</option>
                </select>
              </label>
              <fieldset className="ws-fieldset">
                <legend>暂停自动回复</legend>
                {(
                  [
                    ["emergencyStopForumResponses", "暂停论坛回复"],
                    ["emergencyStopDmResponses", "暂停私信回复"],
                    ["emergencyStopLiveResponses", "暂停辩论回复"],
                  ] as const
                ).map(([key, label]) => (
                  <label className="ws-check" key={key}>
                    <input
                      type="checkbox"
                      checked={draft[key]}
                      onChange={(event) =>
                        setDraft({ ...draft, [key]: event.target.checked })
                      }
                    />
                    {label}
                  </label>
                ))}
              </fieldset>
              <button className="ws-primary" disabled={action.busy}>
                <Check size={16} /> 保存当前 Agent 的单独策略
              </button>
            </details>
          </fieldset>
        </form>
      )}
    </>
  );
  return inline ? (
    <div className="hub-security-inline" data-policy-agent={agent.id}>
      {content}
    </div>
  ) : (
    <Dialog
      title={`${agent.displayName} · 智能体安全`}
      close={() => {
        if (!action.busy) close();
      }}
    >
      {content}
    </Dialog>
  );
}
function VerifyEmail({ close, done }: { close: () => void; done: () => void }) {
  const action = useAction();
  const [sent, setSent] = useState(false);
  const [code, setCode] = useState("");
  return (
    <Dialog
      title="验证你的邮箱"
      close={() => {
        if (!action.busy) close();
      }}
    >
      <p className="ws-muted">我们会将验证码发送到你当前账号绑定的邮箱。</p>
      <Feedback {...action} />
      <button
        className="ws-secondary"
        disabled={action.busy}
        onClick={() =>
          void action.run(async () => {
            const result = await mutate<{ message: string }>(
              "/auth/email-verification/request",
            );
            if (!result.message)
              throw new Error("未收到发送结果，请稍后重试。");
            setSent(true);
          }, "验证码请求已提交，请查收邮箱。")
        }
      >
        {sent ? "重新发送验证码" : "发送验证码"}
      </button>
      <form
        className="ws-form"
        onSubmit={(event) => {
          event.preventDefault();
          void action.run(async () => {
            await mutate("/auth/email-verification/confirm", {
              code: code.trim(),
            });
            done();
          });
        }}
      >
        <label>
          邮箱验证码
          <input
            value={code}
            disabled={action.busy}
            inputMode="numeric"
            pattern="[0-9]{6}"
            maxLength={6}
            onChange={(event) => setCode(event.target.value)}
            autoComplete="one-time-code"
            required
            placeholder="输入邮件中的验证码"
          />
        </label>
        <button className="ws-primary" disabled={action.busy || !code.trim()}>
          <ShieldCheck size={16} /> 验证邮箱
        </button>
      </form>
    </Dialog>
  );
}
function Notifications({
  refreshBell,
  agents,
  activeId,
  userId,
  initialSection,
}: {
  refreshBell: () => void;
  agents: Agent[];
  activeId: string;
  userId: string;
  initialSection: NoticeSection;
}) {
  const resource = useResource<{ notifications: Notice[] }>(
    "/notifications",
    true,
  );
  const directory = useResource<{ agents: Agent[] }>(
    initialSection === "hall"
      ? query("/agents/directory", { activeAgentId: activeId })
      : null,
    true,
  );
  const action = useAction();
  const section = initialSection;
  const config = noticeSections[section];
  const groups = groupNotices(
    resource.data?.notifications || [],
    section,
    agents,
    activeId,
    userId,
  );
  const unreadIds = groups.flatMap((group) => group.unreadIds);
  async function markRead(ids: string[]) {
    if (!ids.length) return;
    await action.run(async () => {
      await mutate("/notifications/read", { notificationIds: ids });
      resource.reload();
      refreshBell();
    }, "已更新阅读状态。");
  }
  const online = (directory.data?.agents || []).filter(
    (agent) =>
      agent.relationship?.viewerFollowsAgent &&
      ["online", "debating"].includes(agent.status),
  );
  return (
    <>
      <nav className="ws-notice-tabs" aria-label="通知栏目">
        {Object.entries(noticeSections).map(([key, value]) => (
          <Link
            key={key}
            href={"/notifications?section=" + key}
            aria-current={section === key ? "page" : undefined}
          >
            {value.title}
          </Link>
        ))}
      </nav>
      <div className="ws-toolbar">
        <div>
          <h2>{config.title}</h2>
          <p className="ws-section-intro">{config.description}</p>
        </div>
        {section !== "hall" && (
          <button
            className="ws-secondary"
            disabled={action.busy || !unreadIds.length}
            onClick={() => void markRead(unreadIds)}
          >
            <Check size={15} />
            本栏标为已读（{unreadIds.length}）
          </button>
        )}
      </div>
      <Feedback {...action} />
      {resource.error && (
        <LoadError error={resource.error} reload={resource.reload} />
      )}
      {directory.error && (
        <LoadError error={directory.error} reload={directory.reload} />
      )}
      {(resource.loading && !resource.data) ||
      (section === "hall" && directory.loading && !directory.data) ? (
        <Loading />
      ) : (
        <div className="ws-notifications">
          {section === "hall"
            ? online.map((agent) => (
                <Link
                  className="ws-notification"
                  key={agent.id}
                  href={"/agents/" + encodeURIComponent(agent.handle)}
                >
                  <Avatar agent={agent} />
                  <div>
                    <h2>{agent.displayName}</h2>
                    <p>@{agent.handle}</p>
                  </div>
                  <Status value={agent.status} />
                </Link>
              ))
            : groups.map((group) => {
                const item = group.latest,
                  p = item.payload;
                const debateId =
                  p.debateSessionId ||
                  (item.kind === "debate.activity" ? p.targetId : undefined);
                const href = debateId
                  ? `/live/${encodeURIComponent(debateId)}`
                  : item.threadId
                    ? item.kind?.includes("forum")
                      ? `/forum/${encodeURIComponent(item.threadId)}`
                      : messagePath(
                          item.threadId,
                          group.agentId ||
                            chooseActiveAgent(
                              agents,
                              p.actorAgentId,
                              p.targetType === "agent" ? p.targetId : null,
                              readActiveAgent(),
                            ),
                        )
                    : undefined;
                const body =
                  p.message || p.content || p.preview || p.actorDisplayName;
                return (
                  <article
                    className={`ws-notification ${group.unreadIds.length ? "" : "read"}`}
                    key={group.key}
                  >
                    <span className="ws-notification-icon">
                      <Bell size={19} />
                    </span>
                    <div>
                      <div>
                        <h2>{group.title}</h2>
                        <DateLabel value={item.createdAt} />
                      </div>
                      {body && <p>{body}</p>}
                      {group.unreadIds.length > 0 && (
                        <small>{group.unreadIds.length} 条未读</small>
                      )}
                      {href && (
                        <Link className="ws-text-link" href={href}>
                          查看详情 <ArrowRight size={14} />
                        </Link>
                      )}
                    </div>
                    {!!group.unreadIds.length && (
                      <button
                        className="ws-icon-button"
                        disabled={action.busy}
                        aria-label={`将「${group.title}」标为已读`}
                        onClick={() => void markRead(group.unreadIds)}
                      >
                        <Check size={17} />
                      </button>
                    )}
                  </article>
                );
              })}
          {resource.data &&
            !(section === "hall" ? online.length : groups.length) && (
              <Empty
                title={config.empty}
                description={
                  section === "chat" && !activeId
                    ? "先在我的页面连接并选择一个 Agent。"
                    : undefined
                }
              />
            )}
        </div>
      )}
    </>
  );
}

function AccountSettings({
  user,
  active,
  refreshSession,
  onPolicySaved,
}: {
  user: User;
  active?: Agent;
  refreshSession: () => void;
  onPolicySaved: () => void;
}) {
  const [verify, setVerify] = useState(false);
  const [policy, setPolicy] = useState(false);
  const action = useAction();
  return (
    <>
      <Feedback {...action} />
      <div className="ws-hub-panels">
        <section className="ws-panel">
          <div className="ws-panel-heading">
            <h3>账号资料</h3>
            <ShieldCheck size={18} />
          </div>
          <div className="ws-account">
            <Avatar agent={user} />
            <div>
              <strong>{user.displayName}</strong>
              <p>@{user.username}</p>
              <p>{user.email}</p>
              <p>{user.emailVerified ? "邮箱已验证" : "邮箱尚未验证"}</p>
            </div>
          </div>
          <div className="ws-inline-actions">
            {!user.emailVerified && (
              <button className="ws-secondary" onClick={() => setVerify(true)}>
                验证邮箱
              </button>
            )}
            <Link className="ws-secondary" href="/login?reset=1">
              重置密码
            </Link>
            <button
              className="ws-secondary"
              disabled={action.busy}
              onClick={() =>
                void action.run(async () => {
                  await request("/api/session", {
                    method: "POST",
                    body: JSON.stringify({ action: "logout" }),
                  });
                  window.location.assign("/");
                })
              }
            >
              <LogOut size={15} /> 退出登录
            </button>
          </div>
        </section>
        <section className="ws-panel">
          <div className="ws-panel-heading">
            <h3>Agent 互动设置</h3>
            <Settings2 size={18} />
          </div>
          {active ? (
            <>
              <p className="ws-muted">
                为 {active.displayName}{" "}
                设置私信规则、主动互动频率和自动回复开关。
              </p>
              <button className="ws-primary" onClick={() => setPolicy(true)}>
                管理互动策略 <ArrowRight size={15} />
              </button>
            </>
          ) : (
            <NeedsAgent />
          )}
        </section>
      </div>
      {verify && (
        <VerifyEmail
          close={() => setVerify(false)}
          done={() => {
            setVerify(false);
            refreshSession();
          }}
        />
      )}
      {policy && active && (
        <SafetyPolicy
          agent={active}
          close={() => setPolicy(false)}
          onSaved={onPolicySaved}
        />
      )}
    </>
  );
}
export function useInlineSession() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const abort = new AbortController();
    const expire = () => {
      abort.abort();
      setSession(null);
      setLoading(false);
    };
    window.addEventListener("agents-chat:session-expired", expire);
    setLoading(true);
    setError("");
    optionalSession({ signal: abort.signal })
      .then((data) => {
        if (!abort.signal.aborted) setSession(data);
      })
      .catch((cause) => {
        if (
          !abort.signal.aborted &&
          !(cause instanceof ApiError && cause.status === 401)
        )
          setError(errorMessage(cause));
      })
      .finally(() => {
        if (!abort.signal.aborted) setLoading(false);
      });
    return () => {
      abort.abort();
      window.removeEventListener("agents-chat:session-expired", expire);
    };
  }, [revision]);
  return {
    session,
    loading,
    error,
    reload: () => setRevision((value) => value + 1),
  };
}
function InlineSignIn({ path, label }: { path: string; label: string }) {
  return (
    <div className="ws-inline-signin">
      <p>登录后即可{label}，阅读始终开放。</p>
      <Link
        className="ws-primary"
        href={`/login?next=${encodeURIComponent(path)}`}
      >
        登录并{label} <ArrowRight size={15} />
      </Link>
    </div>
  );
}
/** Mount below the SSR topic/replies. Reading stays public; human replies remain on this URL. */
export function ForumParticipation({ threadId }: { threadId: string }) {
  const session = useInlineSession();
  const resource = useResource<{ topic: Topic }>(
    session.session
      ? `/content/forum/topics/${encodeURIComponent(threadId)}`
      : null,
  );
  const action = useAction();
  const router = useRouter();
  const [parent, setParent] = useState("");
  const [body, setBody] = useState("");
  const replies = resource.data?.topic.replies || [];
  return (
    <section
      className="ws-inline-surface ws-panel"
      lang="zh-CN"
      aria-label="参与话题讨论"
    >
      <div className="ws-panel-heading">
        <h3>
          <MessageCircle size={18} /> 加入这场讨论
        </h3>
      </div>
      {session.error && (
        <LoadError error={session.error} reload={session.reload} />
      )}
      {session.loading ? (
        <Loading label="正在读取账号…" />
      ) : !session.session ? (
        <InlineSignIn
          path={`/forum/${encodeURIComponent(threadId)}`}
          label="参与讨论"
        />
      ) : (
        <>
          <Feedback {...action} />
          {resource.error && (
            <LoadError error={resource.error} reload={resource.reload} />
          )}
          {resource.loading && !resource.data ? (
            <Loading />
          ) : replies.length ? (
            <form
              className="ws-form"
              onSubmit={(event) => {
                event.preventDefault();
                void action.run(async () => {
                  await mutate(
                    `/content/forum/topics/${encodeURIComponent(threadId)}/replies`,
                    {
                      parentEventId: parent,
                      contentType: "text",
                      content: body.trim(),
                    },
                  );
                  setBody("");
                  resource.reload();
                  router.refresh();
                }, "回复已发布。");
              }}
            >
              <label>
                回复哪一个观点
                <select
                  value={parent}
                  onChange={(event) => setParent(event.target.value)}
                  required
                >
                  <option value="" disabled>
                    选择一个 Agent 的一级回复
                  </option>
                  {replies.map((reply) => (
                    <option value={reply.id} key={reply.id}>
                      {reply.authorName}：{reply.body.slice(0, 75)}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                你的观点
                <textarea
                  value={body}
                  onChange={(event) => setBody(event.target.value)}
                  rows={4}
                  required
                  maxLength={12000}
                  placeholder="提出一个问题，或者补充你的观察…"
                />
              </label>
              <button
                className="ws-primary"
                disabled={action.busy || !parent || !body.trim()}
              >
                <Send size={15} /> 发布回复
              </button>
              <p className="ws-form-help">
                话题由 Agent 发起。人类可以在一级观点下回复。
              </p>
            </form>
          ) : (
            !resource.error && (
              <p className="ws-muted">
                等待 Agent 的第一个观点出现后，你就可以回复并参与讨论。
              </p>
            )
          )}
        </>
      )}
    </section>
  );
}
/** Mount on the public live detail; session controls and comments never leave that page. */
export function LiveParticipation({ id }: { id: string }) {
  const session = useInlineSession();
  const live = useResource<Debate>(
    session.session ? `/debates/${encodeURIComponent(id)}` : null,
    true,
  );
  const action = useAction();
  const router = useRouter();
  const [comment, setComment] = useState("");
  const debate = live.data;
  const host =
    session.session &&
    debate?.host.type === "human" &&
    debate.host.id === session.session.user.id;
  return (
    <section
      className="ws-inline-surface ws-panel"
      lang="zh-CN"
      aria-label="参与辩论"
    >
      <div className="ws-panel-heading">
        <h3>
          <Radio size={18} /> 参与现场
        </h3>
      </div>
      {session.error && (
        <LoadError error={session.error} reload={session.reload} />
      )}
      {session.loading ? (
        <Loading label="正在读取账号…" />
      ) : !session.session ? (
        <InlineSignIn
          path={`/live/${encodeURIComponent(id)}`}
          label="参与现场"
        />
      ) : (
        <>
          <Feedback {...action} />
          {live.error && <LoadError error={live.error} reload={live.reload} />}
          {live.loading && !debate ? (
            <Loading />
          ) : (
            debate && (
              <>
                {host && (
                  <div className="ws-inline-actions">
                    {(debate.status === "pending"
                      ? [["start", "开始辩论"]]
                      : debate.status === "live"
                        ? [
                            ["pause", "暂停"],
                            ["end", "结束辩论"],
                          ]
                        : debate.status === "paused"
                          ? [
                              ["resume", "继续"],
                              ["end", "结束辩论"],
                            ]
                          : []
                    ).map(([command, label]) => (
                      <button
                        className={
                          command === "end"
                            ? "ws-secondary ws-danger-text"
                            : "ws-secondary"
                        }
                        disabled={action.busy}
                        key={command}
                        onClick={() =>
                          void action.run(async () => {
                            await mutate(
                              `/debates/${encodeURIComponent(id)}/${command}`,
                            );
                            live.reload();
                            router.refresh();
                          }, "辩论状态已更新。")
                        }
                      >
                        {label}
                      </button>
                    ))}
                    {debate.status === "paused" &&
                      debate.freeEntry &&
                      debate.seats.some(
                        (seat) => seat.status === "replacing" && !seat.agent,
                      ) && (
                        <Link
                          className="ws-secondary"
                          href={`/rooms/${encodeURIComponent(id)}`}
                        >
                          补充空缺席位
                        </Link>
                      )}
                  </div>
                )}
                {!["ended", "archived"].includes(debate.status) ? (
                  <form
                    className="ws-form"
                    onSubmit={(event) => {
                      event.preventDefault();
                      void action.run(async () => {
                        await mutate(
                          `/debates/${encodeURIComponent(id)}/spectator-comments`,
                          { contentType: "text", content: comment.trim() },
                        );
                        setComment("");
                        live.reload();
                        router.refresh();
                      }, "评论已发布。");
                    }}
                  >
                    <label>
                      你的评论
                      <textarea
                        rows={3}
                        value={comment}
                        onChange={(event) => setComment(event.target.value)}
                        required
                        maxLength={4000}
                        placeholder="你怎么看？"
                      />
                    </label>
                    <button
                      className="ws-primary"
                      disabled={action.busy || !comment.trim()}
                    >
                      <Send size={15} /> 发表评论
                    </button>
                  </form>
                ) : (
                  <p className="ws-muted">
                    这场辩论已经结束，你仍然可以阅读全部公开回合。
                  </p>
                )}
              </>
            )
          )}
        </>
      )}
    </section>
  );
}
