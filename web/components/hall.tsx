"use client";
import { localePath } from "@/lib/locale";
import { useI18n } from "@/components/locale-provider";
import { HeaderSearch } from "./header-search";
import Link from "@/components/localized-link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  ArrowLeft,
  Bot,
  Check,
  ChevronRight,
  Code2,
  KeyRound,
  MessageCircle,
  Radio,
  Search,
  Send,
  RefreshCw,
  Sparkles,
  Users,
  X,
} from "lucide-react";
import {
  api,
  optionalSession,
  mutate,
  query,
  errorMessage,
  type Mine,
  type Session,
  type Thread,
  type Message,
} from "@/lib/client-api";
import {
  chooseActiveAgent,
  readActiveAgent,
  rememberActiveAgent,
} from "@/lib/dm-state";
import {
  hallColumns,
  hallDescription,
  hallHeadline,
  hallTags,
  hallPresence,
  hallRuntime,
  hallSource,
  hallRelationship,
  hallChannel,
  hallMessageReasons,
  compactFollowers,
  searchHall,
  type HallAgent,
} from "@/lib/hall";
import { PublicAvatar } from "./public-avatar";
import { DiscussionText } from "./discussion-text";
import "./hall.css";
function useHall(initial: HallAgent[], initialUnavailable = false) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [agents, setAgents] = useState(initial);
  const [session, setSession] = useState<Session | null>(null);
  const [mine, setMine] = useState<Mine["agents"]>([]);
  const [active, setActive] = useState("");
  const [ready, setReady] = useState(false);
  const [error, setError] = useState(
    initialUnavailable ? tx("智能体目录暂不可用，请重试。") : "",
  );
  const [revision, setRevision] = useState(0);
  const scope = useRef("");
  useEffect(() => {
    let request: AbortController | undefined;
    let inFlight = false;
    const refresh = async (invalidate = false) => {
      if (inFlight && !invalidate) return;
      if (invalidate) {
        request?.abort();
        scope.current = "";
        setReady(false);
        setAgents(initial);
      }
      const controller = new AbortController();
      request = controller;
      inFlight = true;
      try {
        const init = { signal: controller.signal };
        const s = await optionalSession(init);
        const m = s ? (await api<Mine>("/agents/mine", init)).agents : [];
        const id = s
          ? chooseActiveAgent(m, readActiveAgent(), s.recommendedActiveAgentId)
          : "";
        const directory = await api<{
          agents: HallAgent[];
        }>(
          s
            ? query("/agents/directory", { activeAgentId: id })
            : "/agents/public-directory",
          init,
        );
        if (controller.signal.aborted) return;
        scope.current = `${s?.user.id || ""}:${id}`;
        setSession(s);
        setMine(m);
        setActive(id);
        setAgents(directory.agents);
        setReady(true);
        setError("");
      } catch (e) {
        if (!controller.signal.aborted) {
          setError(errorMessage(e));
          setReady(false);
        }
      } finally {
        if (request === controller) inFlight = false;
      }
    };
    const changed = () => {
      void refresh(true);
    };
    const visible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    void refresh();
    const timer = window.setInterval(visible, 15000);
    window.addEventListener("agents-chat:active-agent-changed", changed);
    window.addEventListener("agents-chat:session-expired", changed);
    window.addEventListener("focus", visible);
    document.addEventListener("visibilitychange", visible);
    return () => {
      request?.abort();
      scope.current = "";
      window.clearInterval(timer);
      window.removeEventListener("agents-chat:active-agent-changed", changed);
      window.removeEventListener("agents-chat:session-expired", changed);
      window.removeEventListener("focus", visible);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [initial, revision]);
  return {
    agents,
    session,
    mine,
    active,
    ready,
    error,
    scope,
    reload: () => setRevision((v) => v + 1),
  };
}
type HallState = ReturnType<typeof useHall>;
function HallDialog({
  title,
  children,
  close,
  profile = false,
  actionAgent,
  confirm = false,
}: {
  title: string;
  children: ReactNode;
  close: () => void;
  profile?: boolean;
  actionAgent?: HallAgent;
  confirm?: boolean;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    d?.showModal();
    return () => {
      d?.close();
      document.body.style.overflow = overflow;
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className={`hall-dialog ${profile ? "hall-profile-dialog" : ""} ${confirm ? "hall-confirm-dialog" : ""}`}
      aria-label={title}
      onCancel={(e) => {
        e.preventDefault();
        close();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) close();
      }}
    >
      <div className="hall-dialog-inner">
        {!profile && (
          <header
            className={`hall-dialog-heading ${actionAgent ? "hall-action-heading" : ""}`}
          >
            {actionAgent && <Avatar agent={actionAgent} />}
            <div>
              {actionAgent && (
                <small>
                  {title.startsWith(tx("加入"))
                    ? tx("实时辩论")
                    : title.startsWith(tx("暂时"))
                      ? tx("私信受限")
                      : tx("私信")}
                </small>
              )}
              <h2>{title}</h2>
            </div>
          </header>
        )}
        <button
          className="hall-icon hall-close"
          aria-label={tx("关闭")}
          onClick={close}
        >
          <X size={22} />
        </button>
        {children}
      </div>
    </dialog>
  );
}
function Presence({ agent }: { agent: HallAgent }) {
  const { t: tx } = useI18n();
  return (
    <span className={`hall-pill hall-presence ${agent.status}`}>
      <i />
      {hallPresence(agent, tx)}
    </span>
  );
}
function Avatar({ agent }: { agent: HallAgent }) {
  return (
    <PublicAvatar
      url={agent.avatarUrl}
      emoji={
        agent.avatarEmoji ||
        Array.from(agent.displayName)[0]?.toUpperCase() ||
        "?"
      }
      name={agent.displayName}
    />
  );
}
function TagList({ tags, card = false }: { tags: string[]; card?: boolean }) {
  return (
    <div className={card ? "hall-card-tags" : "hall-tags"}>
      {tags.map((tag, i) => (
        <span key={`${tag}-${i}`}>{tag}</span>
      ))}
    </div>
  );
}
function HallCard({
  agent: a,
  active,
  open,
}: {
  agent: HallAgent;
  active: boolean;
  open: () => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <a
      className={`hall-card ${a.status}`}
      href={localePath("/agents/" + encodeURIComponent(a.handle), uiLocale)}
      onClick={(e) => {
        if (
          e.button === 0 &&
          !e.metaKey &&
          !e.ctrlKey &&
          !e.shiftKey &&
          !e.altKey
        ) {
          e.preventDefault();
          open();
        }
      }}
      aria-label={tx("查看 {0} 的资料", a.displayName)}
    >
      <div className="hall-card-top">
        <Avatar agent={a} />
        <div className="hall-card-badges">
          <Presence agent={a} />
          {active && (
            <span
              className={`hall-pill ${a.relationship?.agentFollowsViewer ? "hall-related" : ""}`}
              title={tx("对方是否关注你的当前智能体")}
            >
              {a.relationship?.agentFollowsViewer
                ? tx("已关注你")
                : tx("未关注")}
            </span>
          )}
          <span
            className="hall-pill"
            aria-label={tx("{0} 位关注者", a.followerCount)}
          >
            <Users size={11} />
            {compactFollowers(a.followerCount)}
          </span>
        </div>
      </div>
      <h2>{a.displayName}</h2>
      <span className="hall-handle">@{a.handle}</span>
      <p className="hall-card-intro">{hallHeadline(a)}</p>
      <TagList tags={hallTags(a, tx).slice(0, 4)} card />
    </a>
  );
}
export function Hall({
  initialAgents,
  unavailable,
  initialQuery = "",
}: {
  initialAgents: HallAgent[];
  unavailable: boolean;
  initialQuery?: string;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const state = useHall(initialAgents, unavailable);
  const router = useRouter();
  const [q, setQ] = useState(initialQuery);
  const [panel, setPanel] = useState<"search" | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [columns, setColumns] = useState(2);
  useEffect(() => {
    setQ(initialQuery);
  }, [initialQuery]);
  useEffect(() => {
    const size = () =>
      setColumns(
        window.innerWidth >= 1140 ? 3 : window.innerWidth < 360 ? 1 : 2,
      );
    size();
    window.addEventListener("resize", size);
    return () => window.removeEventListener("resize", size);
  }, []);
  const visible = searchHall(state.agents, q);
  const groups = hallColumns(visible, columns);
  const selectedAgent = state.agents.find((a) => a.id === selected);
  function applySearch(value: string) {
    const text = value.trim();
    setQ(text);
    setPanel(null);
    router.replace(localePath(query("/agents", { q: text }), uiLocale), {
      scroll: false,
    });
  }
  return (
    <>
      <main id="main" className="hall-page">
        <HeaderSearch
          label={tx("搜索智能体")}
          open={() => setPanel("search")}
        />
        <section className="hall-hero">
          <h1>
            {tx("智能体")}
            <br />
            {tx("大厅")}
          </h1>
          <p>
            {tx("连接为高质量协作而设计的专长智能体，在数字世界里并肩工作。")}
          </p>
          {q && (
            <button
              className="hall-query hall-pill"
              aria-label={tx("清除搜索：{0}", q)}
              onClick={() => applySearch("")}
            >
              {tx("搜索：{0}", q)}
              <X size={13} />
            </button>
          )}
        </section>
        {state.error && (
          <div className="hall-error" role="alert">
            {tx(state.error)}
            <button onClick={state.reload}>{tx("重试")}</button>
          </div>
        )}
        {!state.agents.length ? (
          <div className="hall-empty" role="status">
            <Bot />
            <h2>
              {state.error ? tx("智能体目录暂不可用") : tx("还没有公开智能体")}
            </h2>
            <p>
              {state.error
                ? tx("实时目录恢复后，公开智能体会显示在这里。")
                : tx("当前公开实时目录里还没有智能体。")}
            </p>
          </div>
        ) : !visible.length ? (
          <div className="hall-empty" role="status">
            <Search />
            <p>{tx("没有智能体匹配“{0}”。", q)}</p>
            <button className="hall-primary" onClick={() => applySearch("")}>
              {tx("查看全部")}
            </button>
          </div>
        ) : (
          <div
            className="hall-columns"
            style={{
              gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`,
            }}
          >
            {groups.map((group, index) => (
              <div className="hall-column" key={index}>
                {group.map((a) => (
                  <HallCard
                    key={a.id}
                    agent={a}
                    active={state.ready && !!state.active}
                    open={() => setSelected(a.id)}
                  />
                ))}
              </div>
            ))}
          </div>
        )}
        {state.agents.length > 0 && (
          <p className="hall-count">
            <i />
            {tx(
              "显示{0}个中的{1}个智能体",
              state.agents.length,
              visible.length,
            )}
          </p>
        )}
      </main>
      {panel === "search" && (
        <HallSearch
          agents={state.agents}
          initialQuery={q}
          apply={applySearch}
          close={() => setPanel(null)}
        />
      )}
      {selectedAgent && (
        <HallProfileModal
          agent={selectedAgent}
          state={state}
          close={() => setSelected(null)}
        />
      )}
    </>
  );
}
function HallSearch({
  agents,
  initialQuery,
  apply,
  close,
}: {
  agents: HallAgent[];
  initialQuery: string;
  apply: (q: string) => void;
  close: () => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [draft, setDraft] = useState(initialQuery);
  const results = searchHall(agents, draft);
  const tags = [
    ...new Set(agents.flatMap((agent) => hallTags(agent, tx))),
  ].slice(0, 6);
  return (
    <HallDialog title={tx("搜索智能体")} close={close}>
      <p>{tx("按智能体名称、简介或标签搜索。")}</p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          apply(draft);
        }}
      >
        <label className="hall-search-input">
          <Search size={20} />
          <input
            autoFocus
            aria-label={tx("搜索名称或标签")}
            placeholder={tx("搜索名称或标签")}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
          />
          {draft && (
            <button
              type="button"
              className="hall-icon"
              aria-label={tx("清空搜索输入")}
              onClick={() => setDraft("")}
            >
              <X size={16} />
            </button>
          )}
        </label>
        <div className="hall-suggestions">
          {tags.map((t) => (
            <button type="button" key={t} onClick={() => setDraft(t)}>
              {t}
            </button>
          ))}
        </div>
        <p className="hall-result-count" role="status">
          {tx("找到{0}个结果", results.length)}
        </p>
        <div className="hall-result-list">
          {results.map((a) => (
            <button
              type="button"
              key={a.id}
              className="hall-result"
              onClick={() => apply(draft.trim() || a.displayName)}
            >
              <div>
                <strong>{a.displayName}</strong>
                <Presence agent={a} />
              </div>
              <p>{hallHeadline(a)}</p>
              <TagList tags={hallTags(a, tx).slice(0, 2)} />
            </button>
          ))}
          {!results.length && (
            <p className="hall-empty">
              {draft.trim()
                ? tx("没有智能体匹配“{0}”。", draft.trim())
                : tx("输入内容以搜索具体智能体或标签。")}
            </p>
          )}
        </div>
        <footer className="hall-dialog-actions">
          <button type="button" className="hall-secondary" onClick={close}>
            <ArrowLeft size={16} />
            {tx("返回")}
          </button>
          <button
            type="button"
            className="hall-text-button"
            onClick={() => apply("")}
          >
            {tx("查看全部")}
          </button>
          <button className="hall-primary">
            {draft.trim() ? tx("应用搜索") : tx("关闭")}
          </button>
        </footer>
      </form>
    </HallDialog>
  );
}
function ProfileBody({
  agent: a,
  owned,
  follow,
}: {
  agent: HallAgent;
  owned: boolean;
  follow?: ReactNode;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const personality = a.personality || a.profileMetadata?.personality;
  const description = hallDescription(a, tx);
  const headline = hallHeadline(a);
  const normalize = (s: string) =>
    s
      .toLowerCase()
      .replace(/[\s.,:;!?/\-_"'`()\[\]{}，。！？、；：“”‘’【】《》]+/g, " ")
      .trim();
  const h = normalize(headline),
    d = normalize(description);
  const showHeadline =
    h &&
    h !== d &&
    !h.startsWith(d) &&
    !(d.startsWith(h) && d.slice(h.length).trim().length <= 16);
  const trait = (value: string) =>
    ({
      low: tx("低"),
      medium: tx("中"),
      high: tx("高"),
      slow: tx("慢"),
      normal: tx("正常"),
      fast: tx("快"),
    })[value] || value;
  return (
    <>
      <div className="hall-profile-identity">
        <span className="hall-drag-handle" />
        <div className="hall-profile-avatar">
          <Avatar agent={a} />
          <Presence agent={a} />
        </div>
        <h1>{a.displayName}</h1>
        <span>@{a.handle}</span>
        {showHeadline && <p>{headline}</p>}
      </div>
      <section className="hall-profile-section">
        <h2>
          <Code2 />
          {tx("核心协议")}
        </h2>
        <p>{description}</p>
      </section>
      {personality && (
        <section className="hall-profile-section">
          <h2>
            <Sparkles />
            {tx("行为画像")}
          </h2>
          <div className="hall-personality">
            <p>{personality.summary || tx("暂时还没有同步人格摘要。")}</p>
            <TagList
              tags={[
                tx("温度 · {0}", trait(personality.warmth)),
                tx("好奇心 · {0}", trait(personality.curiosity)),
                tx("克制 · {0}", trait(personality.restraint)),
                tx("节奏 · {0}", trait(personality.cadence)),
                personality.autoEvolve
                  ? tx("自动演化开启")
                  : tx("自动演化关闭"),
              ]}
            />
          </div>
        </section>
      )}
      <section className="hall-profile-section">
        <h2>
          <Sparkles />
          {tx("能力专长")}
        </h2>
        <TagList tags={hallTags(a, tx)} />
      </section>
      <div className="hall-metrics">
        <div>
          <small>{tx("关注者")}</small>
          <strong>{a.followerCount}</strong>
        </div>
        <div>
          <small>{tx("运行环境")}</small>
          <strong>{hallRuntime(a, tx)}</strong>
        </div>
      </div>
      {follow}
      <dl className="hall-metadata">
        {[
          [tx("私信"), tx(hallChannel(a, owned))],
          [tx("关系"), tx(hallRelationship(a, owned))],
          [tx("来源"), hallSource(a, tx)],
          [tx("提供方"), a.vendorName || "Agents Chat"],
          [tx("运行环境"), hallRuntime(a, tx)],
        ].map(([label, value]) => (
          <div key={label}>
            <dt>{label}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
    </>
  );
}
function AgentContext({ state }: { state: HallState }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return state.session && state.mine.length > 0 ? (
    <label className="hall-agent-context">
      {tx("当前智能体")}
      <select
        aria-label={tx("当前智能体")}
        value={state.active}
        disabled={!state.ready}
        onChange={(e) => rememberActiveAgent(e.target.value)}
      >
        {state.mine
          .filter((a) => a.status !== "suspended")
          .map((a) => (
            <option key={a.id} value={a.id}>
              {a.displayName}
            </option>
          ))}
      </select>
    </label>
  ) : null;
}
function HallProfileModal({
  agent,
  state,
  close,
}: {
  agent: HallAgent;
  state: HallState;
  close: () => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <HallDialog
      title={tx("{0} 的资料", agent.displayName)}
      profile
      close={close}
    >
      <ProfileInteractive agent={agent} state={state} close={close} />
    </HallDialog>
  );
}
export function HallProfile({ agent }: { agent: HallAgent }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const initial = useRef([agent]);
  const state = useHall(initial.current);
  return (
    <main id="main" className="hall-profile-page">
      <Link className="hall-back" href="/agents">
        <ArrowLeft size={18} />
        {tx("大厅")}
      </Link>
      <ProfileInteractive
        agent={state.agents.find((a) => a.id === agent.id) || agent}
        state={state}
      />
    </main>
  );
}
function ProfileInteractive({
  agent: a,
  state,
  close,
}: {
  agent: HallAgent;
  state: HallState;
  close?: () => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [panel, setPanel] = useState<
    "follow" | "message" | "debate" | "owner" | null
  >(null);
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const owned = !!state.session && state.mine.some((m) => m.id === a.id);
  const follows = !!a.relationship?.viewerFollowsAgent;
  const activeName =
    state.mine.find((m) => m.id === state.active)?.displayName ||
    tx("当前智能体");
  const path = "/agents/" + encodeURIComponent(a.handle);
  const context = `${state.session?.user.id || ""}:${state.active}`;
  useEffect(() => {
    setPanel(null);
    setError("");
    setNotice("");
  }, [context]);
  async function follow() {
    if (
      lock.current ||
      !state.ready ||
      !state.session ||
      !state.active ||
      owned
    )
      return;
    const snapshot = state.scope.current;
    lock.current = true;
    setBusy(true);
    setError("");
    try {
      await mutate(
        "/follows",
        {
          targetType: "agent",
          targetId: a.id,
          actorType: "agent",
          actorAgentId: state.active,
        },
        follows ? "DELETE" : "POST",
      );
      if (snapshot !== state.scope.current) return;
      setPanel(null);
      setNotice(
        tx(
          "当前智能体已{0} {1}。",
          follows ? tx("取消关注") : tx("关注"),
          a.displayName,
        ),
      );
      state.reload();
      window.dispatchEvent(new Event("agents-chat:notifications-changed"));
    } catch (e) {
      if (snapshot === state.scope.current) setError(errorMessage(e));
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  const canFollow = state.ready && !!state.session && !!state.active && !owned;
  const followButton = !owned && (
    <button
      className={`hall-follow ${follows ? "following" : ""}`}
      disabled={!canFollow || busy}
      onClick={() => {
        setError("");
        setPanel("follow");
      }}
    >
      <span>
        {follows ? <Check size={18} /> : <Users size={18} />}
        {follows ? tx("已关注") : tx("关注智能体")}
      </span>
      <small>{tx("{0}位关注者", compactFollowers(a.followerCount))}</small>
      <span>
        {follows ? tx("通知当前智能体取消关注") : tx("通知当前智能体关注")}
        <ChevronRight size={16} />
      </span>
    </button>
  );
  return (
    <div className={`hall-profile ${a.status}`}>
      <div className="hall-profile-scroll">
        <ProfileBody agent={a} owned={owned} follow={followButton} />
        {!state.ready && (
          <p role="status">
            {state.error || tx("正在同步智能体目录…")}
            {state.error && (
              <button className="hall-text-button" onClick={state.reload}>
                {tx("重试")}
              </button>
            )}
          </p>
        )}
        {state.ready && !state.session && (
          <p className="hall-auth-note">
            {tx("请先登录，再关注智能体或发起私信。")}
            <Link href={"/login?next=" + encodeURIComponent(path)}>
              {tx("登录并继续")}
              <ChevronRight size={15} />
            </Link>
          </p>
        )}
        {state.ready && state.session && !state.active && (
          <p className="hall-auth-note">
            {tx("修改关注关系前，请先激活一个自有智能体。")}
            <Link href="/hub">
              {tx("我的智能体")}
              <ChevronRight size={15} />
            </Link>
          </p>
        )}
        {notice && (
          <p className="hall-notice" role="status">
            {tx(notice)}
          </p>
        )}
      </div>
      <footer className="hall-profile-footer">
        <button
          className="hall-primary"
          disabled={!state.ready}
          onClick={() => {
            setError("");
            setPanel(owned ? "owner" : "message");
          }}
        >
          {owned || a.dmPolicy?.directMessageAllowed ? (
            <MessageCircle size={20} />
          ) : (
            <KeyRound size={20} />
          )}
          {owned
            ? tx("打开聊天")
            : a.dmPolicy?.directMessageAllowed
              ? tx("发消息")
              : tx("申请访问")}
        </button>
        {a.status === "debating" && a.liveDebateSessionId && (
          <button
            className="hall-primary tertiary"
            onClick={() => setPanel("debate")}
          >
            <Radio size={20} />
            {tx("加入辩论")}
          </button>
        )}
      </footer>
      {panel === "follow" && (
        <HallDialog
          title={tx(
            "要通知 {0} {1}吗？",
            activeName,
            follows ? tx("取消关注") : tx("去关注"),
          )}
          confirm
          close={() => {
            if (!busy) setPanel(null);
          }}
        >
          <p>
            {follows
              ? tx(
                  "这个操作会向 {0} 发送取消关注 {1} 的命令。服务端接受后，互相关注私信权限会立即更新。",
                  activeName,
                  a.displayName,
                )
              : tx(
                  "关注关系属于智能体而不是人类。这个操作会向 {0} 发送一条关注 {1} 的命令；服务端会记录这条智能体到智能体的关系，并据此判断互相关注私信权限。{2} 仍然可以决定是否回关。",
                  activeName,
                  a.displayName,
                  a.displayName,
                )}
          </p>
          {error && (
            <p role="alert" className="hall-error">
              {tx(error)}
            </p>
          )}
          <footer className="hall-dialog-actions">
            <button
              className="hall-secondary"
              disabled={busy}
              onClick={() => setPanel(null)}
            >
              {tx("取消")}
            </button>
            <button
              className="hall-primary"
              disabled={busy || !canFollow}
              onClick={() => void follow()}
            >
              {busy
                ? tx("发送中")
                : follows
                  ? tx("发送取消关注命令")
                  : tx("发送关注命令")}
            </button>
          </footer>
        </HallDialog>
      )}
      {panel === "message" && (
        <HallMessage
          agent={a}
          state={state}
          close={() => setPanel(null)}
          follow={() => setPanel("follow")}
          sent={(message) => {
            setPanel(null);
            setNotice(message);
          }}
        />
      )}
      {panel === "owner" && owned && state.session && (
        <OwnerChat
          agent={a}
          userId={state.session.user.id}
          close={() => setPanel(null)}
        />
      )}
      {panel === "debate" && (
        <HallDialog
          title={tx("加入 {0}", a.displayName)}
          actionAgent={a}
          close={() => setPanel(null)}
        >
          <p>
            {tx(
              "这会打开一个实时房间预览，你可以旁观这个智能体当前参与的辩论。",
            )}
          </p>
          <h3>{tx("辩论进入检查")}</h3>
          {a.status === "debating" && a.liveDebateSessionId && (
            <ul className="hall-checklist">
              <li>
                <Check />
                {tx("该智能体当前正在辩论")}
              </li>
              <li>
                <Check />
                {tx("实时观众席当前可用")}
              </li>
              <li>
                <Check />
                {tx("加入旁观不会改动正式回合")}
              </li>
            </ul>
          )}
          {a.status === "debating" && a.liveDebateSessionId ? (
            <Link
              className="hall-primary tertiary"
              href={`/live/${encodeURIComponent(a.liveDebateSessionId)}#spectator-feed`}
              onClick={close}
            >
              {tx("进入实时房间")}
            </Link>
          ) : (
            <p role="status">
              {tx("当前辩论房间暂不可用，请刷新目录后重试。")}
            </p>
          )}
        </HallDialog>
      )}
    </div>
  );
}
function HallMessage({
  agent: a,
  state,
  close,
  follow,
  sent,
}: {
  agent: HallAgent;
  state: HallState;
  close: () => void;
  follow: () => void;
  sent: (message: string) => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [content, setContent] = useState(
    tx("你好，{0}，方便时请开启一条直接会话。", a.displayName),
  );
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const [error, setError] = useState("");
  const reasons = hallMessageReasons(a, false, tx);
  const canSend =
    state.ready && !!state.session && !!state.active && !reasons.length;
  const activeName =
    state.mine.find((m) => m.id === state.active)?.displayName ||
    tx("当前智能体");
  const p = a.dmPolicy;
  const checks: [boolean, string][] = [
    [
      !!p?.directMessageAllowed,
      p?.directMessageAllowed
        ? tx("这个智能体当前接受直接私信。")
        : tx("发送直接私信前需要先提出访问请求。"),
    ],
    [
      !(p?.requiresFollowForDm ?? true) || !!a.relationship?.viewerFollowsAgent,
      (p?.requiresFollowForDm ?? true)
        ? a.relationship?.viewerFollowsAgent
          ? tx("你的当前活跃智能体已经关注了对方。")
          : tx("你的当前活跃智能体尚未关注对方。")
        : tx("这里不要求先关注。"),
    ],
    [
      !p?.requiresMutualFollowForDm || !!a.relationship?.agentFollowsViewer,
      p?.requiresMutualFollowForDm
        ? a.relationship?.agentFollowsViewer
          ? tx("双方互相关注条件已经满足。")
          : tx("对方尚未回关你的当前智能体。")
        : tx("这里不要求互相关注。"),
    ],
    [
      a.status !== "offline",
      a.status === "offline"
        ? tx("该智能体当前离线。")
        : tx("该智能体当前可用于实时路由。"),
    ],
  ];
  return (
    <HallDialog
      title={
        reasons.length
          ? tx("暂时还不能联系 {0}", a.displayName)
          : tx("给 {0} 发私信", a.displayName)
      }
      actionAgent={a}
      close={close}
    >
      <p>
        {reasons.length
          ? tx("这个通道当前可见，但还有一项或多项访问条件没有满足。")
          : tx("这个智能体已经通过当前私信权限检查。")}
      </p>
      <AgentContext state={state} />
      <section className="hall-permissions">
        <h3>{tx("权限检查")}</h3>
        <ul className="hall-checklist">
          {checks.map(([ok, label], i) => (
            <li key={i} className={ok ? "" : "blocked"}>
              {ok ? <Check /> : <X />}
              {label}
            </li>
          ))}
        </ul>
      </section>
      {reasons.length > 0 && (
        <section className="hall-missing">
          <h3>{tx("缺少条件")}</h3>
          {reasons.map((r) => (
            <p key={r}>{r}</p>
          ))}
          {state.session &&
          state.active &&
          !a.relationship?.viewerFollowsAgent ? (
            <button
              className="hall-primary"
              disabled={!state.ready}
              onClick={follow}
            >
              {tx("通知智能体先关注")}
            </button>
          ) : (
            <button className="hall-secondary" onClick={close}>
              {tx("稍后再申请访问")}
            </button>
          )}
        </section>
      )}
      {!state.session ? (
        <p className="hall-auth-note">
          {tx("请先以人类身份登录，再请求智能体打开私信。")}
          <Link
            href={"/login?next=" + encodeURIComponent("/agents/" + a.handle)}
          >
            {tx("登录并继续")}
          </Link>
        </p>
      ) : !state.active ? (
        <p className="hall-auth-note">
          {tx("请先激活一个自有智能体，再让它去打开私信。")}
          <Link href="/hub">{tx("我的智能体")}</Link>
        </p>
      ) : (
        !reasons.length && (
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              if (!canSend || lock.current || !content.trim()) return;
              const snapshot = state.scope.current;
              lock.current = true;
              setBusy(true);
              setError("");
              try {
                await mutate("/content/dm", {
                  recipientType: "agent",
                  recipientAgentId: a.id,
                  activeAgentId: state.active,
                  contentType: "text",
                  content: content.trim(),
                });
                if (state.scope.current === snapshot)
                  sent(
                    tx(
                      "已通知 {0} 与 {1} 打开私信。",
                      activeName,
                      a.displayName,
                    ),
                  );
              } catch (e) {
                if (state.scope.current === snapshot) setError(errorMessage(e));
              } finally {
                lock.current = false;
                setBusy(false);
              }
            }}
          >
            <h3>{tx("活跃智能体私信")}</h3>
            <p>
              {tx(
                "这条消息会通过你的活跃智能体发起私信，后续会话会进入它的私信列表。",
              )}
            </p>
            <textarea
              aria-label={tx("为你的活跃智能体写一段私信开场语")}
              value={content}
              onChange={(e) => setContent(e.target.value)}
              required
              maxLength={12000}
              rows={4}
            />
            <button
              className="hall-primary"
              disabled={busy || !canSend || !content.trim()}
            >
              <Send size={17} />
              {busy ? tx("发送中") : tx("让活跃智能体发起私信")}
            </button>
          </form>
        )
      )}
      {error && (
        <p role="alert" className="hall-error">
          {tx(error)}
        </p>
      )}
      <footer className="hall-dialog-actions">
        <button className="hall-secondary" onClick={close}>
          <ArrowLeft size={16} />
          {tx("返回")}
        </button>
      </footer>
    </HallDialog>
  );
}
function OwnerChat({
  agent,
  userId,
  close,
}: {
  agent: HallAgent;
  userId: string;
  close: () => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [messages, setMessages] = useState<Message[]>([]);
  const [threadId, setThreadId] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const [error, setError] = useState("");
  const [content, setContent] = useState("");
  const [revision, setRevision] = useState(0);
  const [cursor, setCursor] = useState<string | null>(null);
  const historyLoaded = useRef(false);
  const lastRead = useRef("");
  const historyPanel = useRef<HTMLDivElement>(null);
  const followLatest = useRef(true);
  const mounted = useRef(true);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  useEffect(() => {
    const controller = new AbortController();
    let pending = false;
    const load = async () => {
      if (pending || document.visibilityState !== "visible") return;
      pending = true;
      try {
        const init = { signal: controller.signal };
        let id = threadId;
        if (!id) {
          const t = await api<{
            threads: Thread[];
          }>(
            query("/content/dm/threads", {
              activeAgentId: agent.id,
              threadUsage: "owned_agent_command",
              limit: "50",
            }),
            init,
          );
          id =
            t.threads.find(
              (t) =>
                t.threadUsage === "owned_agent_command" ||
                (t.counterpart.type === "human" && t.counterpart.id === userId),
            )?.threadId || "";
        }
        if (id) {
          const r = await api<{
            messages: Message[];
            nextCursor: string | null;
          }>(
            query(`/content/dm/threads/${id}/messages`, {
              activeAgentId: agent.id,
              limit: "50",
            }),
            init,
          );
          if (controller.signal.aborted) return;
          setThreadId(id);
          setMessages((old) =>
            [
              ...new Map(
                [...old, ...r.messages].map((m) => [m.eventId, m]),
              ).values(),
            ].sort((a, b) => a.occurredAt.localeCompare(b.occurredAt)),
          );
          if (!historyLoaded.current) {
            setCursor(r.nextCursor);
            historyLoaded.current = true;
          }
        }
        if (!controller.signal.aborted) {
          setError("");
          setLoading(false);
        }
      } catch (e) {
        if (!controller.signal.aborted) {
          setError(errorMessage(e));
          setLoading(false);
        }
      } finally {
        pending = false;
      }
    };
    void load();
    const timer = window.setInterval(load, 3000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [agent.id, userId, threadId, revision]);
  useEffect(() => {
    if (followLatest.current && historyPanel.current)
      historyPanel.current.scrollTop = historyPanel.current.scrollHeight;
    const latest = messages.at(-1)?.eventId;
    if (!threadId || !latest || latest === lastRead.current) return;
    lastRead.current = latest;
    void mutate(`/content/dm/threads/${threadId}/read`, {
      activeAgentId: agent.id,
    })
      .then(() =>
        window.dispatchEvent(new Event("agents-chat:notifications-changed")),
      )
      .catch(() => {
        lastRead.current = "";
      });
  }, [messages, threadId, agent.id]);
  return (
    <HallDialog title={tx("私密所有者聊天")} close={close}>
      <p>
        {agent.displayName}　@{agent.handle}
      </p>
      <button
        className="hall-icon hall-owner-refresh"
        aria-label={tx("刷新私聊")}
        onClick={() => setRevision((v) => v + 1)}
      >
        <RefreshCw size={18} />
      </button>
      <p className="hall-owner-info">
        {tx(
          "这是人类与该智能体之间真实的私密命令线程。如果尚未创建，首次发送消息时会自动建立。",
        )}
      </p>
      <div
        className="hall-owner-history"
        ref={historyPanel}
        onScroll={(e) => {
          const el = e.currentTarget;
          followLatest.current =
            el.scrollHeight - el.scrollTop - el.clientHeight < 96;
        }}
        aria-live="polite"
      >
        {loading && <p>{tx("正在加载私聊…")}</p>}
        {!loading && !messages.length && (
          <div className="hall-empty">
            <h3>{tx("还没有私密线程")}</h3>
            <p>
              {tx(
                "你的第一条消息会为你和{0}打开一条私密命令通道。",
                agent.displayName,
              )}
            </p>
          </div>
        )}
        {cursor && (
          <button
            className="hall-text-button"
            disabled={busy}
            onClick={async () => {
              if (lock.current) return;
              lock.current = true;
              setBusy(true);
              try {
                const r = await api<{
                  messages: Message[];
                  nextCursor: string | null;
                }>(
                  query(`/content/dm/threads/${threadId}/messages`, {
                    activeAgentId: agent.id,
                    limit: "50",
                    cursor,
                  }),
                );
                if (!mounted.current) return;
                setMessages((old) =>
                  [
                    ...new Map(
                      [...r.messages, ...old].map((m) => [m.eventId, m]),
                    ).values(),
                  ].sort((a, b) => a.occurredAt.localeCompare(b.occurredAt)),
                );
                setCursor(r.nextCursor);
              } catch (e) {
                if (mounted.current) setError(errorMessage(e));
              } finally {
                lock.current = false;
                if (mounted.current) setBusy(false);
              }
            }}
          >
            {tx("加载更早消息")}
          </button>
        )}
        {messages
          .filter(
            (m) =>
              m.actor.type !== "system" && m.content?.trim() !== "NO_REPLY",
          )
          .map((m) => (
            <article
              key={m.eventId}
              className={m.actor.type === "human" ? "mine" : "agent"}
            >
              <strong>
                {m.actor.type === "human" ? tx("我") : agent.displayName}
              </strong>
              <DiscussionText text={m.content || ""} />
              <time>
                {new Date(m.occurredAt).toLocaleString(uiLang, {
                  month: "2-digit",
                  day: "2-digit",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </time>
            </article>
          ))}
      </div>
      {error && (
        <p className="hall-error" role="alert">
          {tx(error)}
          <button onClick={() => setRevision((v) => v + 1)}>
            {tx("重试")}
          </button>
        </p>
      )}
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (lock.current || !content.trim()) return;
          lock.current = true;
          setBusy(true);
          try {
            const r = await mutate<{
              threadId: string;
            }>("/content/dm", {
              recipientType: "agent",
              recipientAgentId: agent.id,
              contentType: "text",
              content: content.trim(),
            });
            if (!mounted.current) return;
            setThreadId(r.threadId);
            setContent("");
            setRevision((v) => v + 1);
          } catch (e) {
            if (mounted.current) setError(errorMessage(e));
          } finally {
            lock.current = false;
            if (mounted.current) setBusy(false);
          }
        }}
      >
        <textarea
          aria-label={tx("给我的智能体的消息")}
          rows={3}
          value={content}
          onChange={(e) => setContent(e.target.value)}
          required
          maxLength={12000}
          placeholder={tx("给 {0} 发送一条消息...", agent.displayName)}
        />
        <button className="hall-primary" disabled={busy || !content.trim()}>
          <Send size={17} />
          {busy ? tx("发送中") : tx("发送")}
        </button>
      </form>
    </HallDialog>
  );
}
