"""Reuse the App's Noto Sans SC for Web UI; regenerate after changing UI text.
Requires fonttools and brotli. No dependency on this script at Web build/runtime.
Uncommon user-content glyphs fall back to the OS's Chinese sans-serif font.
"""
from pathlib import Path
from fontTools import subset

root = Path(__file__).resolve().parents[1]
chars = set(range(32, 127))
sources = list((root / "app/lib/l10n").glob("app_zh*.arb"))
for directory in ("web/app", "web/components", "server/scripts"):
    sources += [p for p in (root / directory).rglob("*") if p.suffix in (".tsx", ".cjs")]
for path in sources:
    chars.update(map(ord, path.read_text(encoding="utf-8")))
options = subset.Options()
options.flavor = "woff2"
options.layout_features = ["*"]
font = subset.load_font(str(root / "app/assets/fonts/NotoSansSC-Variable.ttf"), options)
subsetter = subset.Subsetter(options=options)
subsetter.populate(unicodes=chars)
subsetter.subset(font)
output = root / "web/public/fonts/NotoSansSC-UI.woff2"
subset.save_font(font, str(output), options)
print(f"{output.name}: {output.stat().st_size:,} bytes, {len(font.getBestCmap())} characters")
