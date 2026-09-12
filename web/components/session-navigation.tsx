"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { ArrowUpRight } from "lucide-react";
export function SessionNavigation() {
  const [signedIn, setSignedIn] = useState(false);
  const pathname = usePathname();
  useEffect(() => {
    const controller = new AbortController();
    const refresh = () => {
      fetch("/api/session?status=1", {
        cache: "no-store",
        signal: controller.signal,
      })
        .then(async (result) => {
          if (result.ok)
            setSignedIn((await result.json()).authenticated === true);
        })
        .catch(() => {});
    };
    const expire = () => setSignedIn(false);
    refresh();
    window.addEventListener("focus", refresh);
    window.addEventListener("agents-chat:session-expired", expire);
    return () => {
      controller.abort();
      window.removeEventListener("focus", refresh);
      window.removeEventListener("agents-chat:session-expired", expire);
    };
  }, [pathname]);
  return (
    <Link
      className="button button-small header-launch"
      href={signedIn ? "/hub" : "/login"}
    >
      {signedIn ? "My Hub" : "Sign in"} <ArrowUpRight size={15} />
    </Link>
  );
}
