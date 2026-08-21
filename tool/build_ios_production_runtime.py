from __future__ import annotations

import argparse
import hashlib
import re
import urllib.request
from pathlib import Path

from visual_contract_check import VISUAL_CONTRACT, verify_visual_contract

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_URL = "https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1/bali-stock-ios-runtime"
RUNTIME_SOURCE_URL = "https://mvnxfouyoynqyjdpcblh.supabase.co/storage/v1/object/public/bali-stock-runtime/production/bali-stock.html"
SCANNER_LIBRARY_URL = "https://cdn.jsdelivr.net/npm/html5-qrcode@2.3.8/html5-qrcode.min.js"
SCANNER_LIBRARY_SHA256 = "660b12437b1d747e3e68b8be0685c08cb728140110ad213f167b14b66f8b1d8e"
SCANNER_COMPAT_MODULE = ROOT / "ios-web" / "ios-scanner-compat.js"
PERFORMANCE_MODULE = ROOT / "ios-web" / "ios-runtime-performance.js"
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


def fetch_scanner_library() -> str:
    request = urllib.request.Request(
        SCANNER_LIBRARY_URL,
        headers={"Accept": "application/javascript,*/*", "Cache-Control": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != SCANNER_LIBRARY_SHA256:
        raise SystemExit(f"html5-qrcode checksum mismatch: {digest}")
    return raw.decode("utf-8")


def embed_script(html: str, script_id: str, source: str) -> str:
    safe = source.replace("</script", "<\\/script")
    replacement = f'<script id="{script_id}">{safe}</script>'
    pattern = re.compile(rf'<script\s+id=["\']{re.escape(script_id)}["\'][^>]*>[\s\S]*?</script>', re.I)
    updated, count = pattern.subn(lambda _: replacement, html, count=1)
    if count != 1:
        raise SystemExit(f"Embedded script not found exactly once: {script_id} ({count})")
    return updated


def inline_scanner_library(html: str) -> str:
    source = fetch_scanner_library().replace("</script", "<\\/script")
    replacement = f'<script id="bali-html5-qrcode-v238">{source}</script>'
    pattern = re.compile(
        r'<script\s+src=["\']https://cdn\.jsdelivr\.net/npm/html5-qrcode@2\.3\.8/html5-qrcode\.min\.js["\'][^>]*>\s*</script>',
        re.I,
    )
    updated, count = pattern.subn(lambda _: replacement, html, count=1)
    if count != 1:
        raise SystemExit(f"html5-qrcode external script not found exactly once ({count})")
    return updated


def append_script(html: str, script_id: str, source: str) -> str:
    safe = source.replace("</script", "<\\/script")
    script = f'<script id="{script_id}">{safe}</script>'
    html = re.sub(
        rf'<script\s+id=["\']{re.escape(script_id)}["\'][^>]*>[\s\S]*?</script>',
        "",
        html,
        count=1,
        flags=re.I,
    )
    if "</body>" not in html:
        raise SystemExit("Runtime body closing tag is missing")
    return html.replace("</body>", script + "</body>", 1)


def visual_shell(html: str) -> str:
    return re.sub(r"<script\b[^>]*>[\s\S]*?</script>", "", html, flags=re.I)


def harden_runtime_polling(html: str) -> str:
    pattern = re.compile(r"setInterval\(\(\)=>snapshot\(\)\.catch\(\(\)=>\{\}\),5000\)")
    replacement = (
        "setInterval(()=>{if(typeof window.baliPollSnapshotVersion==='function')"
        "window.baliPollSnapshotVersion();else if(!document.hidden)snapshot().catch(()=>{})},15000)"
    )
    updated, count = pattern.subn(replacement, html, count=1)
    if count != 1:
        raise SystemExit(f"Legacy full-snapshot polling loop not found exactly once ({count})")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description="Build self-contained BALI STOCK iPhone production runtime")
    parser.add_argument("--output", default="dist/ios-runtime/bali-stock.html")
    args = parser.parse_args()

    verify_visual_contract()
    version, build = read_version()
    html = fetch_current_runtime()
    if not re.match(r"^\s*<!doctype html>", html, re.I) or "BALI STOCK" not in html:
        raise SystemExit("Current Supabase runtime is invalid")

    original_visual_shell = visual_shell(html)

    for script_id, path in MODULES.items():
        html = embed_script(html, script_id, path.read_text(encoding="utf-8"))

    html = harden_runtime_polling(html)
    html = inline_scanner_library(html)
    html = append_script(html, "bali-ios-runtime-performance", PERFORMANCE_MODULE.read_text(encoding="utf-8"))
    html = append_script(html, "bali-ios-scanner-compat", SCANNER_COMPAT_MODULE.read_text(encoding="utf-8"))
    html = append_script(html, "bali-mobile-stocktake-compact-v105", MOBILE_STOCKTAKE_MODULE.read_text(encoding="utf-8"))

    html = re.sub(
        r"window\.__BALI_STOCK_SUPABASE_RUNTIME__\s*=\s*['\"][^'\"]+['\"]\s*;",
        f"window.__BALI_STOCK_SUPABASE_RUNTIME__='{version}';",
        html,
        count=1,
    )
    release_marker = (
        f"<script>window.__BALI_STOCK_RELEASE_VERSION__='{version}';"
        f"window.__BALI_STOCK_RELEASE_BUILD__={build};"
        f"window.__BALI_STOCK_VISUAL_CONTRACT__='{VISUAL_CONTRACT}';</script>"
    )
    html = re.sub(r"<script>window\.__BALI_STOCK_RELEASE_VERSION__=[\s\S]*?</script>", "", html, count=1)
    html = html.replace("</body>", release_marker + "</body>", 1)

    required = [
        "__BALI_STOCK_SUPABASE_RUNTIME__",
        "__BALI_STOCK_RELEASE_VERSION__",
        "__BALI_STOCK_VISUAL_CONTRACT__",
        "bali-stock-client-api",
        "__BALI_STOCK_V15_UI__",
        "__BALI_STOCK_V15_DELIVERY_LINK__",
        "__BALI_STOCK_V15_COMPAT__",
        "__BALI_STOCK_V16_CATALOG_HISTORY__",
        "__BALI_STOCK_IOS_SCANNER_COMPAT__",
        "__BALI_STOCK_IOS_RUNTIME_PERFORMANCE__",
        "__BALI_STOCK_MOBILE_STOCKTAKE_COMPACT__",
        "bali-html5-qrcode-v238",
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
        "cdn.jsdelivr.net/npm/html5-qrcode",
    ]
    found = [value for value in forbidden if value in html]
    if found:
        raise SystemExit(f"Forbidden runtime content remains: {found}")

    if visual_shell(html) != original_visual_shell:
        raise SystemExit("iPhone visual shell changed while applying technical runtime fixes")

    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html, encoding="utf-8")
    print(f"{output} | version={version}+{build} | bytes={output.stat().st_size}")


if __name__ == "__main__":
    main()
