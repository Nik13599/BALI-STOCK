from __future__ import annotations

import argparse
import plistlib
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_URL = "https://raw.githack.com/Nik13599/BALI-STOCK/main/ios-web/launch-v16.html"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate BALI STOCK iPhone Web Clip configuration profile")
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--output", default="dist/ios/BALI-STOCK-iPhone.mobileconfig")
    parser.add_argument("--label", default="BALI STOCK")
    args = parser.parse_args()

    icon = (ROOT / "assets" / "branding" / "bali_stock_logo.png").read_bytes()
    payload_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, args.url + ":webclip")).upper()
    profile_uuid = str(uuid.uuid5(uuid.NAMESPACE_URL, args.url + ":profile")).upper()

    profile = {
        "PayloadContent": [
            {
                "FullScreen": True,
                "Icon": icon,
                "IgnoreManifestScope": False,
                "IsRemovable": True,
                "Label": args.label,
                "PayloadDescription": "Устанавливает актуальную версию BALI STOCK V16 на экран Домой.",
                "PayloadDisplayName": "BALI STOCK",
                "PayloadIdentifier": "com.bali.stock.webclip",
                "PayloadType": "com.apple.webClip.managed",
                "PayloadUUID": payload_uuid,
                "PayloadVersion": 1,
                "Precomposed": True,
                "URL": args.url,
            }
        ],
        "PayloadDescription": "BALI STOCK V16 — складской учёт, закупки, поставки и переучёт BALI.",
        "PayloadDisplayName": "BALI STOCK",
        "PayloadIdentifier": "com.bali.stock.profile",
        "PayloadOrganization": "BALI",
        "PayloadRemovalDisallowed": False,
        "PayloadType": "Configuration",
        "PayloadUUID": profile_uuid,
        "PayloadVersion": 1,
    }

    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as file:
        plistlib.dump(profile, file, fmt=plistlib.FMT_XML, sort_keys=False)
    print(output)


if __name__ == "__main__":
    main()
