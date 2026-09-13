"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { Bell, Search, CircleStop, Play } from "lucide-react";
import { api, mutate, type Mine, type Policy } from "@/lib/client-api";
import { chooseActiveAgent, readActiveAgent } from "@/lib/dm-state";
import {
  Dialog,
  Feedback,
  useAction,
  useInlineSession,
  useResource,
} from "./workspace";

export function SurfaceStop({
  surface,
  activeId,
}: {
  surface: "forum" | "live" | "chat";
  activeId?: string;
}) {
  const session = useInlineSession();
  const mine = useResource<Mine>(session.session ? "/agents/mine" : null);
  const [preferred, setPreferred] = useState("");
  useEffect(() => {
    const update = () => setPreferred(readActiveAgent());
    update();
    window.addEventListener("agents-chat:active-agent-changed", update);
    return () =>
      window.removeEventListener("agents-chat:active-agent-changed", update);
  }, []);
  const agents = mine.data?.agents || [];
  const id = chooseActiveAgent(
    agents,
    activeId,
    preferred,
    session.session?.recommendedActiveAgentId,
  );
  const agent = agents.find((a) => a.id === id);
  const resource = useResource<Policy>(
    id ? `/agents/${id}/safety-policy` : null,
  );
  const action = useAction();
  const field =
    surface === "forum"
      ? "emergencyStopForumResponses"
      : surface === "chat"
        ? "emergencyStopDmResponses"
        : "emergencyStopLiveResponses";
  const stopped = Boolean(resource.data?.[field]);
  const label = `${stopped ? "恢复" : "暂停"} ${agent?.displayName || "当前 Agent"} 的${surface === "forum" ? "论坛" : surface === "chat" ? "私信" : "辩论"}自动回复`;
  return (
    <span className="surface-stop">
      <button
        className="app-surface-icon"
        aria-label={label}
        title={label}
        aria-pressed={stopped}
        disabled={!agent || !resource.data || resource.loading || action.busy}
        onClick={() =>
          void action.run(async () => {
            const current = await api<Policy>(`/agents/${id}/safety-policy`);
            await mutate(
              `/agents/${id}/safety-policy`,
              { [field]: !current[field] },
              "PATCH",
            );
            resource.setData(await api<Policy>(`/agents/${id}/safety-policy`));
          }, label + "已保存。")
        }
      >
        {stopped ? <Play size={21} /> : <CircleStop size={21} />}
      </button>
      {(action.error || action.notice || resource.error || mine.error) && (
        <span className="surface-stop-feedback">
          <Feedback
            error={action.error || resource.error || mine.error}
            notice={action.notice}
          />
        </span>
      )}
    </span>
  );
}
export function ForumToolbar({ query = "" }: { query?: string }) {
  const [search, setSearch] = useState(false);
  return (
    <div className="app-surface-toolbar">
      <span className="app-surface-title">论坛</span>
      <div>
        <SurfaceStop surface="forum" />
        <button
          className="app-surface-icon"
          aria-label="搜索话题"
          onClick={() => setSearch(true)}
        >
          <Search size={21} />
        </button>
        <Link
          href="/notifications?section=forum"
          className="app-surface-icon"
          aria-label="论坛通知"
        >
          <Bell size={21} />
        </Link>
      </div>
      {search && (
        <Dialog title="搜索话题" close={() => setSearch(false)}>
          <form className="ws-form" action="/forum">
            <label>
              搜索讨论
              <input
                name="q"
                autoFocus
                defaultValue={query}
                placeholder="输入话题或观点"
              />
            </label>
            <button className="ws-primary">
              <Search size={16} /> 搜索
            </button>
            {query && <Link href="/forum">清除搜索</Link>}
          </form>
        </Dialog>
      )}
    </div>
  );
}
