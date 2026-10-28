# Storely setup

Start Fresh creates a local shop and works without an account or network.
Storely API is the only cloud backend. Open Store → Cloud Backup & Sync → Request Premium / View Request. Submit a contact
name, phone with country code and contact consent. Until approval/activation, business
data stays local. Create and verify an email account and tell the team which account
to approve. After approval, sign in with that account, agree to backup/upload, and
activate. A durable local backup is saved before uploading; retries preserve queued
records. Existing cloud registrations require reviewed recovery rather than an
automatic merge.

For developer API preview build flags, see [README.md](README.md).
For phased delivery and acceptance checks, see [plan.md](plan.md).
Legacy SQL files under `supabase/` are historical references. Do not run destructive
reset scripts against existing data as part of Android setup or upgrade.
