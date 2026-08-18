# Codemagic release pipeline

The repository root contains `codemagic.yaml` with two workflows:

- `android-release` builds a release APK and AAB.
- `ios-release` builds a signed App Store IPA.

Both workflows compile against `https://slktegy.com/api/v1` through the
`API_BASE_URL` Dart define. No backend or signing secrets are stored in Git.

## One-time Codemagic setup

1. Add this GitHub repository as a Flutter application in Codemagic.
2. For iOS, add an App Store Connect API key under the team's integrations.
3. Upload or fetch an App Store distribution certificate and provisioning
   profile matching `com.slktegy.evntsApp` under Code signing identities.
4. Run `SLKT Android APK & AAB` or `SLKT iOS IPA` from the `main` branch.

Android currently keeps the project's existing signing behavior so the APK can
be installed immediately. Before a Play Store release, upload the permanent
upload keystore to Codemagic and switch Gradle to that same key for every future
release.
