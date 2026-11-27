# E17 (Lite) Evidence — Base (v1) Pilot Release Hardening

Date: 2026-11-27

## Scope
Pilot release verification for Base (v1) covering `E00–E03`, `E04.1`, and `E12.1–E12.2` ahead of the user's `E18` hands-on walkthrough and production deployment decision.

## Verified Artifacts & Gates
1. **Clean Android Release APK**:
   - Command: `flutter build apk --release` in `/Users/rudra/projects/Storely`
   - Artifact: `/Users/rudra/projects/Storely/build/app/outputs/flutter-apk/app-release.apk` (`91 MB` / `95.5 MB`)
   - Security check: `android/app/src/main/res/xml/network_security_config.xml` trusts system CAs only (no user/debug CA in release).
   - Feature flag: `STORELY_NATIVE_SALE_POSTING` remains default `false` until user E18 decision.
2. **Backup & Restore (`O12`)**:
   - `flutter test test/native_mixed_version_restore_test.dart` (default) + `--dart-define=STORELY_NATIVE_SALE_POSTING=true`: **6/6 passed** (SQLite v30 schema upgrade, `BackupService` restore, cross-account isolation, opt-in native reservation delivery).
3. **API & Live Docker Stack**:
   - `storelyapi` HEAD `293bf0b`: `make lint` PASS, `make test` **448/448**, `make test-integration` **466/466**, Alembic migration `0029_e04_1_purchase_returns` applied to live DB.
   - `storelyweb` HEAD `441c506`: `make typecheck` PASS, `make api-types-check` PASS, `make lint` PASS (0 warnings/0 errors), `make test` **714/714**, `make build` PASS.
4. **E18 Human Walkthrough Checklist**:
   - Sign in on `https://localhost` and install `app-release.apk` (or use `emulator-5554`).
   - Create a GST invoice with line & fixed document discount, exclusive/inclusive tax mode, and notes; verify A4/A5/80mm/58mm PDF, image share, and WhatsApp text.
   - Record a purchase receipt, pay supplier (partial), post a partial Purchase Return (Debit Note `DN/...`), verify stock & supplier dues match identically between Web and Android.
   - Confirm whether to enable `STORELY_NATIVE_SALE_POSTING=true` before production deploy.
