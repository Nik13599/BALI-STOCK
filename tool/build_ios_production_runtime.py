from __future__ import annotations

import argparse
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_URL = "https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-ios-runtime"
RUNTIME_SOURCE_URL = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime/production/bali-stock.html"
MOBILE_STOCKTAKE_MODULE = ROOT / "ios-web" / "mobile-stocktake-compact-v105.js"
MODULES = {
    "bali-v15-ui": ROOT / "ios-web" / "v15-ui.js",
    "bali-v15-delivery-link": ROOT / "ios-web" / "v15-delivery-link.js",
    "bali-v15-compat": ROOT / "ios-web" / "v15-compat.js",
    "bali-v16-catalog-history": ROOT / "ios-web" / "v16-catalog-history.js",
}


def read_version() -> tuple[str, int]:
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", text, re.M)
    if not match:
        raise SystemExit("Invalid pubspec version")
    return match.group(1), int(match.group(2))


def fetch_current_runtime() -> str:
    request = urllib.request.Request(
        RUNTIME_SOURCE_URL + "?builder=1",
        headers={"Accept": "text/html,*/*", "Cache-Control": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
    return raw.decode("utf-8")


def embed_script(html: str, script_id: str, source: str) -> str:
    safe = source.replace("</script", "<\\/script")
    replacement = f'<script id="{script_id}">{safe}</script>'
    pattern = re.compile(rf'<script\s+id=["\']{re.escape(script_id)}["\'][^>]*>[\s\S]*?</script>', re.I)
    updated, count = pattern.subn(lambda _: replacement, html, count=1)
    if count != 1:
        raise SystemExit(f"Embedded script not found exactly once: {script_id} ({count})")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description="Build self-contained BALI STOCK iPhone production runtime")
    parser.add_argument("--output", default="dist/ios-runtime/bali-stock.html")
    args = parser.parse_args()

    version, build = read_version()
    html = fetch_current_runtime()
    if not re.match(r"^\s*<!doctype html>", html, re.I) or "BALI STOCK" not in html:
        raise SystemExit("Current Supabase runtime is invalid")

    for script_id, path in MODULES.items():
        html = embed_script(html, script_id, path.read_text(encoding="utf-8"))

    mobile_source = MOBILE_STOCKTAKE_MODULE.read_text(encoding="utf-8").replace("</script", "<\\/script")
    mobile_script = f'<script id="bali-mobile-stocktake-compact-v105">{mobile_source}</script>'
    html = re.sub(r'<script\s+id=["\']bali-mobile-stocktake-compact-v105["\'][^>]*>[\s\S]*?</script>', '', html, count=1, flags=re.I)
    html = html.replace("</body>", mobile_script + "</body>", 1)

    html = re.sub(
        r"window\.__BALI_STOCK_SUPABASE_RUNTIME__\s*=\s*['\"][^'\"]+['\"]\s*;",
        f"window.__BALI_STOCK_SUPABASE_RUNTIME__='{version}';",
        html,
        count=1,
    )
    release_marker = f"<script>window.__BALI_STOCK_RELEASE_VERSION__='{version}';window.__BALI_STOCK_RELEASE_BUILD__={build};</script>"
    html = re.sub(r"<script>window\.__BALI_STOCK_RELEASE_VERSION__=[\s\S]*?</script>", "", html, count=1)
    html = html.replace("</body>", release_marker + "</body>", 1)

    required = [
        "__BALI_STOCK_SUPABASE_RUNTIME__",
        "__BALI_STOCK_RELEASE_VERSION__",
        "bali-stock-client-api",
        "__BALI_STOCK_V15_UI__",
        "__BALI_STOCK_V15_DELIVERY_LINK__",
        "__BALI_STOCK_V15_COMPAT__",
        "__BALI_STOCK_V16_CATALOG_HISTORY__",
        "__BALI_STOCK_MOBILE_STOCKTAKE_COMPACT__",
    ]
    missing = [value for value in required if value not in html]
    if missing:
        raise SystemExit(f"Runtime markers missing: {missing}")

    forbidden = [
        "raw.githack.com",
        "raw.githubusercontent.com/Nik13599/BALI-STOCK",
        "Введите пароль доступа",
        "Пароль не введён",
        "Неверный пароль",
        "x-bali-stock-pin",
    ]
    found = [value for value in forbidden if value in html]
    if found:
        raise SystemExit(f"Forbidden runtime content remains: {found}")

    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html, encoding="utf-8")
    print(f"{output} | version={version}+{build} | bytes={output.stat().st_size}")


if __name__ == "__main__":
    main()
