from __future__ import annotations

import json
import urllib.error
import urllib.request

BASE = "https://mvnxfouyoynqyjdpcblh.supabase.co/functions/v1"
CLIENT_KEY = "sb_publishable_Tq2niBP0_2KuzTEuip8Oeg_1HhCUo29"


def request(path: str, *, method: str = "GET", key: bool = False, body: dict | None = None) -> tuple[int, dict]:
    headers = {"Accept": "application/json", "Cache-Control": "no-cache"}
    if key:
        headers["apikey"] = CLIENT_KEY
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=35) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw or "{}")
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8")
        try:
            payload = json.loads(raw or "{}")
        except json.JSONDecodeError:
            payload = {"raw": raw}
        return error.code, payload


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> None:
    status, runtime = request("/bali-stock-ios-runtime?health=1&backend_smoke=1")
    require(status == 200 and runtime.get("ok") is True, f"runtime health failed: {status} {runtime}")
    require(runtime.get("web_app") == "https://nik13599.github.io/BALI-STOCK/", f"unexpected iPhone page: {runtime}")
    require(runtime.get("interface_guard") is True, f"runtime interface guard is disabled: {runtime}")
    require(bool(runtime.get("active_target")), f"runtime target is missing: {runtime}")
    require(runtime.get("password_prompt") is False, f"runtime password flow returned: {runtime}")

    status, snapshot = request("/bali-stock-client-api?action=snapshot&backend_smoke=1", key=True)
    require(status == 200, f"client snapshot failed: {status} {snapshot}")
    products = snapshot.get("products") or []
    locations = snapshot.get("locations") or []
    version = int(snapshot.get("version") or 0)
    require(len(products) > 0, "production snapshot contains no products")
    require(len(locations) > 0, "production snapshot contains no stock locations")
    require(version > 0, f"invalid production sync version: {version}")

    status, version_payload = request("/bali-stock-client-api?action=version&backend_smoke=1", key=True)
    require(status == 200, f"client version failed: {status} {version_payload}")
    require(int(version_payload.get("version") or 0) == version, f"snapshot/version mismatch: {version} vs {version_payload}")

    status, sync_no_key = request("/bali-stock-sync-api", method="POST", body={})
    require(status == 401, f"sync API must reject missing key: {status} {sync_no_key}")

    status, sync_invalid = request("/bali-stock-sync-api", method="POST", key=True, body={})
    require(status == 400, f"sync API invalid request must be 400: {status} {sync_invalid}")
    require("client_action_id" in str(sync_invalid.get("error", "")), f"unexpected sync validation response: {sync_invalid}")

    status, catalog_no_key = request("/bali-stock-catalog-api", method="POST", body={"action": "unknown"})
    require(status == 401, f"catalog API must reject missing key: {status} {catalog_no_key}")

    status, catalog_unknown = request("/bali-stock-catalog-api", method="POST", key=True, body={"action": "unknown"})
    require(status == 400 and catalog_unknown.get("error") == "UNKNOWN_ACTION", f"catalog API contract failed: {status} {catalog_unknown}")

    status, legacy_no_key = request("/bali-stock-api?action=snapshot&backend_smoke=1")
    require(status == 401, f"legacy API must reject missing key: {status} {legacy_no_key}")

    status, legacy = request("/bali-stock-api?action=snapshot&backend_smoke=1", key=True)
    require(status == 200, f"legacy API snapshot with app key failed: {status} {legacy}")
    require(len(legacy.get("products") or []) == len(products), "legacy/client product count mismatch")
    require(int(legacy.get("version") or 0) == version, "legacy/client version mismatch")

    for endpoint in ("bali-stock-ios", "bali-stock-ios-launch"):
        status, health = request(f"/{endpoint}?health=1&backend_smoke=1")
        require(status == 200 and health.get("ok") is True, f"{endpoint} health failed: {status} {health}")
        require(health.get("github_dependency") is False, f"{endpoint} still depends on GitHub: {health}")

    retired = (
        "bali-stock-publish-ios",
        "bali-stock-publish-ios-runtime",
        "bali-stock-host-test",
        "bali-stock-ocr-test",
        "bali-stock-invoice-view",
    )
    for endpoint in retired:
        status, payload = request(f"/{endpoint}")
        require(status == 410, f"retired endpoint {endpoint} is still active: {status} {payload}")

    print(json.dumps({
        "ok": True,
        "runtime_version": runtime.get("version"),
        "runtime_build": runtime.get("build"),
        "sync_version": version,
        "products": len(products),
        "locations": len(locations),
        "operations": len(snapshot.get("operations") or []),
        "drafts": len(snapshot.get("drafts") or []),
        "retired_endpoints": len(retired),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
