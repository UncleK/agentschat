"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import Link from "next/link";
import { ArrowUp, ExternalLink } from "lucide-react";
import { api, errorMessage } from "@/lib/client-api";
import "./reading-workspace.css";

export function useReadingSelection<T>(
  surface: "forum" | "live",
  initialId: string,
  firstId: string,
  initialRecord: T | null,
) {
  const [id, setId] = useState(initialId);
  const [record, setRecord] = useState({ id: initialId, value: initialRecord });
  const [failure, setFailure] = useState<{
    id: string;
    message: string;
  } | null>(null);
  const [revision, setRevision] = useState(0);
  const currentId = useRef(id);
  currentId.current = id;
  const reload = useCallback(() => setRevision((v) => v + 1), []);
  useEffect(() => {
    setId(initialId);
  }, [initialId]);

  useEffect(() => {
    if (!id && firstId) setId(firstId);
  }, [id, firstId]);

  useEffect(() => {
    if (initialId === currentId.current && initialRecord) {
      setRecord({ id: initialId, value: initialRecord });
      setFailure(null);
    }
  }, [initialId, initialRecord]);

  useEffect(() => {
    const readLocation = () => {
      const url = new URL(window.location.href);
      const explicit = url.searchParams.get(
        surface === "forum" ? "topic" : "session",
      );
      const fromPath = url.pathname.match(
        new RegExp(`^/${surface}/([0-9a-f-]{36})$`, "i"),
      )?.[1];
      setId(explicit || fromPath || firstId);
    };
    window.addEventListener("popstate", readLocation);
    return () => window.removeEventListener("popstate", readLocation);
  }, [surface, firstId]);

  useEffect(() => {
    if (!id) return;
    const abort = new AbortController();
    let inFlight = false;
    const load = async () => {
      if (inFlight) return;
      inFlight = true;
      try {
        const result = await api<T | { topic: T }>(
          surface === "forum"
            ? `/content/public/forum/topics/${encodeURIComponent(id)}`
            : `/debates/${encodeURIComponent(id)}`,
          {
            signal: AbortSignal.any([abort.signal, AbortSignal.timeout(10000)]),
          },
        );
        if (abort.signal.aborted || currentId.current !== id) return;
        setRecord({
          id,
          value:
            surface === "forum"
              ? (result as { topic: T }).topic
              : (result as T),
        });
        setFailure(null);
      } catch (error) {
        if (!abort.signal.aborted && currentId.current === id)
          setFailure({ id, message: errorMessage(error) });
      } finally {
        inFlight = false;
      }
    };
    // The first detail is server-rendered; selecting another record fetches only it.
    if (revision || record.id !== id || !record.value) void load();
    const visible = () => {
      if (!document.hidden) void load();
    };
    const timer =
      surface === "live" ? window.setInterval(visible, 15000) : undefined;
    if (surface === "live") window.addEventListener("focus", visible);
    return () => {
      abort.abort();
      window.clearInterval(timer);
      window.removeEventListener("focus", visible);
    };
    // record is deliberately not a dependency: a successful load must not restart it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, surface, revision]);

  const select = useCallback(
    (nextId: string) => {
      if (!window.matchMedia("(min-width: 1024px)").matches) return false;
      if (nextId !== currentId.current) {
        const url = new URL(window.location.href);
        url.pathname = `/${surface}`;
        url.searchParams.set(surface === "forum" ? "topic" : "session", nextId);
        url.hash = "";
        window.history.pushState(null, "", url);
        setId(nextId);
        setFailure(null);
      }
      return true;
    },
    [surface],
  );
  return {
    id,
    data: record.id === id ? record.value : null,
    error: failure?.id === id ? failure.message : "",
    select,
    reload,
  };
}

export function ReadingWorkspace({
  surface,
  selectedId,
  detailHref,
  primary,
  children,
  mobileDetail = false,
}: {
  surface: "forum" | "live";
  selectedId: string;
  detailHref?: string;
  primary: ReactNode;
  children: ReactNode;
  mobileDetail?: boolean;
}) {
  const left = useRef<HTMLElement>(null);
  const right = useRef<HTMLElement>(null);
  useEffect(() => {
    if (!window.location.hash)
      right.current?.scrollTo({ top: 0, behavior: "instant" });
  }, [selectedId]);
  const toTop = (element: HTMLElement | null) => {
    element?.scrollTo({
      top: 0,
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "instant"
        : "smooth",
    });
  };
  return (
    <div
      className={`reading-workspace ${surface}-workspace ${mobileDetail ? "mobile-detail" : ""}`}
    >
      <section
        className="reading-pane reading-primary"
        ref={left}
        aria-label={surface === "forum" ? "论坛主题列表" : "辩论主题列表"}
        tabIndex={0}
      >
        <header className="reading-pane-header">
          <strong>{surface === "forum" ? "话题" : "全部辩论"}</strong>
          <button onClick={() => toTop(left.current)} aria-label="左栏回到顶部">
            <ArrowUp size={16} /> 回到顶部
          </button>
        </header>
        <div className="reading-pane-content">{primary}</div>
      </section>
      <section
        className="reading-pane reading-details"
        ref={right}
        aria-label="当前主题详情"
        tabIndex={0}
      >
        <header className="reading-pane-header">
          <strong>当前主题详情</strong>
          <div>
            {detailHref && (
              <Link href={detailHref} aria-label="打开当前主题独立页面">
                <ExternalLink size={15} />
              </Link>
            )}
            <button
              onClick={() => toTop(right.current)}
              aria-label="右栏回到顶部"
            >
              <ArrowUp size={16} /> 回到顶部
            </button>
          </div>
        </header>
        <div className="reading-pane-content" data-selected-id={selectedId}>
          {children}
        </div>
      </section>
    </div>
  );
}

export function ReadingLoading({
  error,
  retry,
}: {
  error: string;
  retry: () => void;
}) {
  return (
    <div className="reading-loading" role={error ? "alert" : "status"}>
      {error ? (
        <>
          <p>这个主题暂时无法加载。</p>
          <p>{error}</p>
          <button onClick={retry}>重新加载</button>
        </>
      ) : (
        <p>正在加载主题详情…</p>
      )}
    </div>
  );
}
