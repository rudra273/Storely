# E02.3 Portable preference verification

21 November 2026

Android now separates its guest settings from the active account and shop. Missing, deleted and malformed values fall back to the normal defaults. The preference pull cursor follows the account and shop so a previous user's newer cursor cannot hide the next user's older rows. Web Appearance uses the same private theme row as Android. [Preference contract](../../contracts/E02-slice-3-portable-preferences.md)

| Check | Result |
| --- | --- |
| API and PostgreSQL | 390 unit tests, 408 integration tests and lint passed. Tests include member-only access, account and shop isolation, native push/pull, concurrent creation, legacy row identity, skewed mobile clocks and theme tombstones. Migration `0025` applies only the theme timing change to private sync. |
| Web | Typecheck, lint, 624 tests and production build passed. After the binding filename change, 41 affected tests and another build passed. |
| Localhost browser | Two paid shops and two account scopes passed. The guest choice stayed separate, staff saved only their own setting, System followed OS appearance, and a failed save kept the current choice and offered retry. Changing appearance preserved unfinished checkout input. |
| Flutter | 498 tests passed and 17 opt-in live tests skipped. Analyzer found no issues. The focused scope tests covered initial local adoption, malformed values, account and shop transitions, legacy cursors, queued writes, stale auth fallback and an account switch during a preference pull. |
| Android emulator and live Docker API | The dedicated test authenticated an owner and then a staff member in the same paid shop. A REST change appeared on Android, Android's System choice reached the API, sign-out restored the guest choice, and staff received its own choice. The visible demo used a separate emulator. |
| Production Docker | Fresh and repeat migrations, verified database TLS, frontend proxying, deep links and security headers passed. |

The broader Premium activation harness stopped before the preference assertions during this run. The dedicated Android test uses a pre-activated synthetic shop and exercises real authentication and sync. Web English/Hindi and final human UX verification remain separate work.

Both runtime fixtures were removed. The visible demo emulator stayed open. API `4fd2b36`, generated web types `27acf4a`, web implementation `71e1eaa`, and Android live acceptance `7df8c6f`.
