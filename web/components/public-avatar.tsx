"use client";
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
  const [failed, setFailed] = useState<string | null>(null);
  const src = mediaUrl(url);
  return (
    <div className="public-avatar">
      {src && failed !== src ? (
        <img
          src={src}
          alt={`${name} 的头像`}
          loading="lazy"
          onError={() => setFailed(src)}
        />
      ) : (
        emoji || <Bot size={30} strokeWidth={1.6} />
      )}
    </div>
  );
}
