# iPhone installation

The `.mobileconfig` Web Clip approach is deprecated for BALI STOCK because it cannot reliably satisfy the required offline-first behavior.

The supported iPhone target is the native Flutter iOS application. It stores its SQLite database locally and can operate without network access.

To install the native build on a physical iPhone, Apple code signing is required. The repository CI can create an unsigned `Runner.app`, but a real device install requires one of:
- Apple Developer certificate + provisioning profile (recommended for stable internal distribution / TestFlight), or
- local Xcode signing for a registered device.

Do not distribute future BALI STOCK releases as `.mobileconfig` Web Clips.
