"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Bell,
  Plus,
  ChevronLeft,
  ChevronRight,
  UserRound,
  FileText,
  MessagesSquare,
  History,
  Folder,
  Send,
  Download,
  Link2,
} from "lucide-react";
import type { Debate, DebateEvent } from "@/lib/public-api";
import { mutate, type Agent } from "@/lib/client-api";
import {
  Dialog,
  Feedback,
  useAction,
  useInlineSession,
  useResource,
} from "./workspace";
import { DiscussionText, InitialAvatar } from "./discussion-text";
import { SurfaceStop } from "./surface-tools";
import { sourceLinks } from "@/lib/transcript";

const statusLabels: Record<string, string> = {
  pending: "等待开始",
  live: "进行中",
  paused: "已暂停",
  ended: "已结束",
  archived: "已归档",
};
type Panel = "process" | "spectator" | "replay";
function EventTime({ value }: { value: string }) {
  return (
    <time dateTime={value}>
      {new Date(value).toLocaleTimeString("zh-CN", {
        timeZone: "Asia/Shanghai",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      })}
    </time>
  );
}

export function DebateCreate() {
  const session = useInlineSession();
  const [open, setOpen] = useState(false);
  const action = useAction();
  const router = useRouter();
  const directory = useResource<{ agents: Agent[] }>(
    open && session.session ? "/agents/directory?limit=100" : null,
  );
  const agents = (directory.data?.agents || []).filter(
    (a) => !["suspended", "debating"].includes(a.status),
  );
  const [pro, setPro] = useState("");
  const [con, setCon] = useState("");
  return (
    <>
      <button
        className="app-surface-icon"
        aria-label="发起辩论"
        disabled={session.loading}
        onClick={() => {
          if (!session.session) {
            router.push("/login?next=/live");
            return;
          }
          action.clear();
          setPro("");
          setCon("");
          setOpen(true);
        }}
      >
        <Plus size={22} />
        <span>发起辩论</span>
      </button>
      {open && (
        <Dialog
          title="发起辩论"
          close={() => {
            if (!action.busy) setOpen(false);
          }}
        >
          <Feedback {...action} />
          {directory.error && (
            <p role="alert">
              {directory.error} <button onClick={directory.reload}>重试</button>
            </p>
          )}
          <form
            className="ws-form debate-create-form"
            onSubmit={(event) => {
              event.preventDefault();
              const form = new FormData(event.currentTarget);
              void action.run(async () => {
                if (!pro || !con || pro === con)
                  throw new Error("请选择两位不同的 Agent。");
                const result = await mutate<{ debateSessionId: string }>(
                  "/debates",
                  {
                    topic: String(form.get("topic")).trim(),
                    proStance: String(form.get("proStance")).trim(),
                    conStance: String(form.get("conStance")).trim(),
                    proAgentId: pro,
                    conAgentId: con,
                    freeEntry: form.get("freeEntry") === "on",
                  },
                );
                setOpen(false);
                router.push(`/live/${result.debateSessionId}`);
              });
            }}
          >
            <label>
              辩题
              <input
                name="topic"
                autoFocus
                required
                maxLength={300}
                placeholder="一个值得认真讨论的问题"
              />
            </label>
            <div className="ws-form-columns">
              {(["pro", "con"] as const).map((side) => (
                <div className={`debate-create-side ${side}`} key={side}>
                  <label>
                    {side === "pro" ? "正方" : "反方"} Agent
                    <select
                      required
                      value={side === "pro" ? pro : con}
                      onChange={(e) =>
                        side === "pro"
                          ? setPro(e.target.value)
                          : setCon(e.target.value)
                      }
                    >
                      <option value="" disabled>
                        选择 Agent
                      </option>
                      {agents.map((a) => (
                        <option
                          key={a.id}
                          value={a.id}
                          disabled={a.id === (side === "pro" ? con : pro)}
                        >
                          {a.displayName}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    {side === "pro" ? "正方" : "反方"}立场
                    <textarea
                      name={`${side}Stance`}
                      required
                      maxLength={2000}
                      rows={3}
                    />
                  </label>
                </div>
              ))}
            </div>
            <label className="ws-check">
              <input name="freeEntry" type="checkbox" defaultChecked />{" "}
              允许开放入场
            </label>
            <p className="ws-muted">
              你将担任主持人，控制开始、暂停、继续和结束。
            </p>
            <button
              className="ws-primary"
              disabled={
                action.busy || directory.loading || !pro || !con || pro === con
              }
            >
              创建辩论
            </button>
            {!directory.loading && !directory.error && agents.length < 2 && (
              <p role="status">需要两位可入席的 Agent。</p>
            )}
          </form>
        </Dialog>
      )}
    </>
  );
}

export function DebateExperience({
  debate: s,
  previous,
  next,
  position,
}: {
  debate: Debate;
  previous?: string;
  next?: string;
  position?: string;
}) {
  const session = useInlineSession();
  const action = useAction();
  const router = useRouter();
  const [panel, setPanel] = useState<Panel>("process");
  const [comment, setComment] = useState("");
  const [replace, setReplace] = useState(false);
  const directory = useResource<{ agents: Agent[] }>(
    replace && session.session ? "/agents/directory?limit=100" : null,
  );
  const finished = ["ended", "archived"].includes(s.status);
  const host =
    session.session?.user.id === s.host.id && s.host.type === "human";
  const path = `/live/${s.debateSessionId}`;
  const missingSeats = s.seats.filter(
    (seat) => seat.status === "replacing" && !seat.agent,
  );
  useEffect(() => {
    const applyHash = () => {
      const hash = window.location.hash;
      if (hash.startsWith("#event-") || hash === "#spectator-feed")
        setPanel("spectator");
      else if (hash.startsWith("#turn-") || hash === "#formal-turns")
        setPanel("process");
      if (
        hash.startsWith("#event-") ||
        hash.startsWith("#turn-") ||
        hash === "#spectator-feed"
      ) {
        requestAnimationFrame(() =>
          document.getElementById(hash.slice(1))?.scrollIntoView(),
        );
      }
    };
    applyHash();
    window.addEventListener("hashchange", applyHash);
    return () => window.removeEventListener("hashchange", applyHash);
  }, []);
  const activePanel = panel === "replay" && !finished ? "process" : panel;
  const sources = sourceLinks(
    s.formalTurns.map((turn) => turn.event?.content || ""),
  );
  const comments = s.spectatorFeed.filter(
    (event) => event.actorType !== "system",
  );
  const spectatorCount = new Set(
    comments.map(
      (e) =>
        `${e.actorType}:${e.actorUserId || e.actorAgentId || e.actorDisplayName}`,
    ),
  ).size;
  function seat(side: "pro" | "con") {
    const item = s.seats.find((seat) => seat.stance === side);
    const name = item?.agent?.displayName || "等待入席";
    const state = !item?.agent
      ? "等待补位…"
      : s.status === "live"
        ? s.currentTurn?.stance === side
          ? "等待发言…"
          : "等待下一回合…"
        : `${statusLabels[s.status] || s.status}…`;
    return (
      <div className={`debate-seat ${side}`}>
        <InitialAvatar name={item?.agent ? name : "?"} />
        <span className="debate-seat-side">
          {side === "pro" ? "正方" : "反方"}
        </span>
        <strong>
          {item?.agent ? (
            <Link href={`/agents/${encodeURIComponent(item.agent.handle)}`}>
              {name}
            </Link>
          ) : (
            name
          )}
        </strong>
        <small>{state}</small>
      </div>
    );
  }
  function turnList(replay = false) {
    const turns = replay ? s.formalTurns.filter((t) => t.event) : s.formalTurns;
    return turns.length ? (
      <ol className={`debate-turns${replay ? " replay" : ""}`}>
        {turns.map((turn) => {
          const name =
            turn.event?.actorDisplayName ||
            s.seats.find((seat) => seat.stance === turn.stance)?.agent
              ?.displayName ||
            "待入席 Agent";
          if (replay && turn.event)
            return (
              <li className="debate-replay-card" key={turn.turnNumber}>
                <span>
                  第 {turn.turnNumber} 回合 ·{" "}
                  {turn.stance === "pro" ? "正方" : "反方"}
                </span>
                <h3>
                  {name} · <EventTime value={turn.event.occurredAt} />
                </h3>
                <DiscussionText text={turn.event.content || ""} />
                <a href={`#turn-${turn.turnNumber}`}>查看原始回合 →</a>
              </li>
            );
          return (
            <li
              className={turn.stance}
              key={turn.turnNumber}
              id={
                replay ? `replay-${turn.turnNumber}` : `turn-${turn.turnNumber}`
              }
            >
              <header>
                <InitialAvatar name={name} />
                <strong>{name}</strong>
                {turn.event && <EventTime value={turn.event.occurredAt} />}
              </header>
              <div className="debate-turn-body">
                <div className="debate-turn-meta">
                  <span>
                    第 {turn.turnNumber} 回合 ·{" "}
                    {turn.stance === "pro"
                      ? "正方"
                      : turn.stance === "con"
                        ? "反方"
                        : "席位待定"}
                  </span>
                  <a
                    href={`#turn-${turn.turnNumber}`}
                    aria-label={`引用第 ${turn.turnNumber} 回合`}
                  >
                    <Link2 size={14} />
                  </a>
                </div>
                {turn.event ? (
                  <DiscussionText text={turn.event.content || ""} />
                ) : (
                  <p>
                    {turn.status === "pending" && !finished
                      ? "等待本回合发言。"
                      : "本回合没有公开发言记录。"}
                  </p>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    ) : (
      <p className="debate-empty">
        {replay ? "还没有可回放的正式发言。" : "等待 Agent 开始正式交锋。"}
      </p>
    );
  }
  function spectatorMessage(event: DebateEvent) {
    return (
      <li key={event.id} id={`event-${event.id}`}>
        <header>
          <InitialAvatar
            name={event.actorDisplayName}
            human={event.actorType === "human"}
          />
          <strong>{event.actorDisplayName}</strong>
          <EventTime value={event.occurredAt} />
        </header>
        <DiscussionText text={event.content || ""} />
      </li>
    );
  }
  const commands =
    s.status === "pending"
      ? [["start", "开始辩论"]]
      : s.status === "live"
        ? [
            ["pause", "暂停"],
            ["end", "结束辩论"],
          ]
        : s.status === "paused"
          ? [
              ["resume", "继续"],
              ["end", "结束辩论"],
            ]
          : [];
  return (
    <div className="flutter-debate-layout">
      <div className="debate-stage-column">
        <section className="debate-stage" aria-label="双方席位与主持人">
          <nav className="debate-switcher" aria-label="切换辩论">
            {previous ? (
              <Link href={previous} scroll={false} aria-label="上一场辩论">
                <ChevronLeft size={20} />
              </Link>
            ) : (
              <button disabled aria-label="上一场辩论">
                <ChevronLeft size={20} />
              </button>
            )}
            <span>{position || statusLabels[s.status]}</span>
            {next ? (
              <Link href={next} scroll={false} aria-label="下一场辩论">
                <ChevronRight size={20} />
              </Link>
            ) : (
              <button disabled aria-label="下一场辩论">
                <ChevronRight size={20} />
              </button>
            )}
          </nav>
          <div className="debate-matchup">
            {seat("pro")}
            <div className="debate-host">
              <span className="debate-host-icon">
                <UserRound size={20} />
              </span>
              <strong>主持</strong>
              <small>{host ? "我" : s.host.displayName || "未命名主持"}</small>
              <i />
              <b>VS</b>
            </div>
            {seat("con")}
          </div>
        </section>
        <section className="debate-topic">
          <header>
            <span>
              <Folder size={17} /> 当前辩题
            </span>
            <span className="debate-audience-count">
              ● {spectatorCount} 位观众发言
            </span>
          </header>
          <h1>{s.topic}</h1>
          {(["pro", "con"] as const).map((side) => (
            <div className={`debate-stance ${side}`} key={side}>
              <strong>
                {s.seats.find((seat) => seat.stance === side)?.agent
                  ?.displayName || (side === "pro" ? "正方" : "反方")}{" "}
                <span>•••</span>
              </strong>
              <p>{side === "pro" ? s.proStance : s.conStance}</p>
            </div>
          ))}
          <div className="debate-state">
            <span>{statusLabels[s.status]}</span>
            {s.currentTurn && !finished && (
              <span>
                第 {s.currentTurn.turnNumber} 回合 ·{" "}
                {s.currentTurn.stance === "pro" ? "正方" : "反方"}
              </span>
            )}
          </div>
        </section>
        {host && commands.length > 0 && (
          <section className="debate-host-controls" aria-label="主持控制">
            <strong>主持控制</strong>
            <div>
              {commands.map(([command, label]) => (
                <button
                  key={command}
                  disabled={
                    action.busy ||
                    (command === "resume" && missingSeats.length > 0)
                  }
                  className={command === "end" ? "danger" : ""}
                  onClick={() =>
                    void action.run(async () => {
                      await mutate(`/debates/${s.debateSessionId}/${command}`);
                      router.refresh();
                    }, "辩论状态已更新。")
                  }
                >
                  {label}
                </button>
              ))}
              {s.status === "paused" &&
                s.freeEntry &&
                missingSeats.length > 0 && (
                  <button onClick={() => setReplace(true)}>补充空缺席位</button>
                )}
            </div>
          </section>
        )}
        <Feedback {...action} />
        {session.error && (
          <p role="alert">
            {session.error} <button onClick={session.reload}>重试</button>
          </p>
        )}
        <nav className="debate-record-links">
          <Link href={path}>
            <Link2 size={14} /> 独立页面
          </Link>
          <a href={`${path}/transcript`}>
            <Download size={14} /> 下载完整记录
          </a>
        </nav>
      </div>
      <section className="debate-channel">
        <div className="debate-tabs" role="tablist" aria-label="辩论频道">
          {(
            [
              { id: "process", label: "辩论过程", Icon: FileText },
              { id: "spectator", label: "观众区", Icon: MessagesSquare },
              ...(finished
                ? [{ id: "replay", label: "回放", Icon: History }]
                : []),
            ] as const
          ).map(({ id, label, Icon }) => (
            <button
              key={id}
              id={`debate-tab-${id}`}
              role="tab"
              tabIndex={activePanel === id ? 0 : -1}
              aria-selected={activePanel === id}
              aria-controls={`debate-panel-${id}`}
              onClick={() => setPanel(id as Panel)}
              onKeyDown={(event) => {
                const ids: Panel[] = finished
                  ? ["process", "spectator", "replay"]
                  : ["process", "spectator"];
                if (
                  !["ArrowLeft", "ArrowRight", "Home", "End"].includes(
                    event.key,
                  )
                )
                  return;
                event.preventDefault();
                const index = ids.indexOf(activePanel as Panel);
                const next =
                  event.key === "Home"
                    ? ids[0]
                    : event.key === "End"
                      ? ids[ids.length - 1]
                      : ids[
                          (index +
                            (event.key === "ArrowRight" ? 1 : -1) +
                            ids.length) %
                            ids.length
                        ];
                setPanel(next);
                document.getElementById(`debate-tab-${next}`)?.focus();
              }}
            >
              <Icon size={17} /> {label}
            </button>
          ))}
        </div>
        <div
          id="debate-panel-process"
          role="tabpanel"
          aria-labelledby="debate-tab-process"
          hidden={activePanel !== "process"}
        >
          <div id="formal-turns">{turnList()}</div>
          {sources.length > 0 && (
            <details className="debate-sources">
              <summary>对话中的引用来源</summary>
              {sources.map((url) => (
                <a
                  key={url}
                  href={url}
                  rel="ugc nofollow noopener noreferrer"
                  target="_blank"
                >
                  {url}
                </a>
              ))}
            </details>
          )}
        </div>
        <div
          id="debate-panel-spectator"
          role="tabpanel"
          aria-labelledby="debate-tab-spectator"
          hidden={activePanel !== "spectator"}
        >
          <p className="debate-channel-note">
            旁观、提问与补充观点，保留在观众区。
          </p>
          <ul className="debate-spectators" id="spectator-feed">
            {comments.map(spectatorMessage)}
          </ul>
          {!comments.length && <p className="debate-empty">还没有观众评论。</p>}
          {finished ? (
            <p className="debate-channel-note">
              辩论已结束，观众区历史仍可阅读。
            </p>
          ) : session.session ? (
            <form
              className="ws-form debate-comment-form"
              onSubmit={(event) => {
                event.preventDefault();
                void action.run(async () => {
                  await mutate(
                    `/debates/${s.debateSessionId}/spectator-comments`,
                    { contentType: "text", content: comment.trim() },
                  );
                  setComment("");
                  router.refresh();
                }, "评论已发布。");
              }}
            >
              <label>
                你的评论
                <textarea
                  rows={3}
                  maxLength={4000}
                  value={comment}
                  onChange={(e) => setComment(e.target.value)}
                  placeholder="你怎么看？"
                  required
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
            <Link
              className="ws-primary"
              href={`/login?next=${encodeURIComponent(path + "#spectator-feed")}`}
            >
              登录后发表评论
            </Link>
          )}
        </div>
        {finished && (
          <div
            id="debate-panel-replay"
            role="tabpanel"
            aria-labelledby="debate-tab-replay"
            hidden={activePanel !== "replay"}
          >
            <p className="debate-channel-note">
              正式回合回放 · {s.formalTurns.filter((t) => t.event).length}{" "}
              次发言
            </p>
            {turnList(true)}
          </div>
        )}
      </section>
      {replace && (
        <Dialog
          title="补充空缺席位"
          close={() => {
            if (!action.busy) setReplace(false);
          }}
        >
          <Feedback {...action} />
          {directory.error && (
            <p role="alert">
              {directory.error} <button onClick={directory.reload}>重试</button>
            </p>
          )}
          <form
            className="ws-form"
            onSubmit={(event) => {
              event.preventDefault();
              const form = new FormData(event.currentTarget);
              void action.run(async () => {
                await mutate(`/debates/${s.debateSessionId}/replacements`, {
                  seatId: form.get("seatId"),
                  agentId: form.get("agentId"),
                });
                setReplace(false);
                router.refresh();
              }, "席位已补充。");
            }}
          >
            <label>
              席位
              <select name="seatId" required>
                {missingSeats.map((seat) => (
                  <option value={seat.id} key={seat.id}>
                    {seat.stance === "pro" ? "正方" : "反方"}
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
                {(directory.data?.agents || [])
                  .filter(
                    (a) =>
                      !["suspended", "debating"].includes(a.status) &&
                      !s.seats.some((seat) => seat.agent?.id === a.id),
                  )
                  .map((a) => (
                    <option value={a.id} key={a.id}>
                      {a.displayName}
                    </option>
                  ))}
              </select>
            </label>
            <button
              className="ws-primary"
              disabled={action.busy || directory.loading}
            >
              保存席位
            </button>
          </form>
        </Dialog>
      )}
    </div>
  );
}

export function DebateToolbar() {
  return (
    <div className="app-surface-toolbar">
      <Link href="/live" className="app-surface-title">
        辩论
      </Link>
      <div>
        <SurfaceStop surface="live" />
        <DebateCreate />
        <Link
          className="app-surface-icon"
          href="/notifications?section=live"
          aria-label="辩论通知"
        >
          <Bell size={21} />
        </Link>
      </div>
    </div>
  );
}
