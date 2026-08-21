from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VISUAL_CONTRACT = "release-1.0.5"
EXPECTED_PROFILE_SHA256 = "5e1b198bdaffddcb194dbd03f5c90ee0844c7a2f092403ea423f57801abe0519"

BINARY_HASHES = {
    "assets/branding/bali_stock_logo.png": "48f0f9b091e061a149a15a2a96daaf36d718c5c783625dc227ee246dc585ee8a",
}

TEXT_HASHES = {
    "assets/branding/bali_stock_logo.svg": "39bcc2fcbcf8146da8a3070b8b0389acc63c281342853948eb0836b8b0d302ca",
    "ios-web/v14-scan-workflows.js": "894f962a653acb2a19161723d1cb9aee5a629826475c8707b82bcd13d05e7d5e",
    "ios-web/v15-ui.js": "f58ae884a317523464311a83d0372617b7a349a07fbda12ece72df071b19dbf5",
    "ios-web/v15-delivery-link.js": "df0ce1ce86cbd94717deb0681717d5e5fe913f610804d9c83711494d409a2588",
    "ios-web/v15-compat.js": "a9e51aca12da6bfc45b996edcb0178e7eb6ab5a48a293832f7287ff38968dc0c",
    "ios-web/v16-catalog-history.js": "625fde691e5e89e2cfad234638c5fa7e801db6d525349235035365268a31591a",
    "ios-web/mobile-stocktake-compact-v105.js": "533d6a9893eaf437a23e0b283d8ea403c00cc04eae29a54cad98973c56bbeb6c",
}

FLUTTER_UI_SHA256 = "0630555eec08864847106773d5f991c87b9a1000e21bda9de20866cc9d5fd7e2"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalized_text(path: Path) -> bytes:
    return path.read_bytes().replace(b"\r\n", b"\n")


def verify_visual_contract(profile: Path | None = None) -> None:
    failures: list[str] = []
    for relative, expected in BINARY_HASHES.items():
        actual = digest((ROOT / relative).read_bytes())
        if actual != expected:
            failures.append(f"{relative}: {actual}")
    for relative, expected in TEXT_HASHES.items():
        actual = digest(normalized_text(ROOT / relative))
        if actual != expected:
            failures.append(f"{relative}: {actual}")

    ui_files = sorted({
        *ROOT.glob("lib/screens/*.dart"),
        *ROOT.glob("lib/widgets/*.dart"),
    })
    ui = hashlib.sha256()
    for path in ui_files:
        ui.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        ui.update(b"\0")
        ui.update(normalized_text(path))
        ui.update(b"\0")
    if ui.hexdigest() != FLUTTER_UI_SHA256:
        failures.append(f"Flutter screens/widgets: {ui.hexdigest()}")

    pubspec = normalized_text(ROOT / "pubspec.yaml").decode("utf-8")
    required_config = [
        "image_path: assets/branding/bali_stock_logo.png",
        'adaptive_icon_background: "#101A1F"',
        "adaptive_icon_foreground: assets/branding/bali_stock_logo.png",
    ]
    for marker in required_config:
        if marker not in pubspec:
            failures.append(f"pubspec icon config missing: {marker}")

    installer = normalized_text(ROOT / "installer/windows/bali_stock.iss").decode("utf-8")
    if "SetupIconFile=..\\..\\windows\\runner\\resources\\app_icon.ico" not in installer:
        failures.append("Windows installer icon source changed")

    if profile is not None:
        actual = digest(profile.read_bytes())
        if actual != EXPECTED_PROFILE_SHA256:
            failures.append(f"mobileconfig: {actual}")

    if failures:
        raise SystemExit("Visual contract changed:\n- " + "\n- ".join(failures))
    print(f"Visual contract {VISUAL_CONTRACT}: OK")


def main() -> None:
    parser = argparse.ArgumentParser(description="Protect BALI STOCK 1.0.5 interface and icons")
    parser.add_argument("--mobileconfig", type=Path)
    args = parser.parse_args()
    verify_visual_contract(args.mobileconfig)


if __name__ == "__main__":
    main()
