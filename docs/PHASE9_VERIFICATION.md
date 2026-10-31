# Phase 9 verification — 2026-10-28

Supabase SDK, transitive clients and both runtime implementations removed.
Backend URL/key inputs and fallback removed. Legacy URL/key and SDK session
preferences retire idempotently; API user preferences and local SQLite remain.
Only explicit API selection can restore an API session. No remote deletion occurs.

Until Phase 10 adds server entitlements, release cloud activation is disabled.
Debug development requires STORELY_API_URL plus STORELY_CLOUD_PREVIEW=true.
A build flag cannot enable preview in profile/release mode.

Security considerations: removing user-selected backend destinations prevents
credentials and business records from being routed to arbitrary projects through
setup. No new endpoint, authorization grant or token storage was introduced.
No destructive SQLite migration was needed. Removed providers' stored sessions
are cleared without invoking their SDK or sending a network request.

Local evidence: full existing Flutter suite 231 passed, 16 skipped; analyzer clean;
focused API/onboarding and legacy-retirement tests passed; release APK builds.
Runtime/dependency searches find no provider integration in lib or pubspec files.
The legacy SQL directory remains historical reference material.

Outstanding release gates: real/older Android device upgrade with existing data,
airplane-mode setup/billing/restart, live API/emulator integration, user review,
and applicable release security/dependency scans. No Play Store upload performed.
