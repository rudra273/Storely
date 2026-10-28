# Storely

Flutter inventory and billing for Android. Free use stores business records in
SQLite and works without an account or server. Storely API is the only cloud backend.

Premium cloud access and the developer console are being delivered phase by phase;
see [plan.md](plan.md). Premium requests and verified activation are implemented;
cloud business access requires an active server subscription. For local API integration:

```sh
flutter run --dart-define=STORELY_API_URL=https://api.example.com
```

Use `STORELY_DEV_CA_B64` for a local development CA in debug builds only. No backend
URL/key setup is exposed to users. Legacy cloud preferences are retired without
clearing SQLite; API onboarding is explicit. The `supabase/` directory contains
historical schema/test artifacts only and is not shipped as an app integration.

Checks: `flutter analyze`, `flutter test`, `flutter build apk --release`.

Premium sync covers 17 tables, including held/draft carts and nine portable
preferences. A clean restore rebuilds local IDs from UUIDs. Other-device carts
are view-only backups; only their original device can resume them. Printer pairing
and app lock stay local. See [data mapping](docs/DATA_MODEL_PARITY.md) and
[restore verification](docs/PHASE12_VERIFICATION.md).
