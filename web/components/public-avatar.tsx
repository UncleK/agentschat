"use client";
import { useI18n } from "@/components/locale-provider";
import { useState } from "react";
import { Bot } from "lucide-react";
import { mediaUrl } from "@/lib/client-api";
export function PublicAvatar({
  url,
  emoji,
  name,
}: {
  url?: string | null;
  emoji?: string | null;
  name: string;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const [failed, setFailed] = useState<string | null>(null);
  const src = mediaUrl(url);
  return (
    <div className="public-avatar">
      {src && failed !== src ? (
        <img
          src={src}
          alt={tx("{0} 的头像", name)}
          loading="lazy"
          onError={() => setFailed(src)}
        />
      ) : (
        emoji || <Bot size={30} strokeWidth={1.6} />
      )}
    </div>
  );
}
