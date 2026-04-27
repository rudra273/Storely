# Storely — Supabase Cloud Sync Setup Guide

Storely works 100% offline by default. Cloud sync is **optional** — enable it to share data across devices or with your team.

---

## Table of Contents

1. [Create a Supabase Project](#1-create-a-supabase-project)
2. [Create the Database Schema](#2-create-the-database-schema)
3. [Get Your Project Credentials](#3-get-your-project-credentials)
4. [Create a User Account](#4-create-a-user-account)
5. [Connect the App](#5-connect-the-app)
6. [First Sync (Auto Owner)](#6-first-sync-auto-owner)
7. [Adding Team Members](#7-adding-team-members)
8. [Managing Roles](#8-managing-roles)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) and sign up / sign in
2. Click **New Project**
3. Fill in:
   - **Name**: `storely` (or anything you like)
   - **Database Password**: save this somewhere safe
   - **Region**: choose the closest to you
4. Click **Create new project** and wait for it to finish (~2 minutes)

---

## 2. Create the Database Schema

1. In your Supabase dashboard, go to **SQL Editor** (left sidebar)
2. Click **New query**
3. Open the file `supabase/storely_cloud_schema.sql` from this project
4. Copy the **entire contents** and paste into the SQL Editor
5. Click **Run** (or press Ctrl+Enter)
6. You should see: `Success. No rows returned` — that means it worked

This creates all the tables (shops, products, bills, etc.), Row Level Security policies, and helper functions.

---

## 3. Get Your Project Credentials

1. Go to **Project Settings** → **API** (left sidebar → gear icon)
2. You need two values:
   - **Project URL** — looks like `https://abcdefgh.supabase.co`
   - **anon public key** — a long `eyJ...` string under "Project API keys"

> ⚠️ **Never use the `service_role` key in the app.** Only use the `anon` key.

---

## 4. Create a User Account

1. Go to **Authentication** → **Users** (left sidebar)
2. Click **Add user** → **Create new user**
3. Enter:
   - **Email**: your email (e.g. `you@gmail.com`)
   - **Password**: a strong password
   - **Auto Confirm User**: ✅ toggle ON
4. Click **Create user**

Repeat this for each team member who needs access.

---

## 5. Connect the App

1. Open Storely on your device
2. Go to **Store** tab (bottom nav)
3. Tap **Cloud Sync** → gear icon (⚙️)
4. Enter:
   - **Supabase URL**: paste the Project URL from Step 3
   - **Anon Key**: paste the anon public key from Step 3
5. Save, then tap **Sign In**
6. Enter the email and password from Step 4

---

## 6. First Sync (Auto Owner)

After signing in, tap the **sync button** (🔄). The app will:

1. Create the shop in the cloud (using your local shop data)
2. Automatically register you as the **owner**
3. Push all your local data (products, bills, etc.) to the cloud

You'll see your role as **OWNER** on the Shop panel.

> 💡 The first user to sync always becomes the owner. No SQL needed.

---

## 7. Adding Team Members

### For staff members:

1. Create their account in Supabase (**Authentication** → **Add user**)
2. Give them the Supabase URL and anon key
3. They open the app → Store → Cloud Sync → enter credentials → sign in
4. On first sync, they automatically join as **staff**

Staff members can:
- ✅ View all shop data (products, bills, customers)
- ✅ Create bills and add products
- ✅ Sync data to/from cloud
- ❌ Cannot edit the shop profile (name, phone, GSTIN, etc.)

### Role hierarchy:

| Role | Edit Shop | Sync Data | Create Bills | Manage Members |
|------|-----------|-----------|--------------|----------------|
| **Owner** | ✅ | ✅ | ✅ | ✅ (via SQL) |
| **Admin** | ✅ | ✅ | ✅ | ✅ (via SQL) |
| **Staff** | ❌ | ✅ | ✅ | ❌ |

---

## 8. Managing Roles

All role management is done via the **Supabase SQL Editor**.

### Check current members:

```sql
SELECT
  sm.user_id,
  u.email,
  sm.role,
  sm.created_at
FROM public.shop_members sm
JOIN auth.users u ON u.id = sm.user_id
WHERE sm.shop_id = 'local-shop';
```

### Promote a staff member to admin:

```sql
UPDATE public.shop_members
SET role = 'admin'
WHERE shop_id = 'local-shop'
  AND user_id = (SELECT id FROM auth.users WHERE email = 'staff@example.com');
```

### Demote an admin back to staff:

```sql
UPDATE public.shop_members
SET role = 'staff'
WHERE shop_id = 'local-shop'
  AND user_id = (SELECT id FROM auth.users WHERE email = 'admin@example.com');
```

### Remove a member:

```sql
DELETE FROM public.shop_members
WHERE shop_id = 'local-shop'
  AND user_id = (SELECT id FROM auth.users WHERE email = 'remove-me@example.com');
```

### Transfer ownership:

```sql
-- Demote current owner to admin:
UPDATE public.shop_members
SET role = 'admin'
WHERE shop_id = 'local-shop'
  AND user_id = (SELECT id FROM auth.users WHERE email = 'old-owner@example.com');

-- Promote new owner:
UPDATE public.shop_members
SET role = 'owner'
WHERE shop_id = 'local-shop'
  AND user_id = (SELECT id FROM auth.users WHERE email = 'new-owner@example.com');
```

---

## 9. Troubleshooting

### Error: `42501 — new row violates row level security policy`

**Cause**: The user doesn't have the right permissions for the operation.

**Fix**:
1. Check if the user is a member: run the "Check current members" query above
2. If they're not a member, they need to sign in from the app and sync — auto-join will add them as staff
3. If auto-join fails, manually add them:

```sql
-- Create the shop if it doesn't exist:
INSERT INTO public.shops (uuid, name, created_at, updated_at)
VALUES ('local-shop', 'My Shop', now()::text, now()::text)
ON CONFLICT (uuid) DO NOTHING;

-- Add the user as staff (or 'owner'/'admin'):
INSERT INTO public.shop_members (shop_id, user_id, role)
SELECT 'local-shop', id, 'staff'
FROM auth.users WHERE email = 'user@example.com'
ON CONFLICT (shop_id, user_id) DO NOTHING;
```

---

### Error: `23503 — violates foreign key constraint "shop_members_shop_id_fkey"`

**Cause**: Trying to add a member before the shop row exists.

**Fix**: Create the shop first:

```sql
INSERT INTO public.shops (uuid, name, created_at, updated_at)
VALUES ('local-shop', 'My Shop', now()::text, now()::text)
ON CONFLICT (uuid) DO NOTHING;
```

Then retry adding the member.

---

### Member INSERT returns "Success" but no row appears

**Cause**: The email in the WHERE clause doesn't match any user exactly.

**Fix**: Check what emails actually exist:

```sql
SELECT id, email FROM auth.users;
```

Copy the exact email from the result and use it in your INSERT.

---

### Want to start completely fresh (nuclear option)

If something is broken and you want to wipe everything and start over:

**Step 1 — Drop everything:**

```sql
-- Drop all policies
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Authenticated users can create shop" ON public.shops;
DROP POLICY IF EXISTS "Members can sync shops" ON public.shops;
DROP POLICY IF EXISTS "Members can view shops" ON public.shops;
DROP POLICY IF EXISTS "Admins can update shops" ON public.shops;
DROP POLICY IF EXISTS "Admins can delete shops" ON public.shops;
DROP POLICY IF EXISTS "Members can view shop members" ON public.shop_members;
DROP POLICY IF EXISTS "First owner can join empty shop" ON public.shop_members;
DROP POLICY IF EXISTS "Authenticated users can join as staff" ON public.shop_members;
DROP POLICY IF EXISTS "Owners and admins can manage shop members" ON public.shop_members;
DROP POLICY IF EXISTS "Members can sync app_settings" ON public.app_settings;
DROP POLICY IF EXISTS "Members can sync categories" ON public.categories;
DROP POLICY IF EXISTS "Members can sync units" ON public.units;
DROP POLICY IF EXISTS "Members can sync suppliers" ON public.suppliers;
DROP POLICY IF EXISTS "Members can sync customers" ON public.customers;
DROP POLICY IF EXISTS "Members can sync products" ON public.products;
DROP POLICY IF EXISTS "Members can sync bills" ON public.bills;
DROP POLICY IF EXISTS "Members can sync bill_items" ON public.bill_items;
DROP POLICY IF EXISTS "Members can sync stock_movements" ON public.stock_movements;

-- Drop trigger and functions
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.is_shop_member(text);
DROP FUNCTION IF EXISTS public.is_shop_admin(text);
DROP FUNCTION IF EXISTS public.get_shop_role(text);
DROP FUNCTION IF EXISTS public.can_manage_shop_members(text);
DROP FUNCTION IF EXISTS public.shop_has_no_members(text);

-- Drop all tables (order matters — children first)
DROP TABLE IF EXISTS public.stock_movements CASCADE;
DROP TABLE IF EXISTS public.bill_items CASCADE;
DROP TABLE IF EXISTS public.bills CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.suppliers CASCADE;
DROP TABLE IF EXISTS public.units CASCADE;
DROP TABLE IF EXISTS public.categories CASCADE;
DROP TABLE IF EXISTS public.app_settings CASCADE;
DROP TABLE IF EXISTS public.shop_members CASCADE;
DROP TABLE IF EXISTS public.shops CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
```

**Step 2 — Recreate**: Paste and run `supabase/storely_cloud_schema.sql` again.

**Step 3 — Sign in from the app** and sync. First user becomes owner automatically.

> ⚠️ This deletes ALL cloud data (products, bills, etc.). Your local app data is safe — it stays on the device.

---

### Quick reference: manually set up owner by email

If the auto-join didn't work for the first user:

```sql
-- 1. Create shop:
INSERT INTO public.shops (uuid, name, created_at, updated_at)
VALUES ('local-shop', 'My Shop', now()::text, now()::text)
ON CONFLICT (uuid) DO NOTHING;

-- 2. Find your user ID:
SELECT id, email FROM auth.users;

-- 3. Add as owner (use the exact email from step 2):
INSERT INTO public.shop_members (shop_id, user_id, role)
SELECT 'local-shop', id, 'owner'
FROM auth.users WHERE email = 'your-exact-email@example.com'
ON CONFLICT (shop_id, user_id) DO UPDATE SET role = 'owner';

-- 4. Verify:
SELECT * FROM public.shop_members;
```
