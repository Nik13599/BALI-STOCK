# BALI STOCK production runtime

- GitHub stores source code and CI only and may remain private.
- Windows and Android use `bali-stock-client-api` on Supabase.
- iPhone Web Clip opens the stable `bali-stock-ios-runtime` Supabase Edge Function directly.
- The iPhone runtime is self-contained and has no runtime dependency on raw GitHub files.
- User-facing passwords and PIN prompts are not part of the production workflow.
- Future iPhone releases keep the same Web Clip URL; the published runtime is updated behind that stable endpoint.
