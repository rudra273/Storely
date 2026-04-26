# Storely Database Upgrade Plan

## Verdict

The senior review is correct. The current local schema works for a single-device app, but it should not be used as the server-sync schema without cleanup.

The biggest corrections are:

- Add stable UUIDs because local integer IDs cannot sync safely across devices.
- Keep a separate optional product code/barcode from the internal product UUID.
- Change stock quantities from `INTEGER` to `REAL`.
- Replace `product_purchase_entries` with a full `stock_movements` table.
- Stop using `products.mrp` and `bill_items.mrp` as selling price fields.
- Remove DB-level unique constraint on product name.
- Upgrade suppliers, categories, and units into proper synced tables.
- Use soft delete for synced records.

## Core Decisions

1. This upgrade assumes there is no production data to preserve.
2. Build a clean schema instead of carrying legacy table names forward.
3. Use client-generated UUID v4 for offline-first creation.
4. Do not add `sync_version` in V1. Use `updated_at` and `deleted_at` first. Add server-controlled versioning later when the sync protocol exists.
5. Every synced table must have `uuid`, `shop_id`, `created_at`, `updated_at`, `deleted_at`, and `device_id`.
6. Local SQLite `id` remains for joins and performance, but sync and APIs use `uuid`.
7. Product stock is event-based. `products.quantity_cache` is only a cached value.
8. Supplier GSTIN is optional.

## Identity Rules

### Product Identity

Products need two different concepts:

- `uuid`: internal globally unique product identity, required, hidden from user.
- `product_code`: optional user/company product code, visible/searchable.
- `barcode`: optional scan code, visible/searchable.

The app should never use product name as the source of truth identity. Name duplicate warnings can stay in UX, but not as a hard database identity.

### IDs

Use this pattern:

```sql
id INTEGER PRIMARY KEY AUTOINCREMENT,
uuid TEXT NOT NULL UNIQUE,
shop_id TEXT NOT NULL
```

For server sync, use `uuid`, not local `id`.

## Clean Schema

### shops

Add this when server sync starts. For local-only V1, `shop_id` can be generated and stored in settings.

```sql
CREATE TABLE shops(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  gstin TEXT,
  address TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

### products

```sql
CREATE TABLE products(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  product_code TEXT,
  barcode TEXT,
  name TEXT NOT NULL COLLATE NOCASE,
  category_id INTEGER,
  supplier_id INTEGER,
  selling_price REAL NOT NULL DEFAULT 0,
  purchase_price REAL NOT NULL DEFAULT 0,
  gst_percent REAL,
  overhead_cost REAL,
  profit_margin_percent REAL,
  direct_price_toggle INTEGER NOT NULL DEFAULT 0,
  manual_price REAL,
  quantity_cache REAL NOT NULL DEFAULT 0,
  unit_id INTEGER,
  source TEXT NOT NULL DEFAULT 'mobile',
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (category_id) REFERENCES categories(id),
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
  FOREIGN KEY (unit_id) REFERENCES units(id)
);
```

Important changes from current schema:

- `mrp` becomes `selling_price`.
- `item_code` becomes `product_code`.
- Add `barcode`.
- `quantity` becomes `quantity_cache REAL`.
- Remove `UNIQUE` from product name.
- Use `category_id`, `supplier_id`, and `unit_id` instead of text columns.

Recommended constraints and indexes:

```sql
CREATE UNIQUE INDEX idx_products_uuid ON products(uuid);
CREATE INDEX idx_products_shop_updated ON products(shop_id, updated_at);
CREATE INDEX idx_products_shop_product_code ON products(shop_id, product_code);
CREATE INDEX idx_products_shop_barcode ON products(shop_id, barcode);
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_supplier ON products(supplier_id);
```

Do not make `product_code` or `barcode` globally unique. If uniqueness is enforced, enforce it per shop and only for non-empty values.

### categories

Replaces `category_options`.

```sql
CREATE TABLE categories(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  name TEXT NOT NULL COLLATE NOCASE,
  gst_percent REAL,
  overhead_cost REAL,
  profit_margin_percent REAL,
  commission_percent REAL,
  direct_price_toggle INTEGER NOT NULL DEFAULT 0,
  manual_price REAL,
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

Indexes:

```sql
CREATE UNIQUE INDEX idx_categories_shop_name ON categories(shop_id, name);
CREATE UNIQUE INDEX idx_categories_uuid ON categories(uuid);
CREATE INDEX idx_categories_shop_updated ON categories(shop_id, updated_at);
```

### units

Replaces `unit_options`.

```sql
CREATE TABLE units(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  name TEXT NOT NULL COLLATE NOCASE,
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

Indexes:

```sql
CREATE UNIQUE INDEX idx_units_shop_name ON units(shop_id, name);
CREATE UNIQUE INDEX idx_units_uuid ON units(uuid);
CREATE INDEX idx_units_shop_updated ON units(shop_id, updated_at);
```

Preset units can still be seeded locally, but synced custom units should live here.

### suppliers

Replaces supplier text/options with a real table. GSTIN is optional.

```sql
CREATE TABLE suppliers(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  name TEXT NOT NULL COLLATE NOCASE,
  phone TEXT,
  email TEXT,
  gstin TEXT,
  address TEXT,
  notes TEXT,
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

Indexes:

```sql
CREATE UNIQUE INDEX idx_suppliers_uuid ON suppliers(uuid);
CREATE INDEX idx_suppliers_shop_name ON suppliers(shop_id, name);
CREATE INDEX idx_suppliers_shop_updated ON suppliers(shop_id, updated_at);
```

### customers

```sql
CREATE TABLE customers(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'Walk-in Customer',
  phone TEXT,
  email TEXT,
  address TEXT,
  notes TEXT,
  total_purchase_amount REAL NOT NULL DEFAULT 0,
  bill_count INTEGER NOT NULL DEFAULT 0,
  last_purchase_at TEXT,
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

Indexes:

```sql
CREATE UNIQUE INDEX idx_customers_uuid ON customers(uuid);
CREATE UNIQUE INDEX idx_customers_shop_phone
  ON customers(shop_id, phone)
  WHERE phone IS NOT NULL AND TRIM(phone) != '';
CREATE INDEX idx_customers_shop_updated ON customers(shop_id, updated_at);
```

Customer totals are cache fields. The source of truth is bills. Keep incremental updates for speed, and run a full customer ledger recalculation after sync as a safety net.

### bills

```sql
CREATE TABLE bills(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  bill_number TEXT NOT NULL,
  customer_id INTEGER,
  customer_uuid TEXT,
  customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer',
  customer_phone TEXT,
  subtotal_amount REAL NOT NULL DEFAULT 0,
  discount_percent REAL NOT NULL DEFAULT 0,
  discount_amount REAL NOT NULL DEFAULT 0,
  profit_commission_percent REAL NOT NULL DEFAULT 0,
  total_amount REAL NOT NULL,
  item_count INTEGER NOT NULL,
  is_paid INTEGER NOT NULL DEFAULT 1,
  payment_method TEXT NOT NULL DEFAULT 'cash',
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (customer_id) REFERENCES customers(id)
);
```

Indexes:

```sql
CREATE UNIQUE INDEX idx_bills_uuid ON bills(uuid);
CREATE UNIQUE INDEX idx_bills_shop_bill_number ON bills(shop_id, bill_number);
CREATE INDEX idx_bills_shop_created ON bills(shop_id, created_at);
CREATE INDEX idx_bills_shop_updated ON bills(shop_id, updated_at);
CREATE INDEX idx_bills_customer_id ON bills(customer_id);
```

Bill number format:

```text
SHOP-DEVICE-YYYYMMDD-SEQUENCE
```

Example:

```text
SHOP001-DEV01-20260426-0001
```

Generate the sequence per device per day:

```sql
SELECT COUNT(*) + 1 AS next_seq
FROM bills
WHERE device_id = ?
  AND bill_number LIKE ?
```

### bill_items

Drop the current redundant `mrp` field. Keep snapshots.

```sql
CREATE TABLE bill_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  bill_id INTEGER NOT NULL,
  bill_uuid TEXT NOT NULL,
  product_id INTEGER,
  product_uuid TEXT,
  product_name TEXT NOT NULL,
  unit_name TEXT,
  purchase_price_snapshot REAL NOT NULL DEFAULT 0,
  selling_price_snapshot REAL NOT NULL DEFAULT 0,
  cost_snapshot REAL NOT NULL DEFAULT 0,
  profit_snapshot REAL NOT NULL DEFAULT 0,
  commission_snapshot REAL NOT NULL DEFAULT 0,
  gst_snapshot REAL NOT NULL DEFAULT 0,
  was_direct_price INTEGER NOT NULL DEFAULT 1,
  quantity REAL NOT NULL DEFAULT 0,
  subtotal REAL NOT NULL,
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id)
);
```

Indexes:

```sql
CREATE UNIQUE INDEX idx_bill_items_uuid ON bill_items(uuid);
CREATE INDEX idx_bill_items_bill_id ON bill_items(bill_id);
CREATE INDEX idx_bill_items_product_uuid ON bill_items(product_uuid);
CREATE INDEX idx_bill_items_shop_updated ON bill_items(shop_id, updated_at);
```

### stock_movements

Replaces `product_purchase_entries`.

This becomes the source of truth for stock.

```sql
CREATE TABLE stock_movements(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  shop_id TEXT NOT NULL,
  product_id INTEGER NOT NULL,
  product_uuid TEXT NOT NULL,
  movement_type TEXT NOT NULL,
  quantity_delta REAL NOT NULL,
  unit_cost REAL,
  source_type TEXT,
  source_id INTEGER,
  source_uuid TEXT,
  import_batch_key TEXT,
  notes TEXT,
  device_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  FOREIGN KEY (product_id) REFERENCES products(id)
);
```

Allowed `movement_type` values:

```text
purchase
sale
adjustment
return
void
```

Quantity convention:

- Purchase/restock: positive quantity.
- Sale: negative quantity.
- Return from customer: positive quantity.
- Manual correction: positive or negative adjustment.

Indexes:

```sql
CREATE UNIQUE INDEX idx_stock_movements_uuid ON stock_movements(uuid);
CREATE INDEX idx_stock_movements_product_created
  ON stock_movements(product_id, created_at);
CREATE INDEX idx_stock_movements_source
  ON stock_movements(source_type, source_id);
CREATE INDEX idx_stock_movements_shop_updated
  ON stock_movements(shop_id, updated_at);
CREATE INDEX idx_stock_movements_import_batch
  ON stock_movements(import_batch_key);
```

### app_settings

For local-only settings, current key/value is acceptable. For synced settings, add shop/device metadata.

```sql
CREATE TABLE app_settings(
  key TEXT NOT NULL,
  shop_id TEXT NOT NULL,
  value TEXT,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  PRIMARY KEY (shop_id, key)
);
```

Keep device-local settings out of server sync unless they truly belong to the shop.

## Dart Model Changes

Add or update these models:

- `Product`
- `Category`
- `Unit`
- `Supplier`
- `Customer`
- `Bill`
- `BillItem`
- `StockMovement`
- `ShopProfile` later when server sync starts

Shared model fields:

```dart
String uuid;
String shopId;
String? deviceId;
DateTime createdAt;
DateTime updatedAt;
DateTime? deletedAt;
```

Use the `uuid` package for client-generated UUID v4.

## Database Operation Changes

### Product Create/Edit

- Generate `uuid` on create.
- Generate `product_code` only if user enters one or the app needs internal code display.
- Do not require product code.
- Do not enforce unique product name in DB.
- Update `updated_at` on every edit.
- Use soft delete by setting `deleted_at`.

### Restock / Purchase

Replace `product_purchase_entries` insert with:

```text
stock_movements.movement_type = purchase
quantity_delta = positive quantity
unit_cost = purchase price
source_type = manual/import
import_batch_key = import batch key if imported
```

Then update `products.quantity_cache`.

### Billing

On bill creation:

1. Insert bill.
2. Insert bill items with `product_uuid`.
3. Insert stock movement for each product item:

```text
movement_type = sale
quantity_delta = -sold_quantity
source_type = bill
source_id = bill.id
source_uuid = bill.uuid
```

4. Update `products.quantity_cache`.
5. Update customer ledger cache.

### Bill Delete / Void

Do not hard delete synced bills.

Set `bills.deleted_at`, then create reversing stock movements or mark original sale movements deleted based on final business choice.

Recommended for audit trail:

- Keep original sale movement.
- Add reverse movement:

```text
movement_type = void
quantity_delta = +sold_quantity
source_type = bill_void
source_uuid = bill.uuid
```

### Customer Ledger

Keep incremental updates for UX speed.

After sync or app startup, support a full repair function:

```text
recalculateCustomerLedger(shopId)
```

It should rebuild totals from non-deleted bills.

## Import Changes

Import should map columns like this:

| Import Column | DB Field |
| --- | --- |
| Product Code / SKU / Item Code | `products.product_code` |
| Barcode | `products.barcode` |
| Name | `products.name` |
| Category | create/find `categories`, set `category_id` |
| Supplier | create/find `suppliers`, set `supplier_id` |
| Unit | create/find `units`, set `unit_id` |
| Purchase Price | `products.purchase_price`, `stock_movements.unit_cost` |
| Selling Price / Price / Rate | `products.selling_price` or direct price |
| Quantity | purchase stock movement quantity |

Import duplicate detection should move from `product_purchase_entries.import_batch_key` to `stock_movements.import_batch_key`.

## UI Changes

### Product Editor

Required fields:

- Product name
- Purchase price
- Quantity or stock value
- Selling price mode: Formula / Direct

Optional fields:

- Product code
- Barcode
- Category
- Supplier
- Unit

### Supplier Management

Create a real supplier page/table:

- Name required
- Phone optional
- Email optional
- GSTIN optional
- Address optional
- Notes optional

### Product List

Use:

- Product name
- Selling price
- Quantity cache
- Product code/barcode if present
- Category/supplier names via joins

### Billing

When selecting product, resolve by:

1. Barcode
2. Product code
3. Product UUID
4. Name search

Bill item must store snapshots so old bills are stable even after product edits.

## Implementation Order

### Phase 1: Schema Foundation

1. Add `uuid` package.
2. Add local helpers for UUID, shop ID, device ID, and timestamps.
3. Replace schema definitions with clean tables:
   - products
   - categories
   - units
   - suppliers
   - customers
   - bills
   - bill_items
   - stock_movements
   - app_settings
4. Bump DB version.
5. Since there is no production data, prefer dropping/recreating local dev DB during implementation.

### Phase 2: Models

1. Update `Product` with:
   - uuid
   - shopId
   - productCode
   - barcode
   - categoryId
   - supplierId
   - unitId
   - sellingPrice
   - quantityCache as double
   - sync timestamps
2. Add `Supplier`, `Category`, `Unit`, `StockMovement`.
3. Update `Bill`, `BillItem`, `Customer`.
4. Remove `bill_items.mrp` from model.

### Phase 3: Product DB APIs

1. Update product CRUD.
2. Replace name-unique DB assumption with UX warning only.
3. Add product lookup by barcode/product code.
4. Update category/supplier/unit option APIs to use real tables.
5. Update purchase summary queries to read from `stock_movements`.

### Phase 4: Stock Movement APIs

1. Create stock movement insert helper.
2. Create quantity cache recalculation helper.
3. Update restock/import to write purchase movement.
4. Update billing to write sale movement.
5. Update bill void/delete behavior.

### Phase 5: UI Updates

1. Product editor:
   - product code
   - barcode
   - real supplier/category/unit references
   - quantity supports decimal
2. Product list:
   - show code/barcode when present
   - read quantity as decimal
3. Import:
   - map product code/barcode/category/supplier/unit
   - duplicate detection via stock movements
4. Store/settings:
   - supplier table management
   - category/unit management from real tables
5. Billing:
   - search by product code and barcode
   - preserve snapshots

### Phase 6: Tests

Add tests for:

- UUID is generated for every created record.
- Product code is optional.
- Product code/barcode lookup works.
- Duplicate product names are allowed in DB but warned in UX logic.
- Quantity supports decimal values.
- Import creates purchase stock movements.
- Billing creates sale stock movements.
- Product quantity cache updates after purchase/sale.
- Bill void reverses stock.
- Soft delete hides records but keeps them syncable.
- Customer ledger recalculates from bills.
- Supplier GSTIN is optional.
- Bill item stores product UUID and snapshots.

## Sync V1 Protocol Shape

This is not implemented in the DB cleanup phase, but the schema should support it.

Client pushes rows changed since last sync:

```text
WHERE updated_at > last_sync_at OR deleted_at > last_sync_at
```

Server stores rows by `uuid`.

Conflict strategy for V1:

- Last-write-wins using `updated_at`.
- Deleted rows win if `deleted_at` is newer.
- Server returns changed rows since last sync.

Later V2 can add:

- server-assigned `sync_version`
- conflict logs
- per-row merge strategies

## Final Recommendation

Implement this cleanup before server sync. The current schema is acceptable for local-only use, but server sync needs stable identity, soft deletes, and stock movements first.

The first implementation should focus on correctness, not migration compatibility, because there is no production data yet.
