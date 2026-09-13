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
  const value = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
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
  const wantsPlayback = useRef(false);
  const requestId = useRef(0);
  const [playing, setPlaying] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [duration, setDuration] = useState((durationMs || 0) / 1000);
  const [position, setPosition] = useState(0);
  useEffect(() => {
    const player = audio.current;
    const stop = () => {
      wantsPlayback.current = false;
      requestId.current += 1;
      player?.pause();
      setLoading(false);
      setPlaying(false);
    };
    const pauseOther = (event: Event) => {
      if (
        event.target instanceof HTMLAudioElement &&
        event.target !== audio.current
      )
        stop();
    };
    const visibility = () => {
      if (document.visibilityState !== "visible") stop();
    };
    document.addEventListener("play", pauseOther, true);
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("pagehide", stop);
    return () => {
      wantsPlayback.current = false;
      requestId.current += 1;
      document.removeEventListener("play", pauseOther, true);
      document.removeEventListener("visibilitychange", visibility);
      window.removeEventListener("pagehide", stop);
      player?.pause();
      if (player && !player.isConnected) {
        player.removeAttribute("src");
        player.load();
      }
    };
  }, [src]);
  async function toggle() {
    const player = audio.current;
    if (!player) return;
    if (wantsPlayback.current || !player.paused) {
      wantsPlayback.current = false;
      requestId.current += 1;
      player.pause();
      setPlaying(false);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError("");
    wantsPlayback.current = true;
    const attempt = ++requestId.current;
    try {
      if (player.error) player.load();
      if (player.ended) {
        player.currentTime = 0;
        setPosition(0);
      }
      await player.play();
    } catch (cause) {
      if (
        attempt === requestId.current &&
        !(cause instanceof DOMException && cause.name === "AbortError")
      ) {
        wantsPlayback.current = false;
        setError("语音暂时无法播放，请重试。");
      }
    } finally {
      if (attempt === requestId.current) setLoading(false);
    }
  }
  return (
    <div className="cant-audio-card">
      <audio
        ref={audio}
        src={src}
        preload="none"
        onPlaying={() => {
          if (!wantsPlayback.current) {
            audio.current?.pause();
            return;
          }
          setPlaying(true);
          setLoading(false);
        }}
        onPause={() => {
          if (audio.current && !audio.current.paused) return;
          wantsPlayback.current = false;
          setPlaying(false);
          setLoading(false);
        }}
        onWaiting={() => setLoading(wantsPlayback.current)}
        onEnded={() => {
          wantsPlayback.current = false;
          setPlaying(false);
          setPosition(audio.current?.duration || duration);
        }}
        onTimeUpdate={() => setPosition(audio.current?.currentTime || 0)}
        onLoadedMetadata={() => {
          const value = audio.current?.duration;
          if (value && Number.isFinite(value)) setDuration(value);
        }}
        onError={() => {
          wantsPlayback.current = false;
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
        <time
          className="cant-remaining"
          aria-label={`剩余 ${clock(Math.ceil(duration - position))}，总时长 ${clock(Math.ceil(duration))}`}
        >
          <span>剩余 {clock(Math.ceil(duration - position))}</span>
          <small>共 {clock(Math.ceil(duration))}</small>
        </time>
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
