# Codebase Index & Architectural Reference

This artifact serves as a complete, high-density index of the `anydb_flutter` codebase. Refer to this index to identify file responsibilities, paths, classes, and method signatures without performing expensive, token-heavy raw code lookups.

---

## 1. System Architecture Map

The application is structured into four distinct architectural layers:

```
+--------------------------------------------------------------+
|                         UI SCREENS                           |
|  (collection_view.dart, element_editor.dart, logs_page.dart)  |
+------------------------------+-------------------------------+
                               | Hydrates & Displays
                               v
+--------------------------------------------------------------+
|                     DATA & BUSINESS MODELS                   |
|       (ElementModel, GenInterface/Widget Components)        |
+------------------------------+-------------------------------+
                               | Interacts with
                               v
+--------------------------------------------------------------+
|                      DATABASE SERVICES                       |
|           (ElementDb, AggregatorService, Meta)               |
+------------------------------+-------------------------------+
                               | Persists to
                               v
+--------------------------------------------------------------+
|                        STORAGE DRIVERS                       |
|     (StorageService -> AsyncStore/SqliteHelper/FileStore)    |
+--------------------------------------------------------------+
```

---

## 2. Directory & File Index

### 📂 `lib/models/` — Data Models
* **[element_model.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/models/element_model.dart)**
  * **Role:** Manages the life of a single schema-dynamic record.
  * **Core Class:** `ElementModel`
  * **Key Methods:**
    * `init(List schema, dynamic repoIntf)`: Instantiates nested `GenInterface` components based on schema.
    * `populate(Map<String, dynamic> dbJson)`: Hydrates components with raw database JSON.
    * `fetch()`: Serializes all active components back into a dynamic Map.
    * `validate()`: Validates constraints across all components.

---

### 📂 `lib/core/` — System Core
* **[gen_interface.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/core/gen_interface.dart)**
  * **Role:** Abstract base class defining interface capabilities for all dynamic component types.
  * **Core Class:** `GenInterface`
* **[widget_factory.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/core/widget_factory.dart)**
  * **Role:** Factory registry that dynamically resolves component strings to active class instances.
  * **Core Class:** `WidgetFactory` (maps `text`, `number`, `phone`, `date`, `dropdown`, `composite`, `multi_select`, `reminder`, etc.)
* **[formula_engine.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/core/formula_engine.dart)**
  * **Role:** Mathematical spreadsheet-style formula evaluation parser.
  * **Core Class:** `FormulaEngine`
* **[settings_provider.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/core/settings_provider.dart)**
  * **Role:** Manage developer preference parameters, theme configs, and font scales.
* **[cell_helper.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/core/cell_helper.dart)**
  * **Role:** Safe cell value extraction from Excel sheets, preventing crash-level decode errors.

---

### 📂 `lib/services/` — Database & Storage Layer
* **[element_db.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/element_db.dart)**
  * **Role:** Aggregates element records, manages schema metadata, and governs record lifecycle transitions.
  * **Core Class:** `ElementDb`
  * **Key Methods:**
    * `init(schemaJson, interface)`: Initializes db schema, headers, and starts local storage.
    * `initDb({forced, filter})`: Main reader that fetches all records, triggers auto-purge, and instantiates `ElementModel` list.
    * `segregate(records, {types})`: Filters in-memory records based on soft-states (`Active`, `Archived`, `Deleted`).
    * `markArchive()`, `markDelete()`, `restore()`: Soft-lifecycle modifiers using `__meta__` maps.
    * `importDb(data, {wipeFirst})`, `exportDb()`: Bulk database sync controllers.
* **[storage_service.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/storage_service.dart)**
  * **Role:** Storage layer abstraction dispatching reads/writes to configured local or file targets.
  * **Core Classes:** `StorageInterface`, `StorageService`, `LocalStore`, `FileStore`
* **[async_store.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/async_store.dart)**
  * **Role:** Main mobile storage driver utilizing persistent `SharedPreferences` keys.
  * **Core Class:** `AsyncStore`
  * **Key Methods:** `getAll(dbName)`, `get(key)`, `update(key, val)`, `updateAll(dbName, items)`, `clear(dbName)`
* **[sqlite_helper.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/sqlite_helper.dart)**
  * **Role:** High-performance local SQL database helper currently limited to Linux platforms.
  * **Core Class:** `SqliteHelper`
  * **Key Methods:**
    * `updateAll(dbName, items)`: High-performance transactional batch writes (`BEGIN TRANSACTION ... COMMIT`).
* **[extractor_service.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/extractor_service.dart)**
  * **Role:** Governs extraction logic, record alignments, and workbook evaluations.
* **[workbook_service.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/workbook_service.dart)**
  * **Role:** Handles excel sheet compilations, daily/monthly templates, and directories.
* **[google_drive_service.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/google_drive_service.dart)**
  * **Role:** Connects and uploads backups/exports dynamically to Google Drive directories.

---

### 📂 `lib/components/` — Dynamic UI Elements
* **[simple_account.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/simple_account.dart)**
  * **Role:** Handles bookkeeping details, stats calculations, and custom transaction ledger lists.
* **[drawer_content.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/drawer_content.dart)**
  * **Role:** Left navigation panel. Handles theme options, Google login, and manual backup triggers.
* **[text_ascii.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/text_ascii.dart)** & **[text_number.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/text_number.dart)** & **[phone_number.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/phone_number.dart)** & **[drop_down.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/drop_down.dart)**
  * **Role:** Specialized dynamic form fields utilizing text size 16 scales.
* **[multi_value.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/multi_value.dart)** & **[composite.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/composite.dart)**
  * **Role:** Advanced dynamic collection arrays and nested form builders.
* **[reminder.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/reminder.dart)**
  * **Role:** Soft alert parameters and dynamic visual reminders.

---

### 📂 `lib/screens/` — Primary Layout Screens
* **[collection_view.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/screens/collection_view.dart)**
  * **Role:** Main home schema layout (Patients, Financials, Reports tabs).
  * **Key Classes:** `CollectionView`, `_AggregatorView`, `AggregatorReportView`
* **[element_editor.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/screens/element_editor.dart)**
  * **Role:** Generates interactive editors for new or selected dynamic records.
* **[logs_page.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/screens/logs_page.dart)**
  * **Role:** Displays system audit logs, actions, and sheet exports.

---

## 3. Important Metadata Structures

### Soft-Lifecycle Archiving Map
Each record contains a `__meta__` JSON block tracking lifecycle flags:
```json
{
  "__meta__": {
    "time": {
      "c": 1716382000000, // Created timestamp
      "u": 1716383000000, // Last updated timestamp
      "a": 1716384000000, // Archived timestamp (Optional: If present, record is archived)
      "d": 1716385000000  // Deleted timestamp (Optional: If present, record is soft-deleted)
    }
  }
}
```
