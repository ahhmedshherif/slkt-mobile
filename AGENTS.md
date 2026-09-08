# Flutter Buyer App Agent Guide

Before editing, read `docs/AI_PROJECT_MEMORY.md`. In the combined workspace, also read `../docs/ARCHITECTURE_GRAPH.md` and `../docs/SECRETS_AND_ENVIRONMENT.md`.

- This repository is the **buyer-only** TKTS APP Flutter client.
- `lib/src/features/staff/staff_shell.dart` is dormant prototype code and is not part of current routing. Do not reconnect organizer/admin login here.
- Laravel remains authoritative for prices, holds, payments, tickets, transfers and QR validity.
- Only `API_BASE_URL` and the public OneSignal App ID may be compiled into the app; never add backend/provider secrets.
- Production API defaults to `https://tktsapp.com/api/v1`.
- Preserve Android/iOS package identifiers unless an explicit store migration is approved.
- Keep Paymob WebView navigation allowlisted and recover payment status from Laravel.
- Verify with `flutter analyze` and `flutter test`; validate both Android and iOS release configuration for native changes.
