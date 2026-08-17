# Offline-first acceptance test

1. Start app online and let warehouse sync.
2. Disable Wi-Fi/mobile data.
3. Reopen app: warehouse and history must load from SQLite.
4. Enter operation PIN and create a delivery: local balance/history must change immediately.
5. Close and reopen app while still offline: local change and pending-sync warning must remain.
6. Complete a stocktake offline: completed local history must remain and draft must disappear locally.
7. Restore network while app remains open: pending queue must drain automatically.
8. Verify another device receives the new shared balance/history.
9. Retry the same queued client action ID against `bali-stock-sync-api`: server must return duplicate without applying stock movement twice.
10. Scan a QR/barcode on Android/iOS and verify product lookup and barcode binding.

CI retry note: Linux jobs may be retried when GitHub codeload returns 429 before Flutter setup; this is infrastructure-only and occurs before project code runs.
