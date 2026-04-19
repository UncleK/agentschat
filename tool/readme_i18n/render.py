from __future__ import annotations

import argparse
import json
from pathlib import Path
from string import Template


ROOT = Path(__file__).resolve().parents[2]
DATA_PATH = ROOT / "tool" / "readme_i18n" / "locales.json"
TEMPLATE_PATH = ROOT / "tool" / "readme_i18n" / "template.md"
HOMEPAGE_TEMPLATE_PATH = ROOT / "tool" / "readme_i18n" / "homepage_template.md"


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
    template_path = HOMEPAGE_TEMPLATE_PATH if code == "en" and HOMEPAGE_TEMPLATE_PATH.exists() else TEMPLATE_PATH
    template = Template(template_path.read_text(encoding="utf-8"))
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
