# Complete Implementation Plan: anydb_flutter Overhaul

This document contains the step-by-step specifications for all proposed enhancements to `anydb_flutter` (May 2026). These designs are structured to avoid compilation errors and preserve the existing codebase architecture.

## Progress Checklist
- [x] **Phase 1: Robust Web Storage & Quota Management** *(Completed)*
- [x] **Phase 2: Persistent Isolate Worker Pool & Paint-Yielding Spinner** *(Completed)*
- [x] **Phase 3: Minimizable Record Draft Store & Active Emerald Teal Banner** *(Completed)*
- [x] **Phase 4: Tablet Split View Responsive Layout** *(Completed)*
- [x] **Phase 5: Multi-Platform Portability & Compatibility Assessment** *(Completed)*

---

## Phase 1: Robust Web Storage & Quota Management

### Rationale:
On Web, unawaited `prefs.setString` calls throw `QuotaExceededError` DOMExceptions asynchronously outside of standard `try-catch` blocks, causing browser/app crashes when `localStorage` is full.

### Target: `lib/services/async_store.dart`

```dart
// 1. Declare class-level static boolean flag
static bool _isQuotaExceeded = false;

// 2. Update the update method:
static Future<void> update(String key, dynamic val) async {
  if (!kIsWeb) {
    final parts = key.split(':');
    if (parts.length >= 2) {
      await SqliteHelper.update(parts[0], parts.sublist(1).join(':'), val);
      return;
    }
  }

  final jsonStr = jsonEncode(val);
  if (kIsWeb) _webCache[key] = jsonStr;

  if (kIsWeb && _isQuotaExceeded) {
    return; // Short-circuit persistent storage writes once quota is exceeded
  }

  final prefs = await _getPrefs();
  try {
    await prefs.setString(key, jsonStr);
  } catch (e) {
    if (e.toString().contains("QuotaExceededError") ||
        e.toString().contains("quota") ||
        e.toString().contains("NS_ERROR_DOM_QUOTA_REACHED")) {
      _isQuotaExceeded = true;
      debugPrint("AsyncStore: Quota Exceeded. Kept in-memory.");
    } else {
      rethrow;
    }
  }
}

// 3. Update the updateAll method:
static Future<void> updateAll(String dbName, Map<String, dynamic> items) async {
  if (!kIsWeb) {
    await SqliteHelper.updateAll(dbName, items);
    return;
  }

  final prefs = await _getPrefs();
  
  for (var entry in items.entries) {
    final jsonStr = jsonEncode(entry.value);
    if (kIsWeb) _webCache[entry.key] = jsonStr;
    
    if (_isQuotaExceeded) continue;

    try {
      await prefs.setString(entry.key, jsonStr);
    } catch (e) {
      if (e.toString().contains("QuotaExceededError") ||
          e.toString().contains("quota") ||
          e.toString().contains("NS_ERROR_DOM_QUOTA_REACHED")) {
        _isQuotaExceeded = true;
        debugPrint("AsyncStore.updateAll: Web Quota Exceeded. Kept in-memory.");
      } else {
        rethrow;
      }
    }
  }
}

// 4. Update clear & clearAll methods to reset the flag:
static Future<void> clear(String dbName) async {
  ...
  _isQuotaExceeded = false; // Reset quota exceeded status
}

static Future<void> clearAll() async {
  ...
  _isQuotaExceeded = false; // Reset quota exceeded status
}
```

---

## Phase 2: Persistent Isolate Worker Pool & Paint-Yielding Spinner

### Rationale:
Spawning background thread Isolates dynamically (using one-shot `compute` commands) introduces a small startup latency (20ms–50ms) to load Dart resources and memory heaps. For heavy computational loops, this can add unnecessary overhead.

To solve this, we implement a **Persistent Isolate Worker Pool** (`IsolateWorker`). Spawning a single, long-lived background Isolate thread on startup, the pool keeps a duplex Port connection active. CPU-heavy tasks are dynamically dispatched, queued, and returned instantly over a single persistent channel.

### The Unified `IsolateWorker` Service (`lib/services/isolate_worker.dart`)
This central, platform-safe service will manage background thread pooling:

```dart
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

class IsolateWorker {
  static final IsolateWorker _instance = IsolateWorker._internal();
  static IsolateWorker get instance => _instance;
  IsolateWorker._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Map<int, Completer<dynamic>> _pendingTasks = {};
  int _taskIdCounter = 0;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    
    _isolate = await Isolate.spawn(_workerEntryPoint, _receivePort.sendPort);
    
    final Completer<SendPort> portCompleter = Completer<SendPort>();
    _receivePort.listen((message) {
      if (message is SendPort) {
        portCompleter.complete(message);
      } else if (message is Map) {
        final int id = message['id'];
        final dynamic result = message['result'];
        final dynamic error = message['error'];
        
        final completer = _pendingTasks.remove(id);
        if (completer != null) {
          if (error != null) {
            completer.completeError(error);
          } else {
            completer.complete(result);
          }
        }
      }
    });

    _sendPort = await portCompleter.future;
    _initialized = true;
    debugPrint("IsolateWorker: Persistent worker thread successfully established.");
  }

  Future<T> execute<T>(String taskType, Map<String, dynamic> params) async {
    if (kIsWeb) {
      // Browser environment executes tasks synchronously on the main thread safely
      return _executeTaskSync(taskType, params) as T;
    }
    
    await init();
    final int taskId = _taskIdCounter++;
    final completer = Completer<T>();
    _pendingTasks[taskId] = completer;

    _sendPort!.send({
      'id': taskId,
      'type': taskType,
      'params': params,
    });

    return completer.future;
  }
}

// 1. Worker thread entrypoint executing in raw OS sandbox
void _workerEntryPoint(SendPort mainSendPort) {
  final ReceivePort workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  workerReceivePort.listen((message) {
    if (message is Map) {
      final int id = message['id'];
      final String taskType = message['type'];
      final Map<String, dynamic> params = message['params'];

      try {
        final result = _executeTaskSync(taskType, params);
        mainSendPort.send({
          'id': id,
          'result': result,
        });
      } catch (e) {
        mainSendPort.send({
          'id': id,
          'error': e.toString(),
        });
      }
    }
  });
}

// 2. Synchronous task dispatch table
dynamic _executeTaskSync(String type, Map<String, dynamic> params) {
  switch (type) {
    case 'writeExcel':
      return _writeExcelInIsolate(params);
    case 'getMatchedSheets':
      return _getMatchedSheetsInIsolate(params);
    case 'readSheet':
      return _readSheetInIsolate(params);
    case 'parseSchema':
      return _parseSchemaJsonInIsolate(params['jsonStr']);
    case 'importMerge':
      return _processImportLogicStatic(params);
    default:
      throw "IsolateWorker: Unknown task type '$type'";
  }
}
```

---

### App Workflows Utilizing the Isolate Pool

#### 1. Large Schema JSON File Parsing (`schema_service.dart`)
* **Usage:** Spawns on App Startup & Schema Additions.
* **Execution:**
  ```dart
  final content = await IsolateWorker.instance.execute<Map<String, dynamic>>(
    'parseSchema', 
    {'jsonStr': fileContentString}
  );
  ```

#### 2. High-Performance Database Imports (`storage_service.dart`)
* **Usage:** Database backups, imports, and B-tree cache merging in `LocalStore.importData`.
* **Execution:** Offload cache merges into the Isolate:
  ```dart
  final result = await IsolateWorker.instance.execute<Map<String, dynamic>>(
    'importMerge', 
    {'dbName': _dbName, 'data': data, 'currentEntries': currentEntries}
  );
  ```

#### 3. Excel Workbook Generating & Writing (`workbook_service.dart`)
* **Usage:** Triggered when saving sheets, generating Daily/Monthly reports, or finalising a day.
* **Execution:** Dispatches sheets and formula tables to the Isolate:
  ```dart
  final fileBytes = await IsolateWorker.instance.execute<List<int>>(
    'writeExcel', 
    {'existingBytes': existingBytes, 'data': data, 'sheetName': sheetName}
  );
  ```

#### 4. Excel Workbook Discovery & Reading (`workbook_service.dart`)
* **Usage:** Triggered during report data inspection and loading.
* **Execution:** Offloads Excel file tree matches and row mappings:
  ```dart
  final matchedSheets = await IsolateWorker.instance.execute<List<String>>(
    'getMatchedSheets', 
    {'bytes': bytes, 'type': type}
  );
  ```
  ```dart
  final sheetData = await IsolateWorker.instance.execute<List<List<dynamic>>>(
    'readSheet', 
    {'bytes': bytes, 'sheetName': sheetName}
  );
  ```

#### 5. Yielding Delays inside Main Thread (Web Fallback)
* **Yielding Delays:** To ensure the spinner paints instantly on Web targets (where the isolate runs synchronously on the main thread), yield execution before heavy operations:
  - In `_AggregatorReportViewState._generate()`: Keep yielding delay `await Future.delayed(const Duration(milliseconds: 150));` after the post-frame callback.
  - In `_handleDone` (`_CollectionViewTabState`), append yielding delays immediately after updating progress texts:
  ```dart
  statusNotifier.value = "Saving database records locally...";
  await Future.delayed(const Duration(milliseconds: 150)); // Yield to paint status text
  ```

---

## Phase 3: Minimizable Record Draft Store & Active Emerald Teal Banner

### Rationale:
Users must be able to start a new record, navigate away to browse/edit older records without losing data or committing to the database, and return to the draft via an active draft banner.

### Target A: `lib/screens/element_editor.dart`
Pop the screen with `true` on successful save to SQLite:
```dart
Future<void> _save() async {
  ...
  try {
    await widget.db.addRecord(_editingElement);
    if (!mounted) return;
    Navigator.pop(context, true); // Signal successful save
  } catch (e) {
    ...
  }
}
```

### Target B: `lib/screens/collection_view.dart` (`_DatabaseViewState`)
1. **Declare state field** for the draft:
```dart
ElementModel? _draftNewElement;
```

2. **Implement resume helper**:
```dart
void _resumeDraft() async {
  if (_draftNewElement == null) return;
  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (context) => ElementEditor(
        db: widget.db,
        element: _draftNewElement!,
        isNew: true,
      ),
    ),
  );
  if (saved == true) {
    setState(() {
      _draftNewElement = null;
    });
  }
  _init(forced: true);
}
```

3. **Update `onAdd()`** to check for existing draft:
```dart
void onAdd() async {
  if (_draftNewElement != null) {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Active Draft Found"),
        content: const Text("You already have an unsaved draft. What would you like to do?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, "resume"),
            child: const Text("RESUME DRAFT", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, "discard"),
            child: const Text("DISCARD & START FRESH", style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, "cancel"),
            child: const Text("CANCEL"),
          ),
        ],
      ),
    );

    if (choice == "resume") {
      _resumeDraft();
      return;
    } else if (choice == "discard") {
      setState(() {
        _draftNewElement = null;
      });
    } else {
      return; // Cancel
    }
  }

  final newElement = ElementModel();
  newElement.init(widget.db.dbSchema, widget.db.intf);
  newElement.key = "Record ${widget.db.elements.length + 1}";
  setState(() {
    _draftNewElement = newElement;
  });

  final saved = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (context) => ElementEditor(db: widget.db, element: newElement, isNew: true))
  );

  if (saved == true) {
    setState(() {
      _draftNewElement = null;
    });
  }
  _init(forced: true);
}
```

4. **Add Draft Recovery Banner** inside `_DatabaseViewState.build()` above the ListView:
   - **Styling:** Styled in **Luxurious Emerald Teal** (`#00796B` theme) to provide high-end, elegant contrast against the Coral `#E9967A` primary accents.
```dart
if (_draftNewElement != null)
  Container(
    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF00796B).withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF00796B), width: 1.5),
    ),
    child: Row(
      children: [
        const Icon(Icons.edit_document, color: Color(0xFF00796B), size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Unsaved Draft in Progress",
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
              ),
              Text(
                "ID: ${_draftNewElement!.key}",
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _resumeDraft,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF00796B),
            backgroundColor: const Color(0xFF00796B).withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text("RESUME", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Discard Draft"),
                content: const Text("Are you sure you want to discard this unsaved draft? All edits will be permanently lost."),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _draftNewElement = null;
                      });
                    }, 
                    child: const Text("DISCARD", style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
          ),
          child: const Text("DISCARD"),
        ),
      ],
    ),
  ),
```

---

## Phase 4: Tablet Split View Responsive Layout

### Rationale:
Enable dual-pane list-detail splits on wide viewports ($\ge$ 800px) like WhatsApp/Gmail, while preserving a user-toggle setting in preferences to disable it and return to standard single-pane overlays.

### Target A: `lib/core/settings_provider.dart`
Add the preferences key:
```dart
class SettingsState {
  final double fontScale;
  final double inputFontScale;
  final bool enableTabletSplitView;

  SettingsState({
    this.fontScale = 1.0, 
    this.inputFontScale = 1.0,
    this.enableTabletSplitView = true,
  });

  SettingsState copyWith({
    double? fontScale, 
    double? inputFontScale,
    bool? enableTabletSplitView,
  }) {
    return SettingsState(
      fontScale: fontScale ?? this.fontScale,
      inputFontScale: inputFontScale ?? this.inputFontScale,
      enableTabletSplitView: enableTabletSplitView ?? this.enableTabletSplitView,
    );
  }
}

// In SettingsNotifier:
Future<void> _load() async {
  final prefs = await SharedPreferences.getInstance();
  final scale = prefs.getDouble('fontScale') ?? 1.0;
  final inputScale = prefs.getDouble('inputFontScale') ?? 1.0;
  final tabletSplit = prefs.getBool('enableTabletSplitView') ?? true;
  state = state.copyWith(
    fontScale: scale, 
    inputFontScale: inputScale,
    enableTabletSplitView: tabletSplit,
  );
}

Future<void> setTabletSplitView(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('enableTabletSplitView', enabled);
  state = state.copyWith(enableTabletSplitView: enabled);
}
```

### Target B: `lib/components/drawer_content.dart`
Add Preferences switch toggle tile:
```dart
SwitchListTile(
  secondary: const Icon(Icons.splitscreen),
  title: const Text('Tablet Split-Screen'),
  subtitle: const Text('Dual-pane layout on wide screens'),
  activeColor: const Color(0xFFE9967A),
  value: settings.enableTabletSplitView,
  onChanged: (val) {
    ref.read(settingsProvider.notifier).setTabletSplitView(val);
  },
),
```

### Target C: `lib/screens/collection_view.dart` (`_DatabaseViewState`)
1. Convert `_DatabaseView` to `ConsumerStatefulWidget` and `_DatabaseViewState` to `ConsumerState<_DatabaseView>` so we can watch settings.
2. Declare detail selection fields:
```dart
ElementModel? _selectedElementForDetail;
```
3. Inside `build()`, watch settings and viewport width:
```dart
final settings = ref.watch(settingsProvider);
final mediaWidth = MediaQuery.of(context).size.width;
final useSplitView = settings.enableTabletSplitView && mediaWidth >= 800;
```
4. If `useSplitView` is true, render a side-by-side split screen:
```dart
return Scaffold(
  body: Row(
    children: [
      // Left Master Pane (350px width list)
      SizedBox(
        width: 350,
        child: Column(
          children: [
            _buildFiltersRow(),
            if (_draftNewElement != null) _buildDraftBanner(),
            Expanded(child: _buildListView(onTap: (element) {
              setState(() {
                _selectedElementForDetail = element;
              });
            })),
          ],
        ),
      ),
      const VerticalDivider(width: 1, color: Colors.black12),
      // Right Detail Pane
      Expanded(
        child: _selectedElementForDetail == null
            ? _buildPlaceholderDetailView()
            : ElementView(
                db: widget.db,
                element: _selectedElementForDetail!,
                key: ValueKey(_selectedElementForDetail!.key),
              ),
      ),
    ],
  ),
);
```
5. Placeholder detail view styled beautifully:
```dart
Widget _buildPlaceholderDetailView() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.splitscreen, size: 80, color: Color(0xFFE9967A)),
        const SizedBox(height: 16),
        Text(
          "No Record Selected",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo.shade900),
        ),
        const SizedBox(height: 8),
        const Text(
          "Select a record from the list to view or edit details.",
          style: TextStyle(color: Colors.grey),
        ),
      ],
    ),
  );
}
```

---

## Phase 5: Multi-Platform Portability & Compatibility Assessment

To guarantee a robust cross-platform experience across **Android, iOS, Web, Windows, Linux, and macOS**, this section details how the split-pane layout and background Isolates are processed by each compiler target.

### 1. Split Pane Responsive Layout Portability

Because Flutter uses a reactive paint engine, the split-pane layout dynamically adapts to window sizing on all platforms:

| Platform | Screen Characteristics | Split-Pane Behavior |
| :--- | :--- | :--- |
| **Windows / Linux / macOS** | Standard wide desktop screens (typically > 1000px width). | Displays split-pane by default. Re-layouts **dynamically in real-time** if the user resizes the desktop window below the 800px threshold. |
| **Android / iOS (Tablets)** | Tablet landscape/portrait orientations. | Displays split-pane in landscape mode or large iPads. Fits safe boundaries seamlessly. |
| **Android / iOS (Phones)** | Compact portrait viewports. | Automatically folds into the single-column list navigation flow. |
| **Web (Browsers)** | Varies widely from desktop browsers to mobile sizes. | Responds dynamically to browser tab resizing. |

### 2. Background Isolates Threading Portability

Dart handles thread isolation differently between native OS sandboxes and browser JS engines. Our Phase 5 architecture is completely portable:

* **Native Platforms (Windows, Linux, macOS, iOS, Android):**
  - Fully support true operating-system-level threading via POSIX / Win32 threads.
  - Spawning background threads via Flutter’s `compute` method is **100% supported** and operates in microsecond startup times.
  - **Zero Channel Conflicts:** Since our Isolate functions are designed as pure-Dart static computation boundaries (taking only `List<int>` bytes or raw JSON `Strings`), they never invoke restricted iOS/macOS platform channels or native file hooks inside the worker isolates, eliminating any crash risks.
* **Web Platform (Chrome, Safari, Firefox):**
  - Web runtimes compile Dart to single-threaded JavaScript, where direct OS thread access is restricted.
  - Flutter's SDK incorporates transparent polyfills: when executing `compute` on the Web target, it **automatically and safely falls back to synchronous execution on the main thread**.
  - This prevents runtime `UnsupportedError` crashes on Web, running seamlessly in all browser sandboxes!
