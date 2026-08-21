# BALI STOCK production runtime

- GitHub stores source code, CI and a verified camera-safe copy of the iPhone runtime.
- Windows and Android use `bali-stock-client-api` on Supabase.
- iPhone Web Clip keeps the stable `bali-stock-ios-runtime` Supabase URL used by the 1.0.5 profile.
- The Edge Function selects GitHub Pages only when it contains the scanner and frozen visual-contract markers; otherwise it preserves the 1.0.5 launcher.
- The scanner library is embedded into the published runtime; it does not depend on a scanner CDN at launch.
- Application data and mutations continue to use the protected Supabase Edge Functions.
- User-facing passwords and PIN prompts are not part of the production workflow.
- Future iPhone releases keep the same Web Clip URL and icon; GitHub Actions deploys and verifies the camera host without changing the interface.
