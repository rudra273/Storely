# Storely UI Refactor — Plan & Status

A staged plan to make the UI feel professional, compact, and consistent **without
changing flows, navigation, or behavior**. Read `CLAUDE.md` for the design system
(tokens, palette, shared widgets) and the hard constraints before implementing.

**Status legend:** ⬜ not started · 🟡 in progress · ✅ done · ⛔ out of scope

---

## Guiding constraints (recap from CLAUDE.md)

- Light/white theme only — never dark.
- Keep amber/navy palette; amber becomes an accent, not a fill. Lean on neutrals.
- Do NOT touch the bottom navigation.
- Analytics + KPI screens are out of scope (later redesign).
- Presentation only — no flow/logic/DB changes, same content in same order.

---

## Stage 0 — Foundation: design tokens & shared widgets  ✅

- [x] `lib/theme/app_colors.dart` — cooler neutral bg, border tokens, ink aliases.
- [x] `lib/theme/app_spacing.dart` (4-pt scale xs/sm/md/lg/xl/xxl/xxxl).
- [x] `lib/theme/app_radius.dart` (sm=8 / md=12 / lg=16 / pill=999).
- [x] `lib/theme/app_text.dart` — display/title/subtitle/body/label/caption wired into textTheme.
- [x] `lib/theme/app_shadows.dart` — `soft` + `navBar` tokens.
- [x] `lib/theme/widgets/` — `AppCard`, `CompactListRow`, `CompactListCard`,
      `LeadingIconChip`, `StatusDot`, `StatusPill`, `SectionHeader`, `AppScreenHeaderDelegate`.
- [x] `main.dart` — full ThemeData update: bg=#F7F8FA, card 1px border, inputs,
      FilledButton/OutlinedButton/TextButton/FAB/dialog/snackbar/chip themes.
- [x] Old inline `AppColors` removed from main.dart; re-exported from theme barrel.
- [x] `flutter analyze` — no issues.

---

## Stage 1 — Home screen  ✅  (`lib/screens/home_screen.dart`)

- [x] Unified navy sliver header via `AppScreenHeaderDelegate` with shop name subtitle.
- [x] Sales hero: navy card, amber trending icon (not full amber fill).
- [x] Stat tiles use `AppCard` with icon chip — compact 2-column layout.
- [x] Quick actions: full-width row of 4 equal tiles with consistent style.
- [x] Low-stock + unpaid bills use `CompactListCard` with hairline rows + `StatusPill`.
- [x] Section headers via `SectionHeader`. Empty states compact inline.
- [x] `flutter analyze` clean.

---

## Stage 2 — Bills screen  ✅  (`lib/screens/bills_screen.dart`)

- [x] Unified navy sliver header via `AppScreenHeaderDelegate`.
- [x] Search bar inherits global input theme.
- [x] Unpaid summary wrapped in `AppCard` with `ExpansionTile`.
- [x] Bill cards use `AppCard` with compact padding + `StatusPill` chips.
- [x] Date group labels → uppercase `AppText.label`.
- [x] Profit sheet bottom sheet updated to `AppCard`/`AppRadius`.
- [x] FAB kept. `flutter analyze` clean.

---

## Stage 3 — Products screen  ✅  (`lib/screens/products_screen.dart`)

- [x] Import switched to `app_theme.dart`; AppBar inherits global navy theme.
- [x] Product card → `AppCard` with `StatusPill` (Out/Low), `_SourceBadge`, `_InfoChip`.
- [x] Empty state, filter/sort bar, prices-updating banner → theme tokens.
- [x] Product count badge in AppBar → `StatusPill`.
- [x] `flutter analyze` clean.

---

## Stage 4 — Store screen  ✅  (`lib/screens/store_screen.dart`)

- [x] Import switched to `app_theme.dart`; AppBar inherits global navy theme.
- [x] `_StorePanel` → `AppCard`; `_PanelIcon` → `LeadingIconChip`.
- [x] `_StoreActionRow` → `AppCard` with `AppText` styles, compact chevron.
- [x] `_OptionRow` → `AppCard` with compact icon buttons.
- [x] `_SectionLabel` → `AppText.label` uppercase.
- [x] Role badge → `StatusPill`. Shop name/details → AppText scale.
- [x] `flutter analyze` clean.

---

## Stage 5 — Scan & billing flow  ✅  (`lib/screens/scan_screen.dart`)

Lighter pass — camera/flow screen, keep functional.

- [x] Import switched to `app_theme.dart`.
- [x] Cart panel, item cards, qty controls, summary box, customer suggestions,
      manual product tiles → `bg`/`surface`/`border` tokens + `AppRadius`/`AppSpacing`.
- [x] AppBar title style removed (theme handles weight); navy scanner backdrop kept.
- [x] Scanner/camera logic untouched (camera-frame overlay radii intentionally left).
- [x] `flutter analyze` clean.

---

## Stage 6 — Secondary screens  ✅

- [x] `notifications_screen.dart` — AppCard + LeadingIconChip + AppText.
- [x] `about_app_screen.dart` — AppCard sections + AppText scale.
- [x] `privacy_policy_screen.dart` — AppCard + AppText body.
- [x] `welcome_screen.dart` — bg token + AppText + theme button (no hardcoded styles).
- [x] `qr_sheet_screen.dart` — AppBar title cleaned (theme handles weight).
- [x] `flutter analyze` — full project, **no issues**.

---

## Stage 7 — Polish & QA  ⬜

- [ ] Stage 5 (scan screen) complete.
- [ ] Sweep for any remaining magic radii/paddings/inline cards (`grep`).
- [ ] Verify every screen on a real device: content & actions unchanged.
- [ ] Confirm amber-as-accent reads premium; nothing dark-themed slipped in.
- [ ] Bump version, update changelog, build release APK.

---

## Out of scope (do not touch now)  ⛔

- `lib/screens/analytics_screen.dart` — later redesign with only key KPIs.
- `lib/screens/kpi_widgets.dart` — same.
- Bottom navigation in `lib/main.dart` (`AppShell`, `_BottomNavBar`, `_NavItem`).
- App flows, navigation order, DB/sync logic.

---

## Resolved decisions (locked)

1. **Unified header style → Compact navy bar.** Navy header, white text, amber
   accent — applied uniformly. Bills/Products/Store adopt global AppBar theme
   (navy bg set in ThemeData); Home keeps its custom sliver delegate.
2. **Background tone → Cooler neutral grey `#F7F8FA`.** Replaced warm cream.
   White cards with 1px `AppColors.border` borders pop against it.
3. **List density → Compact hairline rows.** Lists use `CompactListCard`/`CompactListRow`
   separated by 1px hairlines. Feature/summary blocks remain `AppCard`s.
