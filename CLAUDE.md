# Storely — Project

Storely is a Flutter app (Android, live on Play Store) for shop owners to manage
products and create bills. Local SQLite (`lib/db`) + optional cloud sync
(`lib/services/cloud_service.dart`).

The UI design system lives in `lib/theme/` (colors, spacing, radius, typography,
shared widgets). Consume those tokens and shared widgets — do not hand-roll
`Container` decorations, magic spacing/radius numbers, or one-off card styles.
The app is light/white themed with a gold/amber (`#F5A623`) + navy accent
palette. Do not change the bottom navigation (`AppShell` / `_BottomNavBar` in
`lib/main.dart`) or app flows/navigation without being asked.

---

## Working rule — verify before you build (REQUIRED)

When I report a defect or request a feature, do **not** start coding immediately.
First investigate the codebase and confirm with me:

1. **Is it a real defect?** Reproduce the logic in the actual code. Read the
   relevant file(s) and trace the behavior before agreeing something is broken.
   If the code already behaves correctly, say so and show me where.
2. **Is it already implemented?** Search for existing handling (the feature,
   a similar helper, a flag, a screen) before adding anything new. We must not
   duplicate what already exists.
3. **Report findings, then wait.** Tell me what you found — "real defect, here's
   the cause", "already implemented at `file:line`", or "not a defect because
   …". Only after I confirm should you begin the actual change.

Do not skip this step because a task "looks like a one-liner." A wrong or
duplicate change is more expensive than a five-minute check.

---

## Android / Flutter engineering guide (medium-level)

This codebase uses plain `StatefulWidget` + `setState` and a `DatabaseHelper`
singleton for SQLite — **not** Riverpod/Bloc/GetX. Match the existing pattern;
do not introduce a state-management package or rearchitect unless I ask.

### Correctness & async safety
- **Never use a `BuildContext` across an async gap without re-checking
  `mounted`.** After every `await`, guard with `if (!mounted) return;` (for
  `State.context`) or `if (!context.mounted) return;` (for a captured context)
  before navigating, showing a snackbar/sheet, or calling `setState`. This is
  the single most common source of crashes here.
- Keep `flutter analyze` **clean** after every change — treat lints
  (`use_build_context_synchronously`, unused imports, etc.) as errors, not noise.
- Wrap DB writes that can fail (constraints, sync) and surface failures to the
  user; don't swallow exceptions silently.

### State & rebuilds
- Prefer `const` constructors everywhere they apply — they let Flutter skip
  rebuilds and are cheap correctness wins.
- Keep `setState` calls scoped to the smallest widget that owns the state; don't
  call it on a large ancestor when a small leaf changed.
- Don't recreate `Future`s inside `build` for `FutureBuilder` — cache them in
  `initState`/state, and handle waiting / error / empty / data states explicitly.

### Lists & performance
- Use `ListView.builder` / `.separated` (lazy) for any list that can grow —
  never a `Column`/`ListView(children: [...])` over a full dataset.
- Dispose every `TextEditingController`, `ScrollController`, `AnimationController`,
  and `StreamSubscription` in `dispose()`.
- Do heavy work (parsing, large queries, PDF/report generation) off the build
  thread; keep `build` methods pure and fast. Use `compute`/isolates for genuinely
  expensive CPU work.
- Avoid unbounded `Opacity`, `ClipRRect`, and large `BackdropFilter` layers in
  hot paths; they're expensive on lower-end Android devices (our user base).

### UI & widget hygiene
- Extract UI into private `_Widget` classes (the existing style) rather than long
  build methods; refactor UI only — don't entangle DB/state changes into a
  "styling" change.
- Use `withValues(alpha:)` (not the deprecated `withOpacity`).
- Respect safe areas / keyboard insets (`SafeArea`, `MediaQuery.viewInsetsOf`)
  for bottom sheets and forms.

### Data, money & release
- This is a billing app: never let `double` money arithmetic drift — round at
  display and compare with a small epsilon (the bill model already does this in
  `_balanceDue` / `_paymentStatus`); follow that pattern.
- Treat the SQLite schema as migration-sensitive — schema changes need a proper
  migration path; don't break existing users' local data.
- Before release work, verify on a real/older Android device, bump the version
  appropriately, and keep the build reproducible (`flutter build apk --release`).

### Useful commands
```
flutter analyze
flutter run                 # debug on device/emulator
flutter build apk --release
```
