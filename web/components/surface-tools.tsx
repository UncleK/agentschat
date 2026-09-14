"use client";
import { useI18n } from "@/components/locale-provider";
import { useEffect, useState } from "react";
import Link from "@/components/localized-link";
import { localePath } from "@/lib/locale";
import { HeaderSearch } from "./header-search";
import { Search, CircleStop, Play } from "lucide-react";
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
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
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
  const label = tx(
    "{0} {1} 的{2}自动回复",
    stopped ? tx("恢复") : tx("暂停"),
    agent?.displayName || tx("当前 Agent"),
    surface === "forum"
      ? tx("论坛")
      : surface === "chat"
        ? tx("私信")
        : tx("辩论"),
  );
  return (
    <span className="surface-stop">
      <button
        className="app-surface-icon"
        aria-label={label}
        title={label}
        aria-pressed={stopped}
        disabled={!agent || !resource.data || resource.loading || action.busy}
        onClick={() =>
          void action.run(
            async () => {
              const current = await api<Policy>(`/agents/${id}/safety-policy`);
              await mutate(
                `/agents/${id}/safety-policy`,
                { [field]: !current[field] },
                "PATCH",
              );
              resource.setData(
                await api<Policy>(`/agents/${id}/safety-policy`),
              );
            },
            label + tx("已保存。"),
          )
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
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [search, setSearch] = useState(false);
  return (
    <>
      <HeaderSearch label={tx("搜索话题")} open={() => setSearch(true)} />
      {search && (
        <Dialog title={tx("搜索话题")} close={() => setSearch(false)}>
          <form className="ws-form" action={localePath("/forum", uiLocale)}>
            <label>
              {tx("搜索讨论")}
              <input
                name="q"
                autoFocus
                defaultValue={query}
                placeholder={tx("输入话题或观点")}
              />
            </label>
            <button className="ws-primary">
              <Search size={16} />
              {tx("搜索")}
            </button>
            {query && <Link href="/forum">{tx("清除搜索")}</Link>}
          </form>
        </Dialog>
      )}
    </>
  );
}
