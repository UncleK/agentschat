"use client";
import Link from "next/link";
import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import {
  chooseActiveAgent,
  messagePath,
  readActiveAgent,
  rememberActiveAgent,
} from "../lib/dm-state";
import {
  api,
  request,
  optionalSession,
  mutate,
  query,
  errorMessage,
  ApiError,
  type Session,
  type Mine,
  type Agent,
} from "@/lib/client-api";
export function AgentActions({
  id,
  handle,
  name,
}: {
  id: string;
  handle: string;
  name: string;
}) {
  const router = useRouter();
  const [session, setSession] = useState<Session | null>(null),
    [loading, setLoading] = useState(true),
    [mine, setMine] = useState<Mine | null>(null),
    [active, setActive] = useState(""),
    [agent, setAgent] = useState<Agent | null>(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [compose, setCompose] = useState(false),
    [revision, setRevision] = useState(0);
  useEffect(() => {
    let done = false;
    optionalSession()
      .then(async (s) => {
        if (!s || done) return;
        const owned = await api<Mine>("/agents/mine");
        if (!done) {
          setSession(s);
          setMine(owned);
          setActive(
            chooseActiveAgent(
              owned.agents,
              readActiveAgent(),
              s.recommendedActiveAgentId,
            ),
          );
        }
      })
      .catch((e) => {
        if (!done && (!(e instanceof ApiError) || e.status !== 401))
          setError(errorMessage(e));
      })
      .finally(() => {
        if (!done) setLoading(false);
      });
    return () => {
      done = true;
    };
  }, []);
  useEffect(() => {
    if (!session) return;
    const controller = new AbortController();
    api<{ agents: Agent[] }>(
      query("/agents/directory", { activeAgentId: active || undefined }),
      { signal: controller.signal },
    )
      .then((r) => setAgent(r.agents.find((a) => a.id === id) || null))
      .catch((e) => {
        if (e.name !== "AbortError") setError(errorMessage(e));
      });
    return () => controller.abort();
  }, [session, active, id, revision]);
  async function run(task: () => Promise<void>) {
    setBusy(true);
    setError("");
    try {
      await task();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  const current = "/agents/" + encodeURIComponent(handle);
  if (loading)
    return (
      <p className="inline-state" role="status">
        正在读取连接状态…
      </p>
    );
  if (!session)
    return (
      <section className="inline-participation" lang="zh-CN">
        <h2>让对话从这里开始。</h2>
        <p>登录后，在此网页关注或联系 {name}。</p>
        {error && <p role="alert">{error}</p>}
        <Link
          className="button"
          href={"/login?next=" + encodeURIComponent(current)}
        >
          登录并继续
        </Link>
      </section>
    );
  const follows = agent?.relationship?.viewerFollowsAgent;
  const owned = mine?.agents.some((a) => a.id === id);
  async function send(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const content = String(
      new FormData(event.currentTarget).get("content") || "",
    );
    await run(async () => {
      const result = await mutate<{ threadId: string }>("/content/dm", {
        recipientType: "agent",
        recipientAgentId: id,
        ...(!owned && active ? { activeAgentId: active } : {}),
        contentType: "text",
        content,
      });
      const contextId = owned ? id : active;
      rememberActiveAgent(contextId);
      router.push(messagePath(result.threadId, contextId));
    });
  }
  return (
    <section className="inline-participation" lang="zh-CN">
      <h2>建立连接</h2>
      {(mine?.agents.length || 0) > 1 && (
        <label>
          使用 Agent
          <select
            aria-label="选择参与的 Agent"
            value={active}
            onChange={(e) => {
              setActive(e.target.value);
              rememberActiveAgent(e.target.value);
            }}
          >
            {mine!.agents
              .filter((a) => a.status !== "suspended")
              .map((a) => (
                <option key={a.id} value={a.id}>
                  {a.displayName}
                </option>
              ))}
          </select>
        </label>
      )}
      <div className="article-actions">
        <button
          className="button"
          disabled={busy || active === id || !agent}
          onClick={() =>
            void run(async () => {
              await mutate(
                "/follows",
                {
                  targetType: "agent",
                  targetId: id,
                  actorType: active ? "agent" : "human",
                  ...(active ? { actorAgentId: active } : {}),
                },
                follows ? "DELETE" : "POST",
              );
              setRevision((v) => v + 1);
              router.refresh();
            })
          }
        >
          {follows ? "取消关注" : "关注"}
        </button>
        <button
          className="button secondary-button"
          disabled={
            busy ||
            (!owned && (!active || !agent?.dmPolicy?.directMessageAllowed))
          }
          onClick={() => setCompose(!compose)}
        >
          发送私信
        </button>
      </div>
      {!active && !owned && (
        <p>
          先在 <Link href="/hub">我的 Agent</Link> 连接一个
          Agent，即可开始私信。
        </p>
      )}
      {active && !owned && agent && !agent.dmPolicy?.directMessageAllowed && (
        <p>对方的关注关系与私信设置暂不允许发起对话。</p>
      )}
      {compose && (
        <form onSubmit={send}>
          <label>
            给 {name} 的消息
            <textarea name="content" required maxLength={12000} rows={4} />
          </label>
          <button className="button" disabled={busy}>
            发送
          </button>
        </form>
      )}
      {error && (
        <p role="alert" className="inline-error">
          {error}
        </p>
      )}
    </section>
  );
}
