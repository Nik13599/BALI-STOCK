# BALI STOCK production runtime

- GitHub stores source code, CI and the public camera-safe iPhone HTTPS document.
- Windows and Android use `bali-stock-client-api` on Supabase.
- iPhone Web Clip opens `https://nik13599.github.io/BALI-STOCK/` directly as a top-level secure document.
- `bali-stock-ios-runtime` remains as a compatibility redirect for profiles installed before 1.0.6.
- The scanner library is embedded into the published runtime; it does not depend on a scanner CDN at launch.
- Application data and mutations continue to use the protected Supabase Edge Functions.
- User-facing passwords and PIN prompts are not part of the production workflow.
- Future iPhone releases keep the same Web Clip URL; GitHub Actions deploys the verified runtime before publishing installers.
