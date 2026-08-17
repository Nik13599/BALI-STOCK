# BALI STOCK runtime hotfix V8

- Windows release artifact now bundles Microsoft VC143 CRT DLLs next to `bali_stock.exe`, so a clean PC does not need a separately preinstalled Visual C++ Redistributable just to start the app.
- Flutter shell is mounted before controller initialization; startup/database failures are shown on screen instead of causing a silent exit/spinner.
- iPhone Web Clip is served directly from the `bali-stock-ios` Supabase Edge Function. The old `htmlpreview.github.io` chain is no longer used by the V8 profile.
