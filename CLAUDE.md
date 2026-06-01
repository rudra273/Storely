# Storely — Project & UI Refactor Reference

Storely is a Flutter app (Android, live on Play Store) for shop owners to manage
products and create bills. Local SQLite (`lib/db`) + optional cloud sync
(`lib/services/cloud_service.dart`).

This file is the **design-system reference** for the ongoing UI refactor. Read it
before touching any screen UI. The staged plan and its status live in `plan.md`.

---

## Goal of the refactor

Make the UI feel **professional, compact, and consistent** without changing what
the app does or how users navigate it. Feedback from real users:

- UX is good and easy to understand — **do not change flows or navigation.**
- UI does not feel professional — cards look generic, spacing is loose.
- Make things **more compact**.

### Hard constraints (do NOT violate)

1. **Keep it a light/white theme. Never dark-themed.** White surfaces always.
2. **Keep the existing accent** — the gold/amber (`#F5A623`) + navy palette. Do
   not introduce a new brand hue. We *may* lean more heavily on neutrals
   (navy/charcoal text, true whites, soft grey backgrounds) so amber becomes an
   accent rather than a fill everywhere.
3. **Do not change the bottom navigation** (`AppShell` / `_BottomNavBar` in
   `lib/main.dart`). Tabs, center scan button, order — all stay.
4. **Analytics is out of scope.** `lib/screens/analytics_screen.dart` and
   `lib/screens/kpi_widgets.dart` will be redesigned later from scratch with only
   the KPIs that matter. Leave them alone for now.
5. **No behavior/flow changes.** Pure presentation refactor. Same screens, same
   data, same actions, same order of things.

---

## Current state (why it looks unprofessional)

- **No shared design layer.** `AppColors` is defined inline in `lib/main.dart`.
  There is no spacing scale, no radius scale, no typography scale, no shared card
  / button / header widgets. Every screen hand-rolls its own `Container`
  decorations.
- **Inconsistent styling.** Audit of `lib/screens`:
  - Corner radii in use: 2, 6, 7, 8, 9, 10, 12, 14, 16, 20, 24, 28, 99, 999.
  - Paddings: 6, 8, 10, 12, 14, 16, 20, 24, 28.
  - Shadows hand-rolled per card; some cards have shadows, some don't.
- **Inconsistent headers.** `HomeScreen` uses a custom navy `SliverPersistentHeader`;
  `Bills`, `Products`, `Store` use a plain Material `AppBar`. They don't feel like
  one app.
- **Amber overused as a fill** (big sales card, quick-action tiles, badges) which
  reads as loud rather than premium.

### File map (screens)

| File | Lines | Header style | In scope |
|------|-------|--------------|----------|
| `main.dart` | 338 | theme + bottom nav | theme yes / nav NO |
| `home_screen.dart` | 769 | custom navy sliver | yes |
| `products_screen.dart` | 4558 | Material AppBar | yes |
| `bills_screen.dart` | 1271 | Material AppBar | yes |
| `store_screen.dart` | 2627 | Material AppBar | yes |
| `scan_screen.dart` | 1514 | — | yes (lighter pass) |
| `qr_sheet_screen.dart` | 291 | AppBar | yes (lighter) |
| `notifications_screen.dart` | 129 | AppBar | yes (lighter) |
| `about_app_screen.dart` | 157 | AppBar | yes (lighter) |
| `privacy_policy_screen.dart` | 106 | AppBar | yes (lighter) |
| `welcome_screen.dart` | 131 | — | yes (lighter) |
| `analytics_screen.dart` | 620 | AppBar | **NO — later redesign** |
| `kpi_widgets.dart` | 867 | — | **NO — later redesign** |

---

## Target design system

Create `lib/theme/` as the single source of truth. Screens consume these tokens
and shared widgets instead of hand-rolling decorations.

### Palette (`lib/theme/app_colors.dart`)

Move `AppColors` out of `main.dart` into here (keep the class name `AppColors`
and the same constant names so existing references keep compiling; re-export or
update imports). Lean on neutrals; amber becomes an accent.

```
navy        #1B2838   primary text / headers / primary buttons
navyLight   #243447   secondary dark surface (use sparingly)
amber       #F5A623   ACCENT only — small highlights, active states, key CTAs
ink         #1B2838   default text (alias of navy)
inkMuted    #6B7280   secondary text (slightly cooler than current #7A8599)
inkFaint    #9CA3AF   tertiary text / placeholders
bg          #F7F8FA   app background — LOCKED: cooler neutral grey (replaces cream)
surface     #FFFFFF   cards / sheets
border      #ECEEF2   hairline borders (1px) — replaces most shadows
borderStrong#E2E5EA   stronger dividers
success     #16A34A
error       #EF4444
warning     #F5A623   (reuse amber)
```

Note: current theme uses warm cream (`#F8F4ED`). Moving to a cooler neutral grey
background (`#F7F8FA`) instantly reads more "app-like / professional" while
staying firmly light/white. Amber stops being a background fill.

### Spacing scale (`lib/theme/app_spacing.dart`)

4-pt grid. **Use these everywhere; no magic numbers.**

```
xs = 4    sm = 8    md = 12    lg = 16    xl = 20    xxl = 24    xxxl = 32
```

Default screen horizontal padding: `lg` (16). Compact rows: vertical `md` (12).

### Radius scale (`lib/theme/app_radius.dart`)

Collapse the 14 different radii into:

```
sm  = 8     chips, badges, small controls
md  = 12    DEFAULT for cards, inputs, tiles
lg  = 16    large feature cards / bottom sheets
pill = 999  fully-rounded pills/avatars
```

Pick **md (12)** as the single default card radius. Compact + modern.

### Elevation / borders

**Prefer 1px hairline borders over shadows.** Professional dashboards use crisp
borders, not drop shadows. Default card = white fill + `border` 1px + radius md,
**no shadow**. Reserve a single soft shadow token for genuinely floating things
(bottom nav, FAB, active bottom sheet) — define it once as `AppShadows.soft`.

### Typography (`lib/theme/app_text.dart`)

Define a small named scale and wire it into `ThemeData.textTheme`. Keep system
font (no new font dependency unless we later choose one — out of scope now).
Tighter, more deliberate sizes for a compact look:

```
display  28 / w800   screen hero numbers (e.g. today's sales)
title    18 / w700   section headers
subtitle 15 / w600   card titles / list item titles
body     14 / w500   body text
label    12 / w600   overline labels (UPPERCASE, letterSpacing 0.8)
caption  12 / w500   muted secondary text
```

### Shared widgets (`lib/theme/widgets/`)

Build these once, replace inline copies across screens:

- `AppCard` — white, radius md, 1px border, configurable padding (default `lg`).
  Optional `onTap` (wraps Material+InkWell). Replaces the dozens of inline
  `Container(decoration: BoxDecoration(...))` cards.
- `AppListTile` / `CompactListRow` — the standard product/bill/low-stock row:
  leading icon-chip, title + subtitle, trailing value/badge. Compact vertical
  padding. This is the workhorse — most lists become this.
- `AppBadge` / `StatusPill` — the Low/Out/Paid/Unpaid pills (radius sm).
- `SectionHeader` — title + optional "View All →" trailing action.
- `AppScreenHeader` (or a shared `SliverAppBar` config) — **one** header style so
  Home / Products / Bills / Store all match. **LOCKED: compact navy header**
  (navy bg, white title, amber accent), matching the existing Home sliver.
  Bills/Products/Store must drop their plain Material `AppBar` and adopt this.
- `PrimaryButton` / `SecondaryButton` wrappers if needed for consistency (or just
  configure `FilledButton`/`OutlinedButton` themes globally).

### Compactness principles

- Replace big feature cards (e.g. 20px-padded amber sales hero) with tighter
  16px-padded cards; amber as a thin accent strip/number color, not full fill.
- Reduce vertical gaps: section spacing `xxl` (24) max, intra-card `md` (12).
- Lists: **LOCKED — hairline-separated compact rows**, not per-row floating cards
  with margins. Repeating lists (products, bills, low-stock) use `CompactListRow`
  divided by 1px `border` hairlines for a dense ledger/dashboard feel. Feature /
  summary blocks may still be `AppCard`s.
- Quick actions: smaller tiles, consistent icon-chip treatment.

---

## Working rules for the refactor

- **One screen per PR-sized change**, following `plan.md` stages in order.
- Never edit Analytics / KPI files.
- Never edit the bottom nav.
- After each screen: run `flutter analyze` (must stay clean) and visually verify
  the screen still has the same content/actions in the same order.
- Don't refactor logic, DB calls, or state management — only the widget tree /
  styling. If a build method mixes logic and UI heavily, extract UI only.
- Match surrounding code style (this codebase uses private `_Widget` classes,
  `const` constructors, `withValues(alpha:)` not `withOpacity`).
- Keep `AppColors` constant names stable to avoid a giant find-replace churn;
  add new tokens alongside, deprecate old ones gradually.

## Useful commands

```
flutter analyze
flutter run                 # debug on device/emulator
flutter build apk --release
```
