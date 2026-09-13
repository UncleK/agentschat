"use client";
import { useState } from "react";
import { Smile, X, Search } from "lucide-react";
import { agentmojiIds, agentmojiSet } from "../lib/agentmoji";
export function AgentmojiText({ text }: { text: string }) {
  return (
    <>
      {text.split(/(:[a-z0-9_]+:)/g).map((part, i) => {
        const id = part.slice(1, -1);
        return part.startsWith(":") &&
          part.endsWith(":") &&
          agentmojiSet.has(id) ? (
          <img
            key={i}
            className="agentmoji-inline"
            src={`/agentmoji/${id}.png`}
            alt={part}
            title={id}
            loading="lazy"
          />
        ) : (
          part
        );
      })}
    </>
  );
}
export function AgentmojiPicker({
  onSelect,
  disabled,
}: {
  onSelect: (code: string) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false),
    [search, setSearch] = useState("");
  return (
    <div className="agentmoji-control">
      <button
        type="button"
        className="ws-icon-button"
        disabled={disabled}
        aria-label="Agentmoji 表情"
        aria-expanded={open}
        onClick={() => setOpen(!open)}
      >
        <Smile size={19} />
      </button>
      {open && (
        <div
          className="agentmoji-picker"
          role="region"
          aria-label="选择 Agentmoji"
        >
          <div className="agentmoji-picker-heading">
            <strong>Agentmoji</strong>
            <button
              type="button"
              className="ws-icon-button"
              aria-label="关闭表情选择"
              onClick={() => setOpen(false)}
            >
              <X size={16} />
            </button>
          </div>
          <label className="ws-search">
            <Search size={15} />
            <input
              aria-label="搜索 Agentmoji"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="搜索表情名称"
            />
          </label>
          <div className="agentmoji-grid">
            {agentmojiIds
              .filter((id) => id.includes(search.toLowerCase()))
              .map((id) => (
                <button
                  type="button"
                  title={id}
                  aria-label={`插入 ${id}`}
                  key={id}
                  onClick={() => {
                    onSelect(`:${id}:`);
                    setOpen(false);
                  }}
                >
                  <img src={`/agentmoji/${id}.png`} alt={id} loading="lazy" />
                </button>
              ))}
          </div>
        </div>
      )}
    </div>
  );
}
