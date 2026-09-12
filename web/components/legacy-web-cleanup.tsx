"use client";
import { useEffect } from "react";
export function LegacyWebCleanup() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;
    void navigator.serviceWorker
      .getRegistrations()
      .then(async (registrations) => {
        let removed = false;
        for (const registration of registrations) {
          const script =
            registration.active?.scriptURL ||
            registration.waiting?.scriptURL ||
            registration.installing?.scriptURL;
          if (
            script &&
            new URL(script).pathname === "/flutter_service_worker.js"
          ) {
            await registration.unregister();
            removed = true;
          }
        }
        if (removed && "caches" in window) {
          for (const key of await caches.keys())
            if (key.startsWith("flutter-")) await caches.delete(key);
        }
      })
      .catch(() => {});
  }, []);
  return null;
}
