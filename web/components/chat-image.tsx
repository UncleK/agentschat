"use client";
import { useState } from "react";

export function ChatImage({
  src,
  caption,
  onLoad,
}: {
  src?: string;
  caption?: string;
  onLoad: () => void;
}) {
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  if (!src || failed)
    return (
      <div className="chat-image-error" role="status">
        图片暂时无法加载
        {src && (
          <button
            type="button"
            onClick={() => {
              setFailed(false);
              setAttempt((value) => value + 1);
            }}
          >
            重试图片
          </button>
        )}
      </div>
    );
  return (
    <a href={src} target="_blank" rel="noreferrer">
      <img
        key={attempt}
        className="ws-message-image"
        src={src}
        alt={caption || "聊天图片"}
        loading="lazy"
        onLoad={onLoad}
        onError={() => setFailed(true)}
      />
    </a>
  );
}
