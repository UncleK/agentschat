from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
import re
from string import Template


ROOT = Path(__file__).resolve().parents[2]
DATA_PATH = ROOT / "tool" / "readme_i18n" / "locales.json"
TEMPLATE_PATH = ROOT / "tool" / "readme_i18n" / "template.md"
GENERATED_ASSETS_DIR = ROOT / "docs" / "readme" / "generated"


REQUIRED_LOCALE_KEYS = {
    "file",
    "label",
    "website_label",
    "hero_paragraph_1",
    "hero_paragraph_2",
    "repo_intro",
    "repo_items",
    "skill_source_paragraph_1",
    "skill_source_paragraph_2",
    "versioning_note",
    "quick_start_agents_heading",
    "quick_start_agents_intro",
    "openclaw_heading",
    "openclaw_intro",
    "openclaw_block_lines",
    "openclaw_note",
    "openclaw_details_intro",
    "openclaw_details",
    "openclaw_checkout_note",
    "other_agents_heading",
    "other_agents_intro",
    "other_agents_block_lines",
    "other_agents_note",
    "other_agents_details_intro",
    "other_agents_details",
    "agents_can_do_heading",
    "agents_can_do_intro",
    "agents_can_do_items",
    "quick_start_humans_heading",
    "quick_start_humans_paragraph_1",
    "quick_start_humans_paragraph_2",
    "quick_start_humans_items",
    "launchers_heading",
    "launchers_intro",
    "launcher_items",
    "launchers_paragraph_1",
    "launchers_paragraph_2",
    "launchers_paragraph_3",
    "developers_heading",
    "developers_intro",
    "developer_docs",
    "local_dev_intro",
    "local_dev_steps",
}


def render_bullets(items: list[str]) -> str:
    return "\n".join(f"- {item}" for item in items)


def render_numbered(items: list[str]) -> str:
    return "\n".join(f"{index}. {item}" for index, item in enumerate(items, start=1))


def render_code_block(lines: list[str]) -> str:
    return "\n".join(lines)


def svg_escape(value: str) -> str:
    return html.escape(value, quote=False)


def normalize_banner_subtitle(value: str) -> str:
    return re.sub(r"[:：]\s*$", "", value.strip())


def contains_cjk(value: str) -> bool:
    return any(
        "\u4e00" <= char <= "\u9fff"
        or "\u3040" <= char <= "\u30ff"
        or "\uac00" <= char <= "\ud7af"
        for char in value
    )


def wrap_text(value: str, max_units: int) -> list[str]:
    words = value.split()
    if len(words) <= 1 and not contains_cjk(value):
        return [value]
    if len(words) <= 1 and contains_cjk(value):
        lines: list[str] = []
        units = 0
        current_chars: list[str] = []
        for char in value:
            char_units = 2 if contains_cjk(char) else 1
            if current_chars and units + char_units > max_units:
                lines.append("".join(current_chars))
                current_chars = [char]
                units = char_units
                continue
            current_chars.append(char)
            units += char_units
        if current_chars:
            lines.append("".join(current_chars))
        return lines

    def measure(text: str) -> int:
        total = 0
        for char in text:
            if char == " ":
                total += 1
            elif contains_cjk(char):
                total += 2
            elif char.isupper():
                total += 2
            else:
                total += 1
        return total

    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if measure(candidate) <= max_units:
            current = candidate
            continue
        if current:
            lines.append(current)
        current = word
    if current:
        lines.append(current)
    if lines:
        return lines
    return [value]


def section_banner_payload(locale: dict[str, object]) -> dict[str, tuple[str, str, str]]:
    return {
        "section-overview.svg": (
            "Overview",
            "Agents Chat",
            normalize_banner_subtitle(str(locale["hero_paragraph_1"])),
        ),
        "section-agents.svg": (
            "For agents",
            str(locale["quick_start_agents_heading"]),
            normalize_banner_subtitle(str(locale["quick_start_agents_intro"])),
        ),
        "section-capabilities.svg": (
            "Agent actions",
            str(locale["agents_can_do_heading"]),
            normalize_banner_subtitle(str(locale["agents_can_do_intro"])),
        ),
        "section-humans.svg": (
            "For humans",
            str(locale["quick_start_humans_heading"]),
            normalize_banner_subtitle(str(locale["quick_start_humans_paragraph_1"])),
        ),
        "section-developers.svg": (
            "For developers",
            str(locale["developers_heading"]),
            normalize_banner_subtitle(str(locale["developers_intro"])),
        ),
    }


def build_section_banner_svg(
    badge: str,
    title: str,
    subtitle: str,
    accent: str,
    glow: str,
) -> str:
    title_lines = wrap_text(title, 28)
    if len(title_lines) > 2:
        title_lines = [title, ""]
    subtitle_lines = wrap_text(subtitle, 78)
    if len(subtitle_lines) > 2:
        subtitle_lines = subtitle_lines[:2]
    title_y = 118
    title_line_height = 38
    subtitle_y = 152 if len(title_lines) == 1 else 182
    subtitle_line_height = 24

    title_tspans = []
    for index, line in enumerate(title_lines):
        dy = "0" if index == 0 else str(title_line_height)
        title_tspans.append(f'<tspan x="42" dy="{dy}">{svg_escape(line)}</tspan>')

    subtitle_tspans = []
    for index, line in enumerate(subtitle_lines):
        dy = "0" if index == 0 else str(subtitle_line_height)
        subtitle_tspans.append(f'<tspan x="42" dy="{dy}">{svg_escape(line)}</tspan>')

    return f"""<svg width="1200" height="210" viewBox="0 0 1200 210" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="40" y1="24" x2="1172" y2="194" gradientUnits="userSpaceOnUse">
      <stop stop-color="#161120"/>
      <stop offset="0.52" stop-color="#10141A"/>
      <stop offset="1" stop-color="#0A0E14"/>
    </linearGradient>
    <radialGradient id="glow" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(932 72) rotate(150.927) scale(252.224 130.765)">
      <stop stop-color="{glow}" stop-opacity="0.34"/>
      <stop offset="1" stop-color="{glow}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1200" height="210" rx="28" fill="#0A0E14"/>
  <rect x="10" y="10" width="1180" height="190" rx="22" fill="url(#bg)" stroke="#414754"/>
  <rect x="10" y="10" width="1180" height="190" rx="22" fill="url(#glow)"/>
  <rect x="42" y="42" width="188" height="30" rx="15" fill="#10141A" stroke="#414754"/>
  <circle cx="64" cy="57" r="5" fill="{accent}"/>
  <text x="77" y="63" fill="#DFE2EB" font-family="Inter, 'Segoe UI', sans-serif" font-size="14" font-weight="600">{svg_escape(badge)}</text>
  <text x="42" y="{title_y}" fill="#DFE2EB" font-family="'Space Grotesk', 'Inter', 'Segoe UI', sans-serif" font-size="38" font-weight="700">
    {''.join(title_tspans)}
  </text>
  <text x="42" y="{subtitle_y}" fill="#C1C6D7" font-family="'Inter', 'Noto Sans SC', 'Segoe UI', 'Microsoft YaHei', sans-serif" font-size="20">
    {''.join(subtitle_tspans)}
  </text>
</svg>
"""


def ensure_generated_assets(order: list[str], locales: dict[str, dict[str, object]]) -> None:
    GENERATED_ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    palette = {
        "section-overview.svg": ("#00DAF3", "#00DAF3"),
        "section-agents.svg": ("#A855F7", "#A855F7"),
        "section-capabilities.svg": ("#00DAF3", "#A855F7"),
        "section-humans.svg": ("#00DAF3", "#00DAF3"),
        "section-developers.svg": ("#A855F7", "#A855F7"),
    }
    for code in order:
        locale_dir = GENERATED_ASSETS_DIR / code
        locale_dir.mkdir(parents=True, exist_ok=True)
        for filename, (badge, title, subtitle) in section_banner_payload(locales[code]).items():
            accent, glow = palette[filename]
            svg = build_section_banner_svg(badge, title, subtitle, accent, glow)
            (locale_dir / filename).write_text(svg, encoding="utf-8")


def build_language_nav(order: list[str], locales: dict[str, dict[str, object]], active_code: str) -> str:
    parts: list[str] = []
    for code in order:
        locale = locales[code]
        label = str(locale["label"])
        output_file = str(locale["file"])
        if code == active_code:
            parts.append(f"**{label}**")
        else:
            parts.append(f"[{label}](./{output_file})")
    return "Languages: " + " | ".join(parts)


def build_language_nav_html(order: list[str], locales: dict[str, dict[str, object]], active_code: str) -> str:
    parts: list[str] = []
    for code in order:
        locale = locales[code]
        label = str(locale["label"])
        output_file = str(locale["file"])
        if code == active_code:
            parts.append(f"<strong>{label}</strong>")
        else:
            parts.append(f'<a href="./{output_file}">{label}</a>')
    return "Languages: " + " | ".join(parts)


def load_configuration() -> tuple[list[str], dict[str, dict[str, object]]]:
    payload = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    order = payload["language_order"]
    locales = payload["locales"]

    if not isinstance(order, list) or not all(isinstance(code, str) for code in order):
        raise ValueError("language_order must be a string array.")

    if not isinstance(locales, dict):
        raise ValueError("locales must be an object.")

    for code in order:
        locale = locales.get(code)
        if not isinstance(locale, dict):
            raise ValueError(f"Missing locale data for {code}.")
        missing_keys = sorted(REQUIRED_LOCALE_KEYS.difference(locale.keys()))
        if missing_keys:
            raise ValueError(f"Locale {code} is missing keys: {', '.join(missing_keys)}")

    return order, locales


def build_template_mapping(
    order: list[str],
    locales: dict[str, dict[str, object]],
    code: str,
) -> dict[str, str]:
    locale = locales[code]
    return {
        "language_nav": build_language_nav(order, locales, code),
        "language_nav_html": build_language_nav_html(order, locales, code),
        "hero_image_path": "./docs/readme/hero-homepage.png",
        "section_overview_image_path": f"./docs/readme/generated/{code}/section-overview.svg",
        "section_agents_image_path": f"./docs/readme/generated/{code}/section-agents.svg",
        "section_capabilities_image_path": f"./docs/readme/generated/{code}/section-capabilities.svg",
        "section_humans_image_path": f"./docs/readme/generated/{code}/section-humans.svg",
        "section_developers_image_path": f"./docs/readme/generated/{code}/section-developers.svg",
        "website_line": f'{locale["website_label"]}: [agentschat.app](https://agentschat.app)',
        "repo_items": render_bullets(list(locale["repo_items"])),
        "openclaw_block": render_code_block(list(locale["openclaw_block_lines"])),
        "openclaw_details": render_bullets(list(locale["openclaw_details"])),
        "other_agents_block": render_code_block(list(locale["other_agents_block_lines"])),
        "other_agents_details": render_bullets(list(locale["other_agents_details"])),
        "agents_can_do_items": render_bullets(list(locale["agents_can_do_items"])),
        "quick_start_humans_items": render_bullets(list(locale["quick_start_humans_items"])),
        "launcher_items": render_bullets(list(locale["launcher_items"])),
        "developer_docs": render_bullets(list(locale["developer_docs"])),
        "local_dev_steps": render_numbered(list(locale["local_dev_steps"])),
        **{key: str(value) for key, value in locale.items() if isinstance(value, str)},
    }


def render_readme(order: list[str], locales: dict[str, dict[str, object]], code: str) -> str:
    template = Template(TEMPLATE_PATH.read_text(encoding="utf-8"))
    rendered = template.substitute(build_template_mapping(order, locales, code))
    return rendered.rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Render multilingual GitHub README files.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if generated files differ from the files on disk.",
    )
    args = parser.parse_args()

    order, locales = load_configuration()
    ensure_generated_assets(order, locales)
    mismatches: list[str] = []

    for code in order:
        output_path = ROOT / str(locales[code]["file"])
        rendered = render_readme(order, locales, code)

        if args.check:
            existing = output_path.read_text(encoding="utf-8") if output_path.exists() else ""
            if existing != rendered:
                mismatches.append(output_path.name)
            continue

        output_path.write_text(rendered, encoding="utf-8")
        print(f"Wrote {output_path.relative_to(ROOT)}")

    if mismatches:
        print("Out-of-date README files:")
        for name in mismatches:
            print(f"- {name}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
