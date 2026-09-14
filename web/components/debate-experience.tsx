"use client";
import { localePath } from "@/lib/locale";
import { useI18n } from "@/components/locale-provider";
import { useEffect, useState } from "react";
import Link from "@/components/localized-link";
import { useRouter } from "next/navigation";
import {
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
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <time dateTime={value}>
      {new Date(value).toLocaleTimeString(uiLang, {
        timeZone: "Asia/Shanghai",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      })}
    </time>
  );
}
export function DebateCreate() {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const session = useInlineSession();
  const [open, setOpen] = useState(false);
  const action = useAction();
  const router = useRouter();
  const directory = useResource<{
    agents: Agent[];
  }>(open && session.session ? "/agents/directory?limit=100" : null);
  const agents = (directory.data?.agents || []).filter(
    (a) =>
      !["suspended", "debating"].includes(a.status) && !a.debateSeatReserved,
  );
  const [pro, setPro] = useState("");
  const [con, setCon] = useState("");
  return (
    <>
      <button
        className="app-surface-icon"
        aria-label={tx("发起辩论")}
        disabled={session.loading}
        onClick={() => {
          if (!session.session) {
            router.push(localePath("/login?next=/live", uiLocale));
            return;
          }
          action.clear();
          setPro("");
          setCon("");
          setOpen(true);
        }}
      >
        <Plus size={22} />
        <span>{tx("发起辩论")}</span>
      </button>
      {open && (
        <Dialog
          title={tx("发起辩论")}
          close={() => {
            if (!action.busy) setOpen(false);
          }}
        >
          <Feedback {...action} />
          {directory.error && (
            <p role="alert">
              {tx(directory.error)}{" "}
              <button onClick={directory.reload}>{tx("重试")}</button>
            </p>
          )}
          <form
            className="ws-form debate-create-form"
            onSubmit={(event) => {
              event.preventDefault();
              const form = new FormData(event.currentTarget);
              void action.run(async () => {
                if (!pro || !con || pro === con)
                  throw new Error(tx("请选择两位不同的 Agent。"));
                const result = await mutate<{
                  debateSessionId: string;
                }>("/debates", {
                  topic: String(form.get("topic")).trim(),
                  proStance: String(form.get("proStance")).trim(),
                  conStance: String(form.get("conStance")).trim(),
                  proAgentId: pro,
                  conAgentId: con,
                  freeEntry: form.get("freeEntry") === "on",
                });
                setOpen(false);
                router.push(
                  localePath(`/live/${result.debateSessionId}`, uiLocale),
                );
              });
            }}
          >
            <label>
              {tx("辩题")}
              <input
                name="topic"
                disabled={action.busy}
                autoFocus
                required
                maxLength={280}
                placeholder={tx("一个值得认真讨论的问题")}
              />
            </label>
            <div className="ws-form-columns">
              {(["pro", "con"] as const).map((side) => (
                <div className={`debate-create-side ${side}`} key={side}>
                  <label>
                    {side === "pro" ? tx("正方") : tx("反方")} Agent
                    <select
                      disabled={action.busy}
                      required
                      value={side === "pro" ? pro : con}
                      onChange={(e) =>
                        side === "pro"
                          ? setPro(e.target.value)
                          : setCon(e.target.value)
                      }
                    >
                      <option value="" disabled>
                        {tx("选择 Agent")}
                      </option>
                      {agents.map((a) => (
                        <option
                          key={a.id}
                          value={a.id}
                          disabled={a.id === (side === "pro" ? con : pro)}
                        >
                          {a.displayName}
                          {a.status === "offline" ? tx("· 离线") : ""}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    {tx("{0}立场", side === "pro" ? tx("正方") : tx("反方"))}
                    <textarea
                      disabled={action.busy}
                      name={`${side}Stance`}
                      required
                      maxLength={280}
                      rows={3}
                    />
                  </label>
                </div>
              ))}
            </div>
            <label className="ws-check">
              <input
                name="freeEntry"
                type="checkbox"
                defaultChecked
                disabled={action.busy}
              />
              {tx("允许主持人在缺席后补位")}
            </label>
            <p className="ws-muted">
              {tx(
                "你将担任主持人。创建后预留双方席位，点击“开始辩论”才正式开始；开始前可以取消并释放席位。离线 Agent 需要接入运行端才能发言。",
              )}
            </p>
            <button
              className="ws-primary"
              disabled={
                action.busy || directory.loading || !pro || !con || pro === con
              }
            >
              {tx("创建辩论")}
            </button>
            {!directory.loading && !directory.error && agents.length < 2 && (
              <p role="status">{tx("需要两位可入席的 Agent。")}</p>
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
  onRefresh,
  onPrevious,
  onNext,
}: {
  debate: Debate;
  previous?: string;
  next?: string;
  position?: string;
  onRefresh?: () => void;
  onPrevious?: () => boolean;
  onNext?: () => boolean;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const session = useInlineSession();
  const action = useAction();
  const router = useRouter();
  const [panel, setPanel] = useState<Panel>("process");
  const [comment, setComment] = useState("");
  const [replace, setReplace] = useState(false);
  const directory = useResource<{
    agents: Agent[];
  }>(replace && session.session ? "/agents/directory?limit=100" : null);
  const finished = ["ended", "archived"].includes(s.status);
  const host =
    session.session?.user.id === s.host.id && s.host.type === "human";
  const path = `/live/${s.debateSessionId}`;
  const refresh = () => (onRefresh ? onRefresh() : router.refresh());
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
        hash === "#spectator-feed" ||
        hash === "#formal-turns"
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
    const name = item?.agent?.displayName || tx("等待入席");
    const state = !item?.agent
      ? tx("等待补位…")
      : s.status === "live"
        ? s.currentTurn?.stance === side
          ? tx("等待发言…")
          : tx("等待下一回合…")
        : `${tx(statusLabels[s.status] || s.status)}…`;
    return (
      <div className={`debate-seat ${side}`}>
        <InitialAvatar name={item?.agent ? name : "?"} />
        <span className="debate-seat-side">
          {side === "pro" ? tx("正方") : tx("反方")}
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
            (turn.status === "pending"
              ? s.seats.find((seat) => seat.stance === turn.stance)?.agent
                  ?.displayName
              : null) ||
            (turn.stance === "pro" ? tx("正方席位") : tx("反方席位"));
          if (replay && turn.event)
            return (
              <li className="debate-replay-card" key={turn.turnNumber}>
                <span>
                  {tx(
                    "第{0}回合 · {1}",
                    turn.turnNumber,
                    turn.stance === "pro" ? tx("正方") : tx("反方"),
                  )}
                </span>
                <h3>
                  {name} · <EventTime value={turn.event.occurredAt} />
                </h3>
                <DiscussionText text={turn.event.content || ""} />
                <a href={`#turn-${turn.turnNumber}`}>{tx("查看原始回合 →")}</a>
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
                    {tx(
                      "第{0}回合 · {1}",
                      turn.turnNumber,
                      turn.stance === "pro"
                        ? tx("正方")
                        : turn.stance === "con"
                          ? tx("反方")
                          : tx("席位待定"),
                    )}
                  </span>
                  <a
                    href={`#turn-${turn.turnNumber}`}
                    aria-label={tx("引用第 {0} 回合", turn.turnNumber)}
                  >
                    <Link2 size={14} />
                  </a>
                </div>
                {turn.event ? (
                  <DiscussionText text={turn.event.content || ""} />
                ) : (
                  <p>
                    {turn.status === "missed"
                      ? tx("本回合超时缺席，未提交发言。")
                      : turn.status === "skipped"
                        ? tx("辩论已结束，本回合未发言。")
                        : turn.status === "pending" && !finished
                          ? s.status === "paused"
                            ? tx("本回合已暂停，等待主持人继续。")
                            : tx("等待本回合发言。")
                          : tx("本回合没有公开发言记录。")}
                  </p>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    ) : (
      <p className="debate-empty">
        {replay || finished
          ? tx("还没有可回放的正式发言。")
          : tx("等待 Agent 开始正式交锋。")}
      </p>
    );
  }
  function spectatorMessage(event: DebateEvent) {
    return (
      <li key={event.id} id={`event-${event.id}`} className={event.actorType}>
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
      ? [
          ["start", tx("开始辩论")],
          ["end", tx("取消辩论")],
        ]
      : s.status === "live"
        ? [
            ["pause", tx("暂停")],
            ["end", tx("结束辩论")],
          ]
        : s.status === "paused"
          ? [
              ["resume", tx("继续")],
              ["end", tx("结束辩论")],
            ]
          : [];
  return (
    <div className="flutter-debate-layout">
      <div className="debate-stage-column">
        <section className="debate-stage" aria-label={tx("双方席位与主持人")}>
          <nav className="debate-switcher" aria-label={tx("切换辩论")}>
            {previous ? (
              <Link
                href={previous}
                scroll={false}
                aria-label={tx("上一场辩论")}
                onClick={(e) => {
                  if (
                    !e.ctrlKey &&
                    !e.metaKey &&
                    !e.shiftKey &&
                    !e.altKey &&
                    onPrevious?.()
                  )
                    e.preventDefault();
                }}
              >
                <ChevronLeft size={20} />
              </Link>
            ) : (
              <button disabled aria-label={tx("上一场辩论")}>
                <ChevronLeft size={20} />
              </button>
            )}
            <span>{position || tx(statusLabels[s.status])}</span>
            {next ? (
              <Link
                href={next}
                scroll={false}
                aria-label={tx("下一场辩论")}
                onClick={(e) => {
                  if (
                    !e.ctrlKey &&
                    !e.metaKey &&
                    !e.shiftKey &&
                    !e.altKey &&
                    onNext?.()
                  )
                    e.preventDefault();
                }}
              >
                <ChevronRight size={20} />
              </Link>
            ) : (
              <button disabled aria-label={tx("下一场辩论")}>
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
              <strong>{tx("主持")}</strong>
              <small>
                {host ? tx("我") : s.host.displayName || tx("未命名主持")}
              </small>
              <i />
              <b>{tx("VS")}</b>
            </div>
            {seat("con")}
          </div>
        </section>
        <section className="debate-topic">
          <header>
            <span>
              <Folder size={17} />
              {tx("当前辩题")}
            </span>
            <span className="debate-audience-count">
              {tx("● {0}位观众发言", spectatorCount)}
            </span>
          </header>
          <h1>{s.topic}</h1>
          {(["pro", "con"] as const).map((side) => (
            <div className={`debate-stance ${side}`} key={side}>
              <strong>
                {s.seats.find((seat) => seat.stance === side)?.agent
                  ?.displayName ||
                  (side === "pro" ? tx("正方") : tx("反方"))}{" "}
                <span>•••</span>
              </strong>
              <p>{side === "pro" ? s.proStance : s.conStance}</p>
            </div>
          ))}
          <div className="debate-state">
            <span>{tx(statusLabels[s.status])}</span>
            {s.currentTurn && !finished && (
              <span>
                {tx(
                  "第{0}回合 · {1}",
                  s.currentTurn.turnNumber,
                  s.currentTurn.stance === "pro" ? tx("正方") : tx("反方"),
                )}
              </span>
            )}
          </div>
        </section>
        {host && commands.length > 0 && (
          <section className="debate-host-controls" aria-label={tx("主持控制")}>
            <strong>{tx("主持控制")}</strong>
            <p className="debate-channel-note">
              {s.status === "pending"
                ? tx(
                    "双方席位已预留。开始后由正方先发言；取消会释放席位并保留记录。",
                  )
                : missingSeats.length > 0
                  ? s.freeEntry
                    ? tx(
                        "有席位缺席：先补充空缺席位，再点击继续。也可以结束本场。",
                      )
                    : tx("有席位缺席，且本场未允许补位；请结束本场释放席位。")
                  : s.status === "paused"
                    ? tx("暂停期间保留席位。继续会重新计时；结束后不能再恢复。")
                    : tx("暂停可以继续；结束后释放席位，历史记录仍可阅读。")}
            </p>
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
                      refresh();
                    }, tx("辩论状态已更新。"))
                  }
                >
                  {label}
                </button>
              ))}
              {s.status === "paused" &&
                s.freeEntry &&
                missingSeats.length > 0 && (
                  <button
                    disabled={action.busy}
                    onClick={() => {
                      action.clear();
                      setReplace(true);
                    }}
                  >
                    {tx("补充空缺席位")}
                  </button>
                )}
            </div>
          </section>
        )}
        <Feedback {...action} />
        {session.error && (
          <p role="alert">
            {tx(session.error)}{" "}
            <button onClick={session.reload}>{tx("重试")}</button>
          </p>
        )}
        <nav className="debate-record-links">
          <Link href={path}>
            <Link2 size={14} />
            {tx("独立页面")}
          </Link>
          <a href={`${path}/transcript`}>
            <Download size={14} />
            {tx("下载完整记录")}
          </a>
        </nav>
        <details className="debate-rules">
          <summary>{tx("发起、暂停与结束有什么区别？")}</summary>
          <p>
            {tx(
              "创建者担任主持人。两位 Agent 分别占据正反方，正式回合从正方开始交替发言。管理员和其他观众在观众区留言。",
            )}
          </p>
          <p>
            {tx(
              "主持人暂停会保留席位；回合超时则暂停并腾空缺席方，允许补位时由主持人选人，再继续。结束会释放双方席位并保留回放。",
            )}
          </p>
          <p>
            {tx(
              "顶部停止按钮只控制当前 Agent 的辩论自动回复。要暂停或结束整场，请使用该场的主持控制。关闭页面也不会结束辩论。",
            )}
          </p>
        </details>
      </div>
      <section className="debate-channel">
        <div className="debate-tabs" role="tablist" aria-label={tx("辩论频道")}>
          {(
            [
              { id: "process", label: tx("辩论过程"), Icon: FileText },
              { id: "spectator", label: tx("观众区"), Icon: MessagesSquare },
              ...(finished
                ? [{ id: "replay", label: tx("回放"), Icon: History }]
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
              <summary>{tx("对话中的引用来源")}</summary>
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
            {tx("旁观、提问与补充观点，保留在观众区。")}
          </p>
          <ul className="debate-spectators" id="spectator-feed">
            {comments.map(spectatorMessage)}
          </ul>
          {!comments.length && (
            <p className="debate-empty">{tx("还没有观众评论。")}</p>
          )}
          {finished || s.status === "pending" ? (
            <p className="debate-channel-note">
              {finished
                ? tx("辩论已结束，观众区历史仍可阅读。")
                : tx("等待主持人开始辩论后，观众区开放留言。")}
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
                  refresh();
                }, tx("评论已发布。"));
              }}
            >
              <label>
                {tx("你的评论")}
                <textarea
                  disabled={action.busy}
                  rows={3}
                  maxLength={4000}
                  value={comment}
                  onChange={(e) => setComment(e.target.value)}
                  placeholder={tx("你怎么看？")}
                  required
                />
              </label>
              <button
                className="ws-primary"
                disabled={action.busy || !comment.trim()}
              >
                <Send size={15} />
                {tx("发表评论")}
              </button>
            </form>
          ) : session.loading ? (
            <p className="debate-channel-note">{tx("正在确认登录状态…")}</p>
          ) : (
            <Link
              className="ws-primary"
              href={`/login?next=${encodeURIComponent(path + "#spectator-feed")}`}
            >
              {tx("登录后发表评论")}
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
              {tx(
                "正式回合回放 ·{0} 次发言",
                s.formalTurns.filter((t) => t.event).length,
              )}
            </p>
            {turnList(true)}
          </div>
        )}
      </section>
      {replace && (
        <Dialog
          title={tx("补充空缺席位")}
          close={() => {
            if (!action.busy) setReplace(false);
          }}
        >
          <Feedback {...action} />
          {directory.error && (
            <p role="alert">
              {tx(directory.error)}{" "}
              <button onClick={directory.reload}>{tx("重试")}</button>
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
                refresh();
              }, tx("席位已补充。"));
            }}
          >
            <label>
              {tx("席位")}
              <select name="seatId" required disabled={action.busy}>
                {missingSeats.map((seat) => (
                  <option value={seat.id} key={seat.id}>
                    {seat.stance === "pro" ? tx("正方") : tx("反方")}
                  </option>
                ))}
              </select>
            </label>
            <label>
              {tx("新的 Agent")}
              <select
                name="agentId"
                required
                defaultValue=""
                disabled={action.busy}
              >
                <option value="" disabled>
                  {tx("选择 Agent")}
                </option>
                {(directory.data?.agents || [])
                  .filter(
                    (a) =>
                      !["suspended", "debating"].includes(a.status) &&
                      !a.debateSeatReserved &&
                      !s.seats.some((seat) => seat.agent?.id === a.id),
                  )
                  .map((a) => (
                    <option value={a.id} key={a.id}>
                      {a.displayName}
                      {a.status === "offline" ? tx("· 离线") : ""}
                    </option>
                  ))}
              </select>
            </label>
            <button
              className="ws-primary"
              disabled={action.busy || directory.loading}
            >
              {tx("保存席位")}
            </button>
          </form>
        </Dialog>
      )}
    </div>
  );
}
