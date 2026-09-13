"use client";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import { Maximize2, Minimize2, X } from "lucide-react";

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
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [expanded, setExpanded] = useState(false);
  const [actualSize, setActualSize] = useState(false);
  const [viewerFailed, setViewerFailed] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  const viewport = useRef<HTMLDivElement>(null);
  const longImage = size.height > size.width * 2.4;
  useEffect(() => {
    if (!expanded) return;
    const viewer = dialog.current;
    if (!viewer) return;
    viewer.showModal();
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      viewer.close();
      document.body.style.overflow = overflow;
    };
  }, [expanded]);
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
    <>
      <button
        type="button"
        className={`chat-image-button ${longImage ? "is-long" : ""}`}
        style={
          size.width
            ? ({ "--chat-image-width": `${size.width}px` } as CSSProperties)
            : undefined
        }
        aria-label={`查看完整图片：${caption || "聊天图片"}`}
        onClick={() => {
          setActualSize(longImage);
          setViewerFailed(false);
          setExpanded(true);
        }}
      >
        <img
          key={attempt}
          className="ws-message-image"
          src={src}
          alt={caption || "聊天图片"}
          loading="lazy"
          onLoad={(event) => {
            setSize({
              width: event.currentTarget.naturalWidth,
              height: event.currentTarget.naturalHeight,
            });
            onLoad();
          }}
          onError={() => {
            setFailed(true);
            setExpanded(false);
          }}
        />
        {longImage && (
          <span className="chat-image-long-hint">长图 · 点击查看完整图片</span>
        )}
      </button>
      <dialog
        ref={dialog}
        className="chat-image-dialog"
        aria-label="查看完整图片"
        onClose={() => setExpanded(false)}
        onClick={(event) => {
          if (event.target === event.currentTarget) setExpanded(false);
        }}
      >
        {expanded && (
          <>
            <header className="chat-image-viewer-toolbar">
              <span title={caption || "聊天图片"}>{caption || "聊天图片"}</span>
              <button
                type="button"
                onClick={() => {
                  setActualSize(!actualSize);
                  viewport.current?.scrollTo(0, 0);
                }}
              >
                {actualSize ? <Minimize2 size={18} /> : <Maximize2 size={18} />}
                {actualSize ? "适应窗口" : "原图尺寸"}
              </button>
              <button
                type="button"
                aria-label="关闭图片"
                onClick={() => setExpanded(false)}
              >
                <X size={22} />
              </button>
            </header>
            <div
              ref={viewport}
              className={`chat-image-viewport ${actualSize ? "actual-size" : "fit-size"}`}
            >
              {viewerFailed ? (
                <p role="alert">图片暂时无法加载，请关闭后重试。</p>
              ) : (
                <img
                  className="chat-image-full"
                  src={src}
                  alt={caption || "聊天图片"}
                  onError={() => setViewerFailed(true)}
                />
              )}
            </div>
          </>
        )}
      </dialog>
    </>
  );
}
