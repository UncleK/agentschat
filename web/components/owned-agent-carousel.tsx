"use client";
import { useI18n } from "@/components/locale-provider";
import { useLayoutEffect, useRef, type CSSProperties } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import type { Agent } from "../lib/client-api";
import { PublicAvatar } from "./public-avatar";
export function OwnedAgentCarousel({
  activeId,
  selectAgent,
  agents,
}: {
  activeId?: string;
  selectAgent: (id: string) => void;
  agents: Agent[];
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const root = useRef<HTMLDivElement>(null);
  const select = useRef(selectAgent);
  select.current = selectAgent;
  const currentId = useRef(activeId);
  currentId.current = activeId;
  const navigate = useRef<(index: number) => void>(() => {});
  const ids = agents
    .map((agent) => `${agent.id}:${agent.status === "suspended"}`)
    .join("|");
  const index = agents.findIndex((agent) => agent.id === activeId);
  const previous = agents.findLastIndex(
    (agent, i) => i < index && agent.status !== "suspended",
  );
  const next = agents.findIndex(
    (agent, i) => i > index && agent.status !== "suspended",
  );
  useLayoutEffect(() => {
    const element = root.current;
    if (!element) return;
    const cards = Array.from(element.children) as HTMLElement[];
    let timer: ReturnType<typeof setTimeout> | undefined;
    let frame = 0;
    let interacting = false;
    let pointer: {
      id: number;
      x: number;
      scroll: number;
      moved: boolean;
    } | null = null;
    let ignoreClick = false;
    const reduced = matchMedia("(prefers-reduced-motion: reduce)");
    const center = () => element.scrollLeft + element.clientWidth / 2;
    const paint = () => {
      frame = 0;
      for (const card of cards) {
        const distance =
          (card.offsetLeft + card.offsetWidth / 2 - center()) /
          card.offsetWidth;
        const lane = Math.max(-2.5, Math.min(2.5, distance));
        card.style.setProperty("--lane", String(reduced.matches ? 0 : lane));
        card.style.setProperty(
          "--depth",
          String(reduced.matches ? 0 : Math.abs(lane)),
        );
        card.style.zIndex = String(100 - Math.round(Math.abs(lane) * 10));
      }
    };
    const scrollTo = (card: HTMLElement, smooth: boolean) => {
      element.scrollTo({
        left: card.offsetLeft - (element.clientWidth - card.offsetWidth) / 2,
        behavior: smooth && !reduced.matches ? "smooth" : "instant",
      });
    };
    const sync = () => {
      interacting = false;
      if (timer) clearTimeout(timer);
      const card = cards.find(
        (item) => item.dataset.agentId === currentId.current,
      );
      if (card) scrollTo(card, false);
      paint();
    };
    const settle = () => {
      if (!interacting || pointer) return;
      interacting = false;
      const nearest = cards
        .filter((card) => card.dataset.selectable === "true")
        .sort(
          (a, b) =>
            Math.abs(a.offsetLeft + a.offsetWidth / 2 - center()) -
            Math.abs(b.offsetLeft + b.offsetWidth / 2 - center()),
        )[0];
      if (!nearest) return;
      scrollTo(nearest, true);
      if (nearest.dataset.agentId !== currentId.current)
        select.current(nearest.dataset.agentId!);
    };
    const scroll = () => {
      if (!frame) frame = requestAnimationFrame(paint);
      if (timer) clearTimeout(timer);
      timer = setTimeout(settle, 180);
    };
    const down = (event: PointerEvent) => {
      interacting = true;
      ignoreClick = false;
      if (event.pointerType !== "mouse" || event.button !== 0) return;
      pointer = {
        id: event.pointerId,
        x: event.clientX,
        scroll: element.scrollLeft,
        moved: false,
      };
    };
    const move = (event: PointerEvent) => {
      if (!pointer || event.pointerId !== pointer.id) return;
      const delta = event.clientX - pointer.x;
      if (Math.abs(delta) > 5) {
        pointer.moved = true;
        ignoreClick = true;
        element.setPointerCapture(event.pointerId);
        element.dataset.dragging = "true";
      }
      if (pointer.moved) {
        event.preventDefault();
        element.scrollLeft = pointer.scroll - delta;
      }
    };
    const up = () => {
      pointer = null;
      delete element.dataset.dragging;
      if (timer) clearTimeout(timer);
      timer = setTimeout(settle, 180);
    };
    const click = (event: MouseEvent) => {
      if (ignoreClick) {
        event.preventDefault();
        event.stopPropagation();
        ignoreClick = false;
      }
    };
    const wheel = () => {
      interacting = true;
    };
    navigate.current = (target) => {
      const card = cards[target];
      if (!card || card.dataset.selectable !== "true") return;
      interacting = true;
      scrollTo(card, true);
      if (timer) clearTimeout(timer);
      timer = setTimeout(settle, 180);
    };
    sync();
    const resize = new ResizeObserver(sync);
    resize.observe(element);
    element.addEventListener("scroll", scroll, { passive: true });
    element.addEventListener("pointerdown", down);
    element.addEventListener("pointermove", move);
    element.addEventListener("pointerup", up);
    element.addEventListener("pointercancel", up);
    element.addEventListener("click", click, true);
    element.addEventListener("wheel", wheel, { passive: true });
    reduced.addEventListener("change", sync);
    return () => {
      resize.disconnect();
      clearTimeout(timer);
      cancelAnimationFrame(frame);
      element.removeEventListener("scroll", scroll);
      element.removeEventListener("pointerdown", down);
      element.removeEventListener("pointermove", move);
      element.removeEventListener("pointerup", up);
      element.removeEventListener("pointercancel", up);
      element.removeEventListener("click", click, true);
      element.removeEventListener("wheel", wheel);
      reduced.removeEventListener("change", sync);
    };
  }, [ids]);
  useLayoutEffect(() => {
    const element = root.current;
    const card =
      element &&
      (Array.from(element.children).find(
        (child) => (child as HTMLElement).dataset.agentId === activeId,
      ) as HTMLElement | undefined);
    if (!element || !card) return;
    const left = card.offsetLeft - (element.clientWidth - card.offsetWidth) / 2;
    if (Math.abs(element.scrollLeft - left) > 2)
      element.scrollTo({ left, behavior: "instant" });
  }, [activeId]);
  if (!agents.length) return null;
  return (
    <section
      className="hub-carousel"
      aria-label={tx("我的智能体档案")}
      aria-roledescription={tx("轮播")}
    >
      <div
        className="hub-carousel-track"
        ref={root}
        tabIndex={0}
        aria-label={tx("左右滑动切换 Agent")}
        onKeyDown={(event) => {
          if (event.target !== event.currentTarget) return;
          const target =
            event.key === "ArrowLeft"
              ? previous
              : event.key === "ArrowRight"
                ? next
                : event.key === "Home"
                  ? agents.findIndex((a) => a.status !== "suspended")
                  : event.key === "End"
                    ? agents.findLastIndex((a) => a.status !== "suspended")
                    : -1;
          if (target >= 0) {
            event.preventDefault();
            navigate.current(target);
          }
        }}
      >
        {agents.map((agent, i) => (
          <div
            key={agent.id}
            className="hub-carousel-slot"
            data-agent-id={agent.id}
            data-selectable={agent.status !== "suspended"}
            style={
              {
                "--lane": i - Math.max(index, 0),
                "--depth": Math.abs(i - Math.max(index, 0)),
              } as CSSProperties
            }
          >
            <button
              className={`hub-agent-card ${activeId === agent.id ? "is-active" : ""}`}
              aria-label={tx("切换到 {0}", agent.displayName)}
              aria-pressed={activeId === agent.id}
              disabled={agent.status === "suspended"}
              onClick={() => navigate.current(i)}
            >
              <span className="hub-agent-portrait">
                <PublicAvatar
                  url={agent.avatarUrl}
                  emoji={agent.avatarEmoji}
                  name={agent.displayName}
                />
                <span className="hub-agent-active">
                  {agent.status === "suspended"
                    ? tx("已停用")
                    : activeId === agent.id
                      ? tx("当前激活")
                      : tx("点击切换")}
                </span>
              </span>
              <span className="hub-agent-name">{agent.displayName}</span>
              <span className="hub-agent-handle">@{agent.handle}</span>
            </button>
          </div>
        ))}
      </div>
      <p className="hub-carousel-caption">{agents[index]?.displayName}</p>
      <div className="hub-carousel-controls">
        <button
          aria-label={tx("上一个 Agent")}
          className="ws-icon-button"
          disabled={previous < 0}
          onClick={() => navigate.current(previous)}
        >
          <ChevronLeft size={20} />
        </button>
        <span aria-live="polite">
          {Math.max(index + 1, 0)} <span>/ {agents.length}</span>
        </span>
        <button
          aria-label={tx("下一个 Agent")}
          className="ws-icon-button"
          disabled={next < 0}
          onClick={() => navigate.current(next)}
        >
          <ChevronRight size={20} />
        </button>
      </div>
      <p className="hub-carousel-hint">{tx("左右滑动，切换当前 Agent")}</p>
    </section>
  );
}
