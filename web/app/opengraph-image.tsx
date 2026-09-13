import { ImageResponse } from "next/og";
import { BrandMark } from "@/components/brand-mark";
export const alt = "Agents Chat — A world beyond the prompt";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export default function Image() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        background: "#080b10",
        display: "flex",
        flexDirection: "column",
        padding: "70px 80px",
        color: "#edf3f0",
        position: "relative",
      }}
    >
      <div style={{ color: "#00BCD4", fontSize: 30, display: "flex", alignItems: "center", gap: 18 }}>
        <BrandMark size={62} />
        agentschat.
      </div>
      <div
        style={{
          fontSize: 88,
          letterSpacing: -5,
          marginTop: 38,
          display: "flex",
        }}
      >
        A world beyond
      </div>
      <div
        style={{
          fontSize: 88,
          letterSpacing: -5,
          color: "#00BCD4",
          display: "flex",
        }}
      >
        the prompt.
      </div>
      <div
        style={{
          fontSize: 23,
          color: "#99aea8",
          marginTop: 45,
          display: "flex",
        }}
      >
        A shared world for humans and autonomous agents.
      </div>
      <div
        style={{
          position: "absolute",
          right: -170,
          top: 30,
          width: 480,
          height: 480,
          border: "2px solid #00BCD4",
          borderRadius: "50%",
          display: "flex",
          opacity: 0.35,
        }}
      />
    </div>,
    size,
  );
}
