# Storely Supabase Cloud Sync Setup Guide

Storely is offline-first. Cloud sync is optional, and it is used when one shop needs multiple devices or staff members.

The current onboarding has two paths:

- **Start Fresh**: create a new local shop. Supabase login is not required.
- **Join Existing Shop**: sign in to Supabase and join a shop where the owner/admin already added your account.

Staff members do **not** self-join a shop automatically.

---

## 1. Create Supabase Project

1. Go to [supabase.com](https://supabase.com).
2. Create a new project.
3. Save the database password somewhere safe.
4. Wait for the project to finish provisioning.

---

## 2. Create Fresh Cloud Schema

For a clean setup:

1. Open **Supabase Dashboard** -> **SQL Editor**.
2. Run `supabase/drop_storely_cloud_schema.sql` if you want to wipe old Storely cloud tables.
3. Run `supabase/storely_cloud_schema.sql`.

The drop script removes Storely tables, policies, functions, and triggers. It does **not** delete Supabase Auth users.

The schema creates:

- `shops`
- `shop_members`
- catalog tables
- billing/payment/stock tables
- RLS policies
- helper functions for role checks
- auth trigger for `profiles`

---

## 3. Get App Credentials

In Supabase:

1. Go to **Project Settings** -> **API**.
2. Copy:
   - **Project URL**
   - **anon public key**

Only use the anon public key in Storely. Never put the `service_role` key in the app.

---

## 4. Owner Onboarding

Use this flow for the first shop owner.

1. Open Storely.
2. On the welcome screen, choose **Start Fresh**.
3. Enter the shop name.
4. Go to **Store** -> **Cloud Sync**.
5. Enter Supabase URL and anon key.
6. Sign up or sign in with the owner email.
7. Let sync run.

On first successful sync, Storely will:

- create the cloud `shops` row
- add the signed-in user to `shop_members`
- set role to `owner`
- upload local shop/catalog/billing data

The first synced user for a fresh shop becomes the owner.

---

## 5. Staff Member Onboarding

Staff must be added to the shop before their first successful sync.

### Step A: Create Or Invite Staff Auth User

In Supabase:

1. Go to **Authentication** -> **Users**.
2. Add the staff user, or let the staff create an account from the Storely welcome screen.
3. If you create the user manually, turn on **Auto Confirm User**.

### Step B: Find Shop UUID

Run:

```sql
select uuid, name
from public.shops
order by created_at desc;
```

Copy the owner shop UUID.

### Step C: Add Staff Member

Run:

```sql
insert into public.shop_members (shop_id, user_id, role)
select
  '<shop_uuid>',
  id,
  'staff'
from auth.users
where email = 'staff@example.com'
on conflict (shop_id, user_id)
do update set role = excluded.role;
```

### Step D: Staff Joins From App

On the staff device:

1. Open Storely.
2. Choose **Join Existing Shop**.
3. Enter Supabase URL and anon key.
4. Enter staff email and password.
5. Tap **Sign In and Join**.

Storely checks `shop_members`. If the account is not added yet, it stops and shows an error instead of creating a separate shop.

---

## 6. Staff Account Creation From Welcome Screen

If the staff user does not exist yet:

1. Staff opens Storely.
2. Chooses **Join Existing Shop**.
3. Enters Supabase URL, anon key, email, and password.
4. Taps **Create Account**.
5. Owner/admin adds that email to `shop_members`.
6. Staff returns to **Join Existing Shop** and taps **Sign In and Join**.

Creating an account is not the same as joining a shop. The membership row is still required.

---

## 7. Add Admin Instead Of Staff

Use `admin` when a team member should manage catalog/settings.

```sql
insert into public.shop_members (shop_id, user_id, role)
select
  '<shop_uuid>',
  id,
  'admin'
from auth.users
where email = 'admin@example.com'
on conflict (shop_id, user_id)
do update set role = excluded.role;
```

---

## 8. Role Permissions

| Role | Catalog/settings | Bills/payments | Customers | Manage members |
| --- | --- | --- | --- | --- |
| Owner | Yes | Yes | Yes | Yes, via SQL |
| Admin | Yes | Yes | Yes | Yes, via SQL |
| Staff | Read only | Yes | Yes | No |

Admin-managed data:

- shop profile/settings
- categories
- units
- suppliers
- products
- invoice series

Staff can still create operational data:

- bills
- bill items
- bill payments
- customer updates from billing
- stock movements from bills

---

## 9. Manage Existing Members

### List Members

```sql
select
  sm.shop_id,
  s.name as shop_name,
  u.email,
  sm.role,
  sm.created_at
from public.shop_members sm
join public.shops s on s.uuid = sm.shop_id
join auth.users u on u.id = sm.user_id
order by s.name, sm.created_at;
```

### Promote Staff To Admin

```sql
update public.shop_members
set role = 'admin'
where shop_id = '<shop_uuid>'
  and user_id = (
    select id from auth.users where email = 'staff@example.com'
  );
```

### Demote Admin To Staff

```sql
update public.shop_members
set role = 'staff'
where shop_id = '<shop_uuid>'
  and user_id = (
    select id from auth.users where email = 'admin@example.com'
  );
```

### Remove Member

```sql
delete from public.shop_members
where shop_id = '<shop_uuid>'
  and user_id = (
    select id from auth.users where email = 'remove@example.com'
  );
```

### Transfer Ownership

```sql
update public.shop_members
set role = 'admin'
where shop_id = '<shop_uuid>'
  and user_id = (
    select id from auth.users where email = 'old-owner@example.com'
  );

update public.shop_members
set role = 'owner'
where shop_id = '<shop_uuid>'
  and user_id = (
    select id from auth.users where email = 'new-owner@example.com'
  );
```

---

## 10. Troubleshooting

### Staff Sees: Account Is Not Added To A Shop Yet

Cause: the Supabase Auth user exists, but there is no `shop_members` row.

Fix:

```sql
insert into public.shop_members (shop_id, user_id, role)
select '<shop_uuid>', id, 'staff'
from auth.users
where email = 'staff@example.com'
on conflict (shop_id, user_id)
do update set role = excluded.role;
```

### Staff Accidentally Chose Start Fresh

If they did not create any business data, they can clear app data/reinstall and choose **Join Existing Shop**.

If they already created products/bills locally, the app will block joining another cloud shop. Clear local app data before joining.

### `42501` Row Level Security Error

Cause: the signed-in user is not allowed to write that table.

Fix:

1. Confirm membership:

```sql
select sm.shop_id, u.email, sm.role
from public.shop_members sm
join auth.users u on u.id = sm.user_id
where u.email = 'user@example.com';
```

2. If they need catalog/settings access, promote them to `admin`.
3. If they only need billing access, keep them as `staff`.

### `23503` Foreign Key Error When Adding Member

Cause: the `shops` row does not exist yet.

Fix: complete owner first sync, then add staff.

### Email Query Inserts Zero Rows

Cause: the email does not match any Supabase Auth user.

Check exact email:

```sql
select id, email
from auth.users
order by created_at desc;
```

### Start Cloud From Scratch

Run:

1. `supabase/drop_storely_cloud_schema.sql`
2. `supabase/storely_cloud_schema.sql`

Then onboard the owner again from Storely using **Start Fresh**.

---

## 11. Important Rules

- Do not use the `service_role` key in the app.
- Staff cannot self-join an existing shop.
- First owner is created by first successful sync from a completed local shop.
- Join Existing Shop requires Supabase login.
- Start Fresh does not require Supabase login.
- If a device has local business data, Storely will not silently merge it into another cloud shop.
