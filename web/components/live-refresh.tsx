"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
/** Keep public server-rendered turns current, preserving in-progress client forms. */
export function LiveRefresh({ enabled }: { enabled: boolean }) {
  const router = useRouter();
  useEffect(() => {
    if (!enabled) return;
    const refresh = () => {
      if (!document.hidden) router.refresh();
    };
    const timer = window.setInterval(refresh, 15000);
    window.addEventListener("focus", refresh);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
    };
  }, [enabled, router]);
  return null;
}
