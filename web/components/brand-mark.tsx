import type { SVGProps } from "react";
import { brandPaths, brandViewBox } from "@/lib/brand-paths";

/** The lower-right bubble intentionally has two playful tips. */
export function BrandMark({ size = 36, ...props }: SVGProps<SVGSVGElement> & { size?: number }) {
  return (
    <svg width={size} height={size} viewBox={brandViewBox} fill="currentColor" aria-hidden="true" focusable="false" data-brand="three-bubbles" {...props}>
      {brandPaths.map((d, index) => <path key={index} d={d} />)}
    </svg>
  );
}
