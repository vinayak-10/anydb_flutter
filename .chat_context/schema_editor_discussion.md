# Dynamic Schema Editor & Feature Expansion Discussion

This document records the conceptual discussion, feature proposals, and architectural outlines for introducing an **In-App Schema Customizer** and extending AnyDb's validation, cloud, and healing pipelines.

---

## 1. The In-App Schema Customizer (Conceptual Design)

### The Vision
Currently, AnyDb is 100% dynamic, but modifying the schema structure requires manual JSON file edits and transfer procedures (writing JSONs to `xyz.maya/anydb/schema/`). 
Introducing a schema customizer option inside the navigation drawer unlocks **instant on-the-fly tailoring** directly on the device.

### Why the Architecture Supports This Flawlessly
Because the SQLite storage layer (implemented in Phase 3) stores record values as schema-free dynamic JSON strings in a single `value` column rather than using rigid table columns, **users can add, rename, or delete schema fields instantly without requiring database migrations or DDL changes**. The database reads the updated schema and maps the existing record payloads dynamically.

### Proposed Implementation Flow
1. **Drawer Navigation Entry Point (`drawer_content.dart`):**
   Add an "Edit Schema Structure" button visible when a schema database is loaded, routing to a custom page.
2. **Two-Layer Editing Interface (`schema_editor_page.dart`):**
   * **Visual Component Builder (No-Code):** An interactive UI where users can tap to add standard fields (`text`, `number`, `phone`, `date`), customize multi-select options, and configure which field is designated as the active **Business Unique Key**.
   * **Raw JSON Text Editor (Power-User):** A full-screen dark-themed monospaced text editor (`TextField` with `maxLines: null`) where developers can modify advanced fields, report layouts, or Excel formula engines directly.
3. **Safety & Syntax Verification:**
   On tapping **Save**, the editor validates compile syntax:
   ```dart
   try {
     final decoded = jsonDecode(editorText);
     // 1. Write the updated JSON back to the schema file using FileService
     // 2. Re-initialize active database structures
     // 3. Invalidate providers and reload the UI instantly
   } catch (e) {
     // Throw a precise syntax SnackBar to prevent schema corruption
   }
   ```

---

## 2. Additional Future Feature Propositions

### A. Automated Background Cloud Sync & Indicators
* **Concept:** Transition from strictly manual backups to a debounced cloud sync orchestrator.
* **Mechanism:** Automatically queue and upload database backups to Google Drive in the background 5 seconds after any write operation (debounced to prevent cloud channel choking). Add a sleek sync status indicator in the app header (`Synced` check mark, `Syncing...` progress loop, or `Offline` cloud) for premium visual feedback.

### B. Database Startup Integrity Pipeline & Self-Healing
* **Concept:** Run automated local data protection scripts to protect SQLite databases from hardware or system-level crashes.
* **Mechanism:** Execute SQLite `PRAGMA integrity_check;` on startup. If corruption is found, automatically rename the damaged database (`*.db.corrupted`), fetch the latest verified backup from Google Drive, and restore local data transactionally with zero user friction.

### C. Regex Constraints & Conditional Logic
* **Concept:** Expand form capabilities to support advanced data formatting rules and dynamic form interactions.
* **Mechanism:** Add support for regex patterns in the JSON schema (e.g. Card format constraints `[A-Z]{3}-\d{4}`) and logical conditional visibility rules (e.g., hiding a field unless a specific dropdown value is selected).

### D. Dynamic Excel Report Styling
* **Concept:** Move Excel workbook styling variables (header colors, borders, font weights, alternating row shades) directly into `schema.json` rather than hardcoding them inside `workbook_service.dart`.
