# EvntsApp Flutter

Production Flutter client for the EvntsApp ticketing platform. The visual system is based on the approved Google Stitch mobile screens in `design_reference/`.

## Production API

The default API base URL is:

```text
https://slktegy.com/api/v1
```

Override it for local or staging builds without changing source code:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8085/api/v1
```

No database, SMS gateway, FTP, or administrator credentials belong in this app. All sensitive actions are performed by Laravel.

## Included flows

- Buyer OTP, email/password login, registration, password reset, and phone verification
- Mandatory name/email/password completion after OTP when a phone has no completed account
- Six-cell OTP input with 60-second resend cooldown
- Event discovery, event details, checkout handoff, orders, ticket wallet, QR ticket, and one-time PDF download
- Two-party ticket transfers with recipient lookup, sender confirmation, recipient approval/decline, cancellation, and transfer history
- Organizer, event staff, scanner, analytics, team management, and administrator views
- Secure buyer/staff token separation using platform secure storage

## Run and verify

```powershell
flutter pub get
dart analyze lib test
flutter test
flutter run
```

Build the Android release APK:

```powershell
flutter build apk --release
```

The output is `build/app/outputs/flutter-apk/app-release.apk`.

The complete backend contract is documented in `../website/docs/FLUTTER_API_COMPLETE.md` and `../website/docs/openapi-mobile.yaml`.
