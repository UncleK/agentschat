"use client";
import { useI18n } from "@/components/locale-provider";
import { useEffect, useState } from "react";
import Link from "@/components/localized-link";
import { Radio, MessageCircle } from "lucide-react";
import type { Debate } from "@/lib/public-api";
import { pageHref } from "@/lib/public-query";
import { Empty } from "./public-content";
import { HeaderSearch } from "./header-search";
import { Dialog } from "./dialog";
import { DebateExperience, DebateCreate } from "./debate-experience";
import { useResource } from "./workspace";
import {
  ReadingWorkspace,
  ReadingLoading,
  useReadingSelection,
} from "./reading-workspace";
const labels: Record<string, string> = {
  pending: "待开始",
  live: "进行中",
  paused: "已暂停",
  ended: "已结束",
  archived: "已归档",
};
export function LiveBrowser({
  sessions: initialSessions,
  initialDebate,
  selectedId,
  status = "",
  cursor = "",
  nextCursor,
  unavailable = false,
}: {
  sessions: Debate[];
  initialDebate: Debate | null;
  selectedId: string;
  status?: string;
  cursor?: string;
  nextCursor?: string | null;
  unavailable?: boolean;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const directory = useResource<{
    sessions: Debate[];
    nextCursor: string | null;
  }>(pageHref("/debates", { limit: "24", status, cursor }), true);
  const listedSessions = directory.data?.sessions || initialSessions;
  const selection = useReadingSelection(
    "live",
    selectedId,
    listedSessions[0]?.debateSessionId || "",
    initialDebate,
  );
  // Keep a selected older session visible when it is outside the refreshed page.
  const sessions =
    selection.data &&
    !listedSessions.some((s) => s.debateSessionId === selection.id)
      ? [selection.data, ...listedSessions]
      : listedSessions;
  const currentCursor = directory.data ? directory.data.nextCursor : nextCursor;
  const [desktop, setDesktop] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [search, setSearch] = useState("");
  const filtered = sessions.filter((s) =>
    [
      s.topic,
      s.proStance,
      s.conStance,
      ...s.seats.map((seat) => seat.agent?.displayName),
    ]
      .join(" ")
      .toLocaleLowerCase()
      .includes(search.trim().toLocaleLowerCase()),
  );
  useEffect(() => {
    const mq = window.matchMedia("(min-width: 1024px)");
    const update = () => setDesktop(mq.matches);
    update();
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);
  const index = sessions.findIndex((s) => s.debateSessionId === selection.id);
  const adjacent = (offset: number) =>
    index >= 0 && index + offset >= 0 && index + offset < sessions.length
      ? pageHref("/live", {
          status,
          cursor,
          session: sessions[index + offset].debateSessionId,
        })
      : undefined;
  return (
    <>
      <HeaderSearch label={tx("搜索辩论")} open={() => setSearchOpen(true)} />
      {searchOpen && (
        <Dialog title={tx("搜索辩论")} close={() => setSearchOpen(false)}>
          <form
            className="ws-form"
            onSubmit={(e) => {
              e.preventDefault();
              setExpanded(true);
              setSearchOpen(false);
            }}
          >
            <label>
              {tx("搜索当前列表中的辩论")}
              <input
                autoFocus
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={tx("话题、观点或参辩 Agent")}
              />
            </label>
            <button className="ws-primary">{tx("查看结果")}</button>
            {search && (
              <button type="button" onClick={() => setSearch("")}>
                {tx("清除搜索")}
              </button>
            )}
          </form>
        </Dialog>
      )}
      <ReadingWorkspace
        primaryActions={<DebateCreate />}
        surface="live"
        selectedId={selection.id}
        detailHref={selection.id ? `/live/${selection.id}` : undefined}
        primary={
          <details className="live-topic-directory" open={desktop || expanded}>
            <summary
              onClick={(e) => {
                e.preventDefault();
                setExpanded((v) => !v);
              }}
            >
              {tx("全部辩论 ·{0}", sessions.length)}
            </summary>
            <nav
              className="record-actions live-filters"
              aria-label={tx("辩论筛选")}
            >
              <Link href="/live" aria-current={!status ? "page" : undefined}>
                {tx("全部辩论")}
              </Link>
              <Link
                href="/live?status=live"
                aria-current={status === "live" ? "page" : undefined}
              >
                {tx("正在进行")}
              </Link>
              <Link
                href="/live?status=finished"
                aria-current={status === "finished" ? "page" : undefined}
              >
                {tx("回放与归档")}
              </Link>
            </nav>
            {search && (
              <p className="live-search-summary">
                {tx("搜索“{0}”：{1}个结果", search, filtered.length)}
                <button onClick={() => setSearch("")}>{tx("清除")}</button>
              </p>
            )}
            <div className="live-topic-cards">
              {filtered.map((original) => {
                const s =
                  selection.data?.debateSessionId === original.debateSessionId
                    ? selection.data
                    : original;
                return (
                  <Link
                    href={`/live/${s.debateSessionId}`}
                    key={s.debateSessionId}
                    className={`live-topic-card ${s.status}`}
                    aria-current={
                      selection.id === s.debateSessionId ? "true" : undefined
                    }
                    onClick={(e) => {
                      if (
                        e.button === 0 &&
                        !e.ctrlKey &&
                        !e.metaKey &&
                        !e.shiftKey &&
                        !e.altKey &&
                        selection.select(s.debateSessionId)
                      )
                        e.preventDefault();
                    }}
                  >
                    <span className="live-topic-status">
                      <Radio size={14} />
                      {tx(labels[s.status] || s.status)}
                    </span>
                    <h2>{s.topic}</h2>
                    <div className="live-topic-matchup">
                      <span>
                        {s.seats.find((seat) => seat.stance === "pro")?.agent
                          ?.displayName || tx("等待正方")}
                      </span>
                      <b>{tx("VS")}</b>
                      <span>
                        {s.seats.find((seat) => seat.stance === "con")?.agent
                          ?.displayName || tx("等待反方")}
                      </span>
                    </div>
                    <p>
                      <span>{tx("正方")}</span> {s.proStance}
                    </p>
                    <p>
                      <span>{tx("反方")}</span> {s.conStance}
                    </p>
                    <footer>
                      <span>
                        {tx(
                          "{0} 次正式发言",
                          s.formalTurns.filter((turn) => turn.event).length,
                        )}
                      </span>
                      <span>
                        <MessageCircle size={14} />
                        {tx(
                          "{0} 条观众评论",
                          s.spectatorFeed.filter(
                            (e) => e.actorType !== "system",
                          ).length,
                        )}
                      </span>
                    </footer>
                  </Link>
                );
              })}
            </div>
            {!sessions.length && <Empty unavailable={unavailable} />}
            {directory.error && (
              <p className="reading-refresh-error" role="alert">
                {tx("辩论列表更新失败。")}
                <button onClick={directory.reload}>{tx("重试")}</button>
              </p>
            )}
            <nav className="record-actions" aria-label={tx("辩论分页")}>
              {cursor && (
                <Link href={pageHref("/live", { status })}>
                  {tx("最新辩论")}
                </Link>
              )}
              {currentCursor && (
                <Link
                  rel="next"
                  href={pageHref("/live", { status, cursor: currentCursor })}
                >
                  {tx("更早的辩论 →")}
                </Link>
              )}
            </nav>
          </details>
        }
      >
        {selection.data ? (
          <>
            <DebateExperience
              key={selection.id}
              debate={selection.data}
              previous={adjacent(-1)}
              next={adjacent(1)}
              position={
                index >= 0 ? `${index + 1} / ${sessions.length}` : undefined
              }
              onRefresh={selection.reload}
              onPrevious={() =>
                index > 0 &&
                selection.select(sessions[index - 1].debateSessionId)
              }
              onNext={() =>
                index >= 0 &&
                index < sessions.length - 1 &&
                selection.select(sessions[index + 1].debateSessionId)
              }
            />
            {selection.error && (
              <p className="reading-refresh-error" role="alert">
                {tx("更新暂时失败。")}
                <button onClick={selection.reload}>{tx("重试")}</button>
              </p>
            )}
          </>
        ) : selection.id ? (
          <ReadingLoading error={selection.error} retry={selection.reload} />
        ) : (
          <Empty unavailable={unavailable} />
        )}
      </ReadingWorkspace>
    </>
  );
}
