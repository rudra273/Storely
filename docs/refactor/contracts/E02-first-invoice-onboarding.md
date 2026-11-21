# First-invoice onboarding

After shop setup, Home should surface the next action for an owner who has yet to save a sales invoice. Use the existing catalog editor and checkout routes. On web, the existing premium activation and invitations still determine when a shop is available. Android also supports a local shop without an account or connection.

| Shop state | Home guidance |
|---|---|
| No catalog products and no saved sales invoice | Add your first product |
| At least one catalog product and no saved sales invoice | Create your first invoice |
| At least one saved sales invoice | Regular Home actions |

Determine progress from saved shop data. A held or recovered draft, review preview, rejected save, purchase, or credit note does not complete the milestone. A cancelled original invoice still records that the owner reached it. Sample products can satisfy the catalog step. Existing role and entitlement checks apply to each action. Keep setup options available through their existing entry points.

Verify with fresh shops and the normal UI. Create one product and start checkout from Home, leave and recover the draft, make an explicit settlement choice, save, and confirm the guidance is gone. Use the same price, quantity and paid amount on both clients and check the saved amounts and stock movement. Exercise retry and the cancelled-invoice case against the real API with isolated test data.
