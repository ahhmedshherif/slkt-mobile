# Flutter Buyer App Repository Memory

Verified 2026-08-31. This repository is the buyer-only TKTS APP Flutter client.

- Production API default: `https://tktsapp.com/api/v1`.
- Version at verification: `2.5.0+4010`; Dart SDK constraint `^3.11.1`.
- Session routing supports `guest` and `buyer` only. `SessionController.restore()` removes staff tokens left by older versions.
- `lib/src/features/staff/staff_shell.dart` is dormant prototype code and is not imported by `app.dart`. Do not reconnect organizer/admin/scanner login in this buyer app.
- The approved future `TKTSAPP Organizers` direction is a separate Flutter project combining organizer operations and scanner kiosk; it has not been implemented here.
- Android package and iOS bundle are `com.tktsapp.jumpersagency`; this is a new store identity approved for the TKTS APP relaunch.
- App links accept `https://tktsapp.com/tickets/*` plus legacy `slkt://tickets`.
- Only `API_BASE_URL` and public OneSignal App ID belong in builds. No Paymob secret/HMAC, SMSMisr, OneSignal REST, DB, FTP or signing credential may enter Flutter.
- Laravel is authoritative for prices, inventory holds, payment state, tickets, transfer ownership and QR validity.
- Paymob navigation remains host-allowlisted; closing the WebView must recover order state from Laravel.
- Secure storage holds buyer tokens and offline/pending buyer data. Clear private cache at logout.
- Maintain deep links, OneSignal identity/click routing, offline ticket cache, screenshot/privacy behavior and server-synchronized checkout expiry.
- Validate changes with `flutter analyze`, `flutter test`, and the affected Android/iOS release configuration.

In the combined workspace, the full cross-project memory is `../docs/AI_PROJECT_MEMORY.md` and the graph is `../docs/ARCHITECTURE_GRAPH.md`.
