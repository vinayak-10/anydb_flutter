# Enterprise Unique Key & Auto-Archiving Logic Design

This document details the refined, enterprise-grade architecture for **Duplicate Prevention and Auto-Archiving** in AnyDb. It implements a user-selected **Business Unique Key** separated completely from the **Database Primary Key**, enabling active validation of records while keeping archived records off-memory in the database.

---

## 1. The Core Architectural Philosophy

We divide record identification into two distinct layers:

1. **Database Primary Key (SQLite Level):**
   - A unique physical identifier (e.g., an autoincremented integer, a generated UUID, or a composite key: `SchemaName:BusinessKey:Timestamp`).
   - Ensures that multiple records with the same business key (e.g., one active and multiple archived historical records) can coexist side-by-side in the physical database on disk without primary key collisions.
2. **Business Unique Key (User-Selected Level):**
   - A dynamic, user-selected schema field (e.g., `Card Number`, `Patient ID`, `Phone`, or `SKU`) chosen dynamically.
   - Used exclusively for business rule validation: searching, duplicate prevention, and auto-archiving.

---

## 2. Architectural Flow

When a user submits a new entry:

```
                          [ User Submits New Entry ]
                                     │
                                     v
                       [ Get Business Unique Key value ]
                    (e.g. Phone = "555-0199" or Card = "101")
                                     │
                                     v
                 [ Query SQLite database for ACTIVE records ]
               WHERE business_key = "101" AND is_active = 1
              (Instant sub-millisecond query; archived stays off-memory)
                                     │
                    ┌────────────────┴────────────────┐
                    ▼ (Exists)                        ▼ (Does Not Exist)
        [ Fetch Expiring Date ]               [ Save as New SQLite Row ]
                    │                           PK: UUID / AutoIncrement
                    v                           Status: Active
            Is Expiring Date                     (Success)
           nearing < 1 month?
            ┌───────┴─────────┐
            ▼ (Yes)           ▼ (No)
     [ Auto-Archive Old: ]   [ Block & Throw Error: ]
     Set is_active = 0        "Card is active & valid"
     [ Save New SQLite Row ]
        Status: Active
        (Success)
```

---

## 3. Key Design Components

### Component A: Dynamic Selection UI (Interactive Dropdown in Drawer)
- **Role:** Allows the user to select, inspect, or change the Business Unique Key at any time.
- **UI Location:** A dedicated dropdown field inside the **Preferences / Schema Configurations** section of the navigation drawer (`DrawerContent` in `drawer_content.dart`).
- **Dynamic Field Prioritization (Heuristics):**
  To make selection effortless, the dropdown dynamically sorts and prioritizes the list of fields from the active database schema:
  - **Primary Candidates (Pushed to the top):** Fields containing highly likely unique identifier keywords in their names, such as:
    `id`, `number`, `code`, `key`, `phone`, `card`, `sku`, `serial`, `barcode`.
  - **Secondary Candidates (Appended below):** Standard fields (e.g., `Name`, `Age`, `Address`, `Sex`).
- **Storage:** Changing this dropdown selection instantly updates the `schema_configurations` or element database metadata table.

### Component B: SQLite Table Design (Active-Only Partitioning)
To support this separation of keys while keeping archived records off-memory:
```sql
CREATE TABLE IF NOT EXISTS "records" (
  id TEXT PRIMARY KEY,          -- Database Primary Key (e.g., UUID or Auto-Generated)
  schema_name TEXT,             -- Dynamic Schema reference
  business_key_value TEXT,      -- The actual value of the user-selected unique field
  is_active INTEGER DEFAULT 1,  -- Lifecycle state flag (1 = Active, 0 = Archived/Deleted)
  value TEXT                    -- The entire dynamic JSON payload
);

-- Index for instant unique-active validation
CREATE INDEX IF NOT EXISTS idx_active_business_key 
ON "records" (schema_name, business_key_value) 
WHERE is_active = 1;
```

---

## 4. The Runtime Validation Logic

When a new record is saved, the validation operates directly on the SQLite database:

1. **Get Unique Key Value:** Retrieve the value of the user-selected key from the incoming form payload (e.g., `newEntry.getFieldValue(config.businessUniqueKey)`).
2. **Execute Active-Only Validation Query:**
   ```dart
   final activeRecord = await SqliteHelper.query(
     'SELECT * FROM "$tableName" WHERE business_key_value = ? AND is_active = 1 LIMIT 1',
     [incomingUniqueValue]
   );
   ```
3. **Resolution Logic:**
   - **If `activeRecord == null`:** The business key is completely free. Save the new entry as `is_active = 1`.
   - **If `activeRecord != null`:**
     - Read the dynamic `Expiry Date` field from the active record's JSON value.
     - **Expiring soon (<= 30 days remaining):**
       - Update the old record's state to archived: `UPDATE "records" SET is_active = 0 WHERE id = ?`.
       - Insert the new record as the new active row: `INSERT INTO "records" ... is_active = 1`.
       - *Benefit:* Done inside a single SQLite transaction block (guarantees atomic data safety).
     - **Not expiring (> 30 days remaining):**
       - Block the save action and display the validation warning to the user.
