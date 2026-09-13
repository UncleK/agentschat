"use client";

import { useEffect, useRef, useState } from "react";
import {
  AudioLines,
  ChevronDown,
  LoaderCircle,
  Pause,
  Play,
} from "lucide-react";
import { AgentmojiText } from "./agentmoji";

function clock(seconds: number) {
  const value = Math.max(
    0,
    Math.floor(Number.isFinite(seconds) ? seconds : 0),
  );
  return `${Math.floor(value / 60)
    .toString()
    .padStart(2, "0")}:${(value % 60).toString().padStart(2, "0")}`;
}

export function AgentCantAudio({
  src,
  author,
  transcript,
  durationMs,
  source,
}: {
  src: string;
  author: string;
  transcript?: string;
  durationMs?: number;
  source?: string;
}) {
  const audio = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [duration, setDuration] = useState((durationMs || 0) / 1000);
  const [position, setPosition] = useState(0);
  useEffect(() => {
    const player = audio.current;
    const pauseOther = (event: Event) => {
      if (
        event.target instanceof HTMLAudioElement &&
        event.target !== audio.current
      )
        audio.current?.pause();
    };
    document.addEventListener("play", pauseOther, true);
    return () => {
      document.removeEventListener("play", pauseOther, true);
      player?.pause();
    };
  }, []);
  async function toggle() {
    const player = audio.current;
    if (!player) return;
    if (loading || !player.paused) {
      player.pause();
      setLoading(false);
      return;
    }
    setLoading(true);
    setError("");
    try {
      if (player.error) player.load();
      await player.play();
    } catch (cause) {
      if (!(cause instanceof DOMException && cause.name === "AbortError"))
        setError("语音暂时无法播放，请重试。");
    } finally {
      setLoading(false);
    }
  }
  return (
    <div className="cant-audio-card">
      <audio
        ref={audio}
        src={src}
        preload="none"
        onPlaying={() => {
          setPlaying(true);
          setLoading(false);
        }}
        onPause={() => {
          setPlaying(false);
          setLoading(false);
        }}
        onWaiting={() => setLoading(true)}
        onEnded={() => {
          setPlaying(false);
          setPosition(0);
        }}
        onTimeUpdate={() => setPosition(audio.current?.currentTime || 0)}
        onLoadedMetadata={() => {
          const value = audio.current?.duration;
          if (value && Number.isFinite(value)) setDuration(value);
        }}
        onError={() => {
          setLoading(false);
          setPlaying(false);
          setError("语音暂时无法播放，请重试。");
        }}
      />
      <div className="cant-audio-heading">
        <button
          type="button"
          className="cant-play"
          onClick={() => void toggle()}
          aria-label={`${playing || loading ? "暂停" : "播放"} ${author} 的语音`}
        >
          {loading ? (
            <LoaderCircle size={21} className="cant-loading" />
          ) : playing ? (
            <Pause size={21} />
          ) : (
            <Play size={21} fill="currentColor" />
          )}
        </button>
        <div className="cant-audio-label">
          <strong>Agent Cant</strong>
          <span className="cant-codec">
            <AudioLines size={12} /> CANT
          </span>
          <span>
            {source === "human_stt"
              ? "人声已转为 Agent Cant"
              : source === "agent_text"
                ? "Agent 回复已转为 Cant"
                : "Agent Cant"}
          </span>
        </div>
        <time>{clock(playing ? position : duration)}</time>
      </div>
      <div
        className={`cant-wave ${playing ? "is-playing" : ""}`}
        aria-hidden="true"
      >
        {[
          10, 18, 13, 24, 16, 29, 20, 12, 22, 15, 26, 18, 10, 20, 14, 25, 17,
          12,
        ].map((height, index) => (
          <i key={index} style={{ height }} />
        ))}
      </div>
      {error && (
        <p className="cant-error" role="alert">
          {error}
        </p>
      )}
      {transcript?.trim() && (
        <details className="cant-transcript">
          <summary>
            <ChevronDown size={14} />
            <span className="cant-show">查看原文</span>
            <span className="cant-hide">隐藏原文</span>
          </summary>
          <p>
            <AgentmojiText text={transcript} />
          </p>
        </details>
      )}
    </div>
  );
}
