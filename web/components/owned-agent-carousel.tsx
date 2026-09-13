"use client";
import { useEffect, useLayoutEffect, useRef, type ReactNode } from "react";

export function OwnedAgentCarousel({
  activeId,
  selectAgent,
  children,
}: {
  activeId?: string;
  selectAgent: (id: string) => void;
  children: ReactNode;
}) {
  const root = useRef<HTMLElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const interacting = useRef(false);
  const select = useRef(selectAgent);
  select.current = selectAgent;
  useLayoutEffect(() => {
    const element = root.current;
    if (!element) return;
    const sync = () => {
      if (!matchMedia("(max-width: 800px)").matches) return;
      const card = [...element.children].find(
        (child) => (child as HTMLElement).dataset.agentId === activeId,
      ) as HTMLElement | undefined;
      if (!card) return;
      interacting.current = false;
      element.scrollLeft +=
        card.getBoundingClientRect().left -
        element.getBoundingClientRect().left -
        (element.clientWidth - card.clientWidth) / 2;
    };
    sync();
    const observer = new ResizeObserver(sync);
    observer.observe(element);
    return () => observer.disconnect();
  }, [activeId, children]);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );
  return (
    <section
      className="ws-owned-grid"
      ref={root}
      aria-label="我的智能体档案"
      onPointerDown={() => {
        interacting.current = true;
      }}
      onTouchStart={() => {
        interacting.current = true;
      }}
      onWheel={() => {
        interacting.current = true;
      }}
      onScroll={() => {
        if (!interacting.current || !matchMedia("(max-width: 800px)").matches)
          return;
        if (timer.current) clearTimeout(timer.current);
        timer.current = setTimeout(() => {
          const element = root.current;
          if (!element || !interacting.current) return;
          const center =
            element.getBoundingClientRect().left + element.clientWidth / 2;
          const card = [...element.children]
            .map((child) => ({
              child: child as HTMLElement,
              rect: child.getBoundingClientRect(),
            }))
            .sort(
              (a, b) =>
                Math.abs(a.rect.left + a.rect.width / 2 - center) -
                Math.abs(b.rect.left + b.rect.width / 2 - center),
            )[0]?.child;
          if (card?.dataset.agentId && card.dataset.selectable === "true")
            select.current(card.dataset.agentId);
          interacting.current = false;
        }, 150);
      }}
    >
      {children}
    </section>
  );
}
