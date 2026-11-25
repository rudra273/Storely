# Storely refactor references

This is the entry point for the end-to-end refactor work agreed on 18 November 2026.

1. [Implementation plan](implementation-plan.md): execution phases, parallel agent ownership, Docker/localhost/emulator gates and final human flow/UX acceptance.
2. [Feature tracker](docs/refactor/feature-tracker.md): every feature from the comparison, its implementation phase and evidence status.
3. [Source comparison — refactor plan.md](<refactor plan.md>): the preserved 17 November audit, 145 feature comparisons, 15 source divergences and 273 declared reference surfaces.
4. [Vyapar reference index](../vyapar-rea/CLONE_SPEC.md): consult its business rules, flows, settings, storage, output and screen/control documents whenever a requirement is unclear. Preserve its UNKNOWN/static-evidence qualifications.
5. [Historical Storely server migration plan](plan.md) and [historical web/API refactor](../storelyweb/refractor.md): useful existing decisions and implementation history. The historical web plan excludes Android and includes visual work; those scope assumptions do not govern this new mobile/web parity effort.
6. [Continuation prompt](docs/refactor/handoff-prompt.md) gives the next implementation agent the verified checkpoint, remaining work and integration runbook.

Keep the source comparison and reference corpus as evidence. Record implementation progress in the new tracker and phase evidence, rather than rewriting the audit to make incomplete features appear finished. Current user requirements take precedence: retain theme/UI identity, align business flows across web/mobile, and reserve final acceptance for the user's flow and UX review.
