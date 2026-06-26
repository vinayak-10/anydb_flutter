import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../main.dart';
import '../services/schema_service.dart';
import '../services/collection_service.dart';
import '../services/element_db.dart';
import '../services/io_helper.dart' as io;
import '../utils/feedback_toast.dart';

class SchemaFieldEditor extends ConsumerStatefulWidget {
  final SchemaInfo schema;

  const SchemaFieldEditor({super.key, required this.schema});

  @override
  ConsumerState<SchemaFieldEditor> createState() => _SchemaFieldEditorState();
}

class _SchemaFieldEditorState extends ConsumerState<SchemaFieldEditor> {
  int _activeTab = 0; // 0: Tree Builder, 1: Raw JSON
  int _treeVersion =
      0; // Incremented on tab switch to reinitialize text field values
  Map<String, dynamic> _schemaData = {};
  final TextEditingController _rawJsonController = TextEditingController();
  bool _isLoading = true;
  String _errorMessage = "";
  final Map<String, bool> _expandedNodes = {};

  @override
  void initState() {
    super.initState();
    _loadSchemaData();
  }

  Future<void> _loadSchemaData() async {
    try {
      final fileService = ref.read(fileServiceProvider);
      final data = await fileService.readJson(widget.schema.path);
      if (data != null) {
        _schemaData = Map<String, dynamic>.from(data);
        final prettyJson = const JsonEncoder.withIndent(
          '  ',
        ).convert(_schemaData);
        _rawJsonController.text = prettyJson;
      } else {
        _errorMessage = "Could not load schema content.";
      }
    } catch (e) {
      _errorMessage = "Error reading schema file: $e";
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _syncFromRawJson() {
    try {
      final decoded = jsonDecode(_rawJsonController.text);
      if (decoded is! Map) {
        throw const FormatException(
          "Schema JSON must be a key-value object (Map).",
        );
      }
      _schemaData = Map<String, dynamic>.from(decoded);
      return true;
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Invalid JSON Format"),
          content: Text("The raw JSON text could not be parsed:\n\n$e"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return false;
    }
  }

  void _syncToRawJson() {
    final prettyJson = const JsonEncoder.withIndent('  ').convert(_schemaData);
    _rawJsonController.text = prettyJson;
  }

  void _switchTab(int tab) {
    if (tab == _activeTab) return;
    if (_activeTab == 1) {
      // Switching from Raw JSON to Tree Builder: Parse text
      final success = _syncFromRawJson();
      if (!success) return;
    } else {
      // Switching from Tree Builder to Raw JSON: Serialize map
      _syncToRawJson();
    }
    setState(() {
      _activeTab = tab;
      _treeVersion++;
    });
  }

  Future<void> _save() async {
    if (_activeTab == 1) {
      final success = _syncFromRawJson();
      if (!success) return;
    }

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Initializing schema & validating structures..."),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final fileService = ref.read(fileServiceProvider);
      final collectionService = ref.read(collectionServiceProvider);

      // Read and cache the old schema content for rollback
      final oldSchemaData = await fileService.readJson(widget.schema.path);
      final oldSchemaString = jsonEncode(oldSchemaData);

      // Write new schema data to the file path
      if (kIsWeb) {
        await fileService.writeJson(
          p.dirname(widget.schema.path),
          p.basename(widget.schema.path),
          _schemaData,
        );
      } else {
        await io.writeString(widget.schema.path, jsonEncode(_schemaData));
      }

      // Try to initialize the collectionService with the new schema data
      try {
        await collectionService.init(_schemaData);

        // Re-bind database onChange triggers
        for (var content in collectionService.contents) {
          if (content.type == ContentType.database) {
            final db = content.service as ElementDb;
            db.onChanged = () {
              ref.read(databaseUpdateProvider.notifier).increment(db.key);
            };
          }
        }

        if (!mounted) return;

        // Dismiss the progress dialog
        Navigator.pop(context);

        // Show success toast
        FeedbackToast.success(context, "Schema successfully updated!");

        // Pop the editor screen back
        Navigator.pop(context, true);
      } catch (initError) {
        // Rollback: Write the old schema string back to file
        if (kIsWeb) {
          await fileService.writeJson(
            p.dirname(widget.schema.path),
            p.basename(widget.schema.path),
            oldSchemaData,
          );
        } else {
          await io.writeString(widget.schema.path, oldSchemaString);
        }

        // Re-init collectionService with the old schema data
        await collectionService.init(oldSchemaData);

        // Re-bind database onChange triggers for old schema
        for (var content in collectionService.contents) {
          if (content.type == ContentType.database) {
            final db = content.service as ElementDb;
            db.onChanged = () {
              ref.read(databaseUpdateProvider.notifier).increment(db.key);
            };
          }
        }

        if (!mounted) return;

        // Dismiss the progress dialog
        Navigator.pop(context);

        // Show error rollback warning dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Schema Initialization Failed"),
            content: Text(
              "The schema update caused an application crash, so it was automatically reverted to the working configuration:\n\n$initError",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Dismiss progress dialog
      Navigator.pop(context);
      FeedbackToast.error(context, "Failed to save schema: $e");
    }
  }

  // --- Default Schema Builders ---
  Map<String, dynamic> _createDefaultDatabase(String name) {
    return {
      "type": "database",
      "name": name,
      "version": "1.0.0",
      "storage": [
        {"type": "local"},
      ],
      "authentication": ["google"],
      "header": {"title": name, "subtitle": ""},
      "meta": {"ts": []},
      "schema": [],
    };
  }

  Map<String, dynamic> _createDefaultAggregator(String name) {
    return {
      "type": "aggregator",
      "name": name,
      "version": "1.0.0",
      "share": [
        {"type": "local"},
      ],
      "schema": [],
    };
  }

  Map<String, dynamic> _createDefaultComposite(String name) {
    return {
      "type": "composite",
      "name": name,
      "searchable": true,
      "displayGroup": [],
      "elements": [],
    };
  }

  Map<String, dynamic> _createDefaultSimpleAccount(String name) {
    return {
      "type": "simple-account",
      "name": name,
      "version": "1.0.0",
      "schema": {
        "type": "composite",
        "name": "Entry",
        "version": "1.0.0",
        "displayGroup": [],
        "elements": [],
      },
    };
  }

  Map<String, dynamic> _createDefaultElement(String name, String type) {
    final Map<String, dynamic> elem = {
      "type": type,
      "name": name,
    };
    if (type == "multi-select") {
      elem["defaultValues"] = [];
      elem["allowedValues"] = [];
    } else {
      elem["defaultValue"] = "";
    }
    return elem;
  }

  Map<String, dynamic> _createDefaultReport(String name) {
    return {
      "type": "report",
      "name": name,
      "header": {"title": "", "subtitle": ""},
      "row": [],
      "summary": [],
    };
  }

  Map<String, dynamic> _createDefaultSummary(String title) {
    return {"title": title, "formula": "", "column": ""};
  }

  // --- Tree Element Mutators ---
  void _addContentItem(String type) {
    setState(() {
      _schemaData['contents'] ??= [];
      final List contents = _schemaData['contents'];
      if (type == 'database') {
        contents.add(_createDefaultDatabase("New Database Table"));
      } else {
        contents.add(_createDefaultAggregator("New Report Aggregator"));
      }
    });
  }

  void _removeContentItem(int index) {
    setState(() {
      final List contents = _schemaData['contents'];
      contents.removeAt(index);
    });
  }

  void _moveContentItem(int index, int direction) {
    setState(() {
      final List contents = _schemaData['contents'];
      final newIndex = index + direction;
      if (newIndex >= 0 && newIndex < contents.length) {
        final item = contents.removeAt(index);
        contents.insert(newIndex, item);
      }
    });
  }

  void _addSchemaField(Map<String, dynamic> content, String type) {
    setState(() {
      content['schema'] ??= [];
      final List schema = content['schema'];
      if (type == 'composite') {
        schema.add(_createDefaultComposite("New Composite Section"));
      } else if (type == 'simple-account') {
        schema.add(_createDefaultSimpleAccount("Account"));
      } else {
        schema.add(_createDefaultElement("New Field", "text"));
      }
    });
  }

  void _removeSchemaField(Map<String, dynamic> content, int index) {
    setState(() {
      final List schema = content['schema'];
      schema.removeAt(index);
    });
  }

  void _moveSchemaField(
    Map<String, dynamic> content,
    int index,
    int direction,
  ) {
    setState(() {
      final List schema = content['schema'];
      final newIndex = index + direction;
      if (newIndex >= 0 && newIndex < schema.length) {
        final item = schema.removeAt(index);
        schema.insert(newIndex, item);
      }
    });
  }

  void _addElement(Map<String, dynamic> parent, String type) {
    setState(() {
      parent['elements'] ??= [];
      final List elements = parent['elements'];
      elements.add(_createDefaultElement("New Field", type));
    });
  }

  void _removeElement(Map<String, dynamic> parent, int index) {
    setState(() {
      final List elements = parent['elements'];
      elements.removeAt(index);
    });
  }

  void _moveElement(Map<String, dynamic> parent, int index, int direction) {
    setState(() {
      final List elements = parent['elements'];
      final newIndex = index + direction;
      if (newIndex >= 0 && newIndex < elements.length) {
        final item = elements.removeAt(index);
        elements.insert(newIndex, item);
      }
    });
  }

  void _addReport(Map<String, dynamic> content) {
    setState(() {
      content['schema'] ??= [];
      final List schema = content['schema'];
      schema.add(_createDefaultReport("New Report"));
    });
  }

  void _removeReport(Map<String, dynamic> content, int index) {
    setState(() {
      final List schema = content['schema'];
      schema.removeAt(index);
    });
  }

  void _addSummary(Map<String, dynamic> report) {
    setState(() {
      report['summary'] ??= [];
      final List summary = report['summary'];
      summary.add(_createDefaultSummary("New Summary Formula"));
    });
  }

  void _removeSummary(Map<String, dynamic> report, int index) {
    setState(() {
      final List summary = report['summary'];
      summary.removeAt(index);
    });
  }

  // --- UI Component Builders ---
  Widget _buildTabButton(int index, String title, IconData icon) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF6B1524) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? const Color(0xFF6B1524) : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : Colors.black54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String initialValue,
    required void Function(String) onChanged,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE9967A), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildTreeEditor() {
    final contents = _schemaData['contents'] as List? ?? [];
    return KeyedSubtree(
      key: ValueKey('tree-root-$_treeVersion'),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. Schema Info Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "SCHEMA METADATA",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1524),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: "Schema Name",
                    initialValue: _schemaData['name']?.toString() ?? "",
                    onChanged: (val) => _schemaData['name'] = val,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: "Description",
                    initialValue: _schemaData['description']?.toString() ?? "",
                    onChanged: (val) => _schemaData['description'] = val,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Sections Header
          Row(
            children: [
              const Text(
                "DATABASE TABLES & REPORTS",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: _addContentItem,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'database',
                    child: Row(
                      children: [
                        Icon(Icons.storage, size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Text("Add Database Table"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'aggregator',
                    child: Row(
                      children: [
                        Icon(Icons.analytics, size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Text("Add Report Aggregator"),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF6B1524)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add, size: 14, color: Color(0xFF6B1524)),
                      SizedBox(width: 4),
                      Text(
                        "ADD NEW",
                        style: TextStyle(
                          color: Color(0xFF6B1524),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 3. Contents List
          if (contents.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Text(
                  "No database tables or report aggregators created yet.",
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ),
            )
          else
            ...contents.asMap().entries.map((entry) {
              final idx = entry.key;
              final content = entry.value as Map<String, dynamic>;
              return _buildContentCard(content, idx, contents.length);
            }),
        ],
      ),
    );
  }

  Widget _buildContentCard(
    Map<String, dynamic> content,
    int idx,
    int totalCount,
  ) {
    final isDb = content['type'] == 'database';
    final name = content['name']?.toString() ?? "Untitled Section";
    final typeLabel = isDb ? "Database Table" : "Report Aggregator";
    final nodeKey = "content-$idx";
    final isExpanded = _expandedNodes[nodeKey] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDb ? Colors.blue.shade100 : Colors.orange.shade100,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          ListTile(
            dense: true,
            leading: Icon(
              isDb ? Icons.storage : Icons.analytics,
              color: isDb ? Colors.blue : Colors.orange,
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              typeLabel,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  onPressed: idx > 0 ? () => _moveContentItem(idx, -1) : null,
                  tooltip: "Move Up",
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  onPressed: idx < totalCount - 1
                      ? () => _moveContentItem(idx, 1)
                      : null,
                  tooltip: "Move Down",
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  onPressed: () => _removeContentItem(idx),
                  tooltip: "Delete Section",
                ),
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: () {
                    setState(() {
                      _expandedNodes[nodeKey] = !isExpanded;
                    });
                  },
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // High Level Configurations Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          label: "Name",
                          initialValue: name,
                          onChanged: (val) => setState(() {
                            content['name'] = val;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          label: "Version",
                          initialValue:
                              content['version']?.toString() ?? "1.0.0",
                          onChanged: (val) => content['version'] = val,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Option Action Buttons / Chips Row
                  const Text(
                    "CONFIGURATION POLICIES",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: Colors.blueGrey,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isDb) ...[
                        ActionChip(
                          avatar: const Icon(Icons.storage, size: 14),
                          label: const Text("Storage Backends"),
                          onPressed: () => _openStorageModal(content),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.vpn_key, size: 14),
                          label: const Text("Authentication"),
                          onPressed: () => _openAuthModal(content),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.title, size: 14),
                          label: const Text("Headers Banner"),
                          onPressed: () => _openHeaderModal(content),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.access_time, size: 14),
                          label: const Text("Timestamps (ts)"),
                          onPressed: () => _openTimestampModal(content),
                        ),
                      ] else ...[
                        ActionChip(
                          avatar: const Icon(Icons.share, size: 14),
                          label: const Text("Share Plugins"),
                          onPressed: () => _openShareModal(content),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Collapsible Sub-Children Section
                  if (isDb) ...[
                    _buildDatabaseFieldsCollapsible(content),
                  ] else ...[
                    _buildAggregatorReportsCollapsible(content),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Database Fields Layout Collapsible ---
  Widget _buildDatabaseFieldsCollapsible(Map<String, dynamic> content) {
    final schema = content['schema'] as List? ?? [];
    final fieldsNodeKey = "db-fields-${content['name']}";
    final isFieldsExpanded = _expandedNodes[fieldsNodeKey] ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "DATABASE FIELDS & LAYOUT (${schema.length})",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              onSelected: (val) => _addSchemaField(content, val),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'field',
                  child: Text("Add Basic Input Field"),
                ),
                const PopupMenuItem(
                  value: 'composite',
                  child: Text("Add Composite Section"),
                ),
                const PopupMenuItem(
                  value: 'simple-account',
                  child: Text("Add Simple Account Block"),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueGrey),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 12, color: Colors.blueGrey),
                    SizedBox(width: 4),
                    Text(
                      "ADD FIELD/GROUP",
                      style: TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                isFieldsExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              onPressed: () => setState(
                () => _expandedNodes[fieldsNodeKey] = !isFieldsExpanded,
              ),
            ),
          ],
        ),
        if (isFieldsExpanded) ...[
          const SizedBox(height: 8),
          if (schema.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              width: double.maxFinite,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                "No fields in this table. Click 'ADD FIELD/GROUP' to add database columns.",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: schema.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, fIdx) {
                final field = schema[fIdx] as Map<String, dynamic>;
                final type = field['type']?.toString() ?? "text";
                final name = field['name']?.toString() ?? "Untitled Field";
                final isGroup = type == 'composite' || type == 'simple-account';

                return Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      isGroup ? Icons.folder_open : Icons.description_outlined,
                      color: isGroup
                          ? const Color(0xFF6B1524)
                          : Colors.blueGrey,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      "Type: $type",
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 14),
                          onPressed: fIdx > 0
                              ? () => _moveSchemaField(content, fIdx, -1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 14),
                          onPressed: fIdx < schema.length - 1
                              ? () => _moveSchemaField(content, fIdx, 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.amber,
                          ),
                          onPressed: () =>
                              _openFieldEditorModal(content, field, fIdx),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeSchemaField(content, fIdx),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    );
  }

  // --- Aggregator Reports Collapsible ---
  Widget _buildAggregatorReportsCollapsible(Map<String, dynamic> content) {
    final schema = content['schema'] as List? ?? [];
    final reportsNodeKey = "agg-reports-${content['name']}";
    final isReportsExpanded = _expandedNodes[reportsNodeKey] ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "EXCEL REPORT SHEETS (${schema.length})",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _addReport(content),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                backgroundColor: const Color(0xFF6B1524),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add, size: 12),
              label: const Text(
                "ADD SHEET",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: Icon(
                isReportsExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              onPressed: () => setState(
                () => _expandedNodes[reportsNodeKey] = !isReportsExpanded,
              ),
            ),
          ],
        ),
        if (isReportsExpanded) ...[
          const SizedBox(height: 8),
          if (schema.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              width: double.maxFinite,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                "No report sheets configured. Click 'ADD SHEET' to generate reports.",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: schema.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, repIdx) {
                final report = schema[repIdx] as Map<String, dynamic>;
                final name = report['name']?.toString() ?? "Untitled Report";
                return Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(
                      Icons.receipt_long,
                      color: Color(0xFF6B1524),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: const Text(
                      "Click Edit to setup Columns, Sources, & Summary formulas",
                      style: TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.amber,
                          ),
                          onPressed: () =>
                              _openReportEditorModal(content, report, repIdx),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeReport(content, repIdx),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    );
  }

  // --- Hybrid Slide-Up Modal Bottom Sheets ---

  void _showModalEditor({
    required BuildContext context,
    required String title,
    required Widget child,
    List<Widget>? actions,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Pull Bar / Header
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  bottom: 8.0,
                ),
                child: Row(
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6B1524),
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16.0),
                  children: [child],
                ),
              ),
              if (actions != null) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalTextField({
    required String label,
    required String initialValue,
    required void Function(String) onChanged,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE9967A), width: 1.5),
        ),
      ),
    );
  }

  // --- Database Modals Builders ---

  void _openStorageModal(Map<String, dynamic> content) {
    _showModalEditor(
      context: context,
      title: "Storage Configuration",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          final storageList = content['storage'] as List? ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "STORAGE BACKENDS",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      setStateModal(() {
                        content['storage'] ??= [];
                        (content['storage'] as List).add({"type": "local"});
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B1524),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text(
                      "ADD STORAGE",
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (storageList.isEmpty)
                const Center(
                  child: Text("No storage configured (uses local only)."),
                )
              else
                ...storageList.asMap().entries.map((entry) {
                  final sIdx = entry.key;
                  final storage = Map<String, dynamic>.from(entry.value as Map);
                  final type = storage['type']?.toString() ?? 'local';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: type,
                                  decoration: const InputDecoration(
                                    labelText: "Storage Type",
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: "local",
                                      child: Text("Local SQLite Database"),
                                    ),
                                    DropdownMenuItem(
                                      value: "file",
                                      child: Text("Local Plaintext File"),
                                    ),
                                    DropdownMenuItem(
                                      value: "gdrive",
                                      child: Text("Google Drive Cloud Backup"),
                                    ),
                                    DropdownMenuItem(
                                      value: "rest-api",
                                      child: Text("REST API Synced Database"),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setStateModal(() {
                                        storageList[sIdx] = {"type": val};
                                      });
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  setStateModal(() {
                                    storageList.removeAt(sIdx);
                                  });
                                },
                              ),
                            ],
                          ),
                          if (type == 'gdrive') ...[
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label: "Google Drive Folder Path",
                              initialValue: storage['folder']?.toString() ?? "",
                              onChanged: (val) =>
                                  storageList[sIdx]['folder'] = val,
                            ),
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label: "Google Drive Backup File Name",
                              initialValue: storage['file']?.toString() ?? "",
                              onChanged: (val) =>
                                  storageList[sIdx]['file'] = val,
                            ),
                          ],
                          if (type == 'rest-api') ...[
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label: "HTTP Sync Endpoint URL",
                              initialValue: storage['url']?.toString() ?? "",
                              onChanged: (val) =>
                                  storageList[sIdx]['url'] = val,
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: storage['method']?.toString() ?? "POST",
                              decoration: const InputDecoration(
                                labelText: "HTTP Request Method",
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: "GET",
                                  child: Text("GET"),
                                ),
                                DropdownMenuItem(
                                  value: "POST",
                                  child: Text("POST"),
                                ),
                                DropdownMenuItem(
                                  value: "PUT",
                                  child: Text("PUT"),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  storageList[sIdx]['method'] = val;
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  void _openAuthModal(Map<String, dynamic> content) {
    _showModalEditor(
      context: context,
      title: "Authentication Settings",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          final authList = List<String>.from(content['authentication'] ?? []);
          final allOptions = ["google", "facebook", "aadhar", "otp"];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select which identity provider accounts are valid for database logins:",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ...allOptions.map((opt) {
                final isChecked = authList.contains(opt);
                return CheckboxListTile(
                  title: Text(opt.toUpperCase()),
                  activeColor: const Color(0xFF6B1524),
                  value: isChecked,
                  onChanged: (val) {
                    setStateModal(() {
                      if (val == true) {
                        authList.add(opt);
                      } else {
                        authList.remove(opt);
                      }
                      content['authentication'] = authList;
                    });
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }

  void _openHeaderModal(Map<String, dynamic> content) {
    content['header'] ??= {"title": "", "subtitle": ""};
    final header = content['header'] as Map<String, dynamic>;
    _showModalEditor(
      context: context,
      title: "Title & Subtitle Banners",
      child: Column(
        children: [
          _buildModalTextField(
            label: "AppBar Primary Title",
            initialValue: header['title']?.toString() ?? "",
            onChanged: (val) => header['title'] = val,
          ),
          const SizedBox(height: 12),
          _buildModalTextField(
            label: "AppBar Secondary Subtitle",
            initialValue: header['subtitle']?.toString() ?? "",
            onChanged: (val) => header['subtitle'] = val,
          ),
        ],
      ),
    );
  }

  void _openTimestampModal(Map<String, dynamic> content) {
    content['meta'] ??= {"ts": []};
    final meta = content['meta'] as Map<String, dynamic>;
    final tsList = List<String>.from(meta['ts'] ?? []);
    final schemaFields = _extractLeafFieldsFromContent(content);

    _showModalEditor(
      context: context,
      title: "Timestamp Keys (ts)",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select which schema fields represent transaction or registration timestamps. These fields will update dynamically when editing records.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              if (schemaFields.isEmpty)
                const Center(child: Text("No schema fields created yet."))
              else
                ...schemaFields.map((field) {
                  final isChecked = tsList.contains(field);
                  return CheckboxListTile(
                    title: Text(field),
                    activeColor: const Color(0xFF6B1524),
                    value: isChecked,
                    onChanged: (val) {
                      setStateModal(() {
                        if (val == true) {
                          tsList.add(field);
                        } else {
                          tsList.remove(field);
                        }
                        meta['ts'] = tsList;
                      });
                    },
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  List<String> _extractLeafFieldsFromContent(Map<String, dynamic> content) {
    final schema = content['schema'] as List? ?? [];
    final List<String> fields = [];

    void extract(List<dynamic> items) {
      for (var item in items) {
        if (item is! Map) continue;
        final type = item['type']?.toString() ?? '';
        final name = item['name']?.toString() ?? '';
        if (type == 'composite') {
          final elements = item['elements'];
          if (elements is List) extract(elements);
        } else if (type == 'simple-account') {
          final inner = item['schema'];
          if (inner is Map) {
            final elements = inner['elements'];
            if (elements is List) extract(elements);
          }
        } else if (type != 'meta' && name.isNotEmpty) {
          fields.add(name);
        }
      }
    }

    extract(schema);
    return fields;
  }

  void _openFieldEditorModal(
    Map<String, dynamic> content,
    Map<String, dynamic> field,
    int fIdx,
  ) {
    _showModalEditor(
      context: context,
      title: "Field: ${field['name'] ?? 'New Field'}",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          final type = field['type']?.toString() ?? "text";
          final name = field['name']?.toString() ?? "";
          final isGroup = type == 'composite' || type == 'simple-account';

          // Define standard items
          final standardItems = [
            const DropdownMenuItem(value: "text", child: Text("Text")),
            const DropdownMenuItem(value: "number", child: Text("Number / Numeric")),
            const DropdownMenuItem(value: "dateTime", child: Text("Date & Time Picker")),
            const DropdownMenuItem(value: "phoneNumber", child: Text("Phone Number Field")),
            const DropdownMenuItem(value: "reminder", child: Text("Reminder Duration Indicator")),
            const DropdownMenuItem(value: "multi-select", child: Text("Multi-Select Choices")),
            const DropdownMenuItem(value: "composite", child: Text("Composite Columns Group")),
            const DropdownMenuItem(value: "simple-account", child: Text("Simple Account Block")),
          ];

          // Dynamic recovery for custom types like list-header to prevent dropdown crash
          final List<DropdownMenuItem<String>> dropdownItems = List.from(standardItems);
          final hasType = dropdownItems.any((item) => item.value == type);
          if (!hasType) {
            dropdownItems.add(DropdownMenuItem(
              value: type,
              child: Text("Custom/System Type: $type"),
            ));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModalTextField(
                label: "Field Display / Key Name",
                initialValue: name,
                onChanged: (val) {
                  setState(() {
                    field['name'] = val;
                  });
                  setStateModal(() {});
                },
              ),
              const SizedBox(height: 12),
              _buildModalTextField(
                label: "Logical Field ID (optional)",
                initialValue: field['id']?.toString() ?? "",
                onChanged: (val) {
                  if (val.trim().isEmpty) {
                    field.remove('id');
                  } else {
                    field['id'] = val.trim();
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: "Data Input Widget Type",
                ),
                items: dropdownItems,
                onChanged: (val) {
                  if (val != null) {
                    setStateModal(() {
                      field['type'] = val;
                      if (val == 'multi-select') {
                        field.remove('defaultValue');
                        field['allowedValues'] ??= [];
                        field['defaultValues'] ??= [];
                        field['limit'] ??= 1;
                      } else if (val == 'composite') {
                        field['elements'] ??= [];
                        field['displayGroup'] ??= [];
                        field['searchable'] ??= true;
                      } else if (val == 'simple-account') {
                        field['schema'] ??= {
                          "type": "composite",
                          "name": "Entry",
                          "version": "1.0.0",
                          "displayGroup": [],
                          "elements": [],
                        };
                      }
                    });
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: field['searchable'] as bool? ?? false,
                    activeColor: const Color(0xFF6B1524),
                    onChanged: (val) {
                      setStateModal(() {
                        field['searchable'] = val ?? false;
                      });
                      setState(() {});
                    },
                  ),
                  const Text("Searchable Index Field"),
                ],
              ),
              const SizedBox(height: 12),

              if (type == 'composite') ...[
                _buildCompositeModalSection(field, setStateModal),
              ] else if (type == 'simple-account') ...[
                _buildSimpleAccountModalSection(field, setStateModal),
              ] else ...[
                if (type == 'multi-select') ...[
                  _buildModalTextField(
                    label: "Selection Limit (e.g. 1 for radio selection)",
                    initialValue: field['limit']?.toString() ?? "",
                    keyboardType: TextInputType.number,
                    onChanged: (val) => field['limit'] = int.tryParse(val),
                  ),
                  const SizedBox(height: 12),
                  _buildModalTextField(
                    label: "Default Value (comma-separated or single, optional)",
                    initialValue: field['defaultValue']?.toString() ?? "",
                    onChanged: (val) {
                      setStateModal(() {
                        if (val.trim().isEmpty) {
                          field.remove('defaultValue');
                        } else {
                          field['defaultValue'] = val;
                        }
                      });
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "ALLOWED SELECT CHOICES",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildAllowedValuesModalEditor(field, setStateModal),
                ] else if (type == 'text') ...[
                  Row(
                    children: [
                      Checkbox(
                        value: field['multiline'] as bool? ?? false,
                        activeColor: const Color(0xFF6B1524),
                        onChanged: (val) {
                          setStateModal(() {
                            field['multiline'] = val ?? false;
                            if (val == true) {
                              field['lines'] ??= 3;
                            } else {
                              field.remove('lines');
                              field.remove('multiline');
                            }
                          });
                          setState(() {});
                        },
                      ),
                      const Text("Multiline Input Area"),
                      const SizedBox(width: 20),
                      Checkbox(
                        value: field['timed'] as bool? ?? false,
                        activeColor: const Color(0xFF6B1524),
                        onChanged: (val) {
                          setStateModal(() {
                            if (val == true) {
                              field['timed'] = true;
                            } else {
                              field.remove('timed');
                            }
                          });
                          setState(() {});
                        },
                      ),
                      const Text("Timed History Logs"),
                    ],
                  ),
                  if (field['multiline'] == true) ...[
                    const SizedBox(height: 8),
                    _buildModalTextField(
                      label: "Multiline Vertical Height (number of visible rows)",
                      initialValue: field['lines']?.toString() ?? "3",
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        field['lines'] = int.tryParse(val) ?? 3;
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildModalTextField(
                    label: "Default String Value",
                    initialValue: field['defaultValue']?.toString() ?? "",
                    onChanged: (val) {
                      setStateModal(() {
                        field['defaultValue'] = val;
                      });
                      setState(() {});
                    },
                  ),
                ] else if (type == 'number') ...[
                  _buildModalTextField(
                    label: "Format Input Mask (optional, e.g. [09999]{/}[00])",
                    initialValue: field['format']?.toString() ?? "",
                    onChanged: (val) {
                      setStateModal(() {
                        if (val.trim().isEmpty) {
                          field.remove('format');
                        } else {
                          field['format'] = val.trim();
                        }
                      });
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildModalTextField(
                    label: "Default String Value",
                    initialValue: field['defaultValue']?.toString() ?? "",
                    onChanged: (val) {
                      setStateModal(() {
                        field['defaultValue'] = val;
                      });
                      setState(() {});
                    },
                  ),
                ] else if (type == 'dateTime') ...[
                  _buildModalTextField(
                    label: "DateTime Observers (comma-separated, optional)",
                    initialValue: (field['observers'] as List?)?.join(', ') ?? "",
                    onChanged: (val) {
                      setStateModal(() {
                        if (val.trim().isEmpty) {
                          field.remove('observers');
                        } else {
                          field['observers'] = val
                              .split(',')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                        }
                      });
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildModalTextField(
                    label: "Default String Value",
                    initialValue: field['defaultValue']?.toString() ?? "",
                    onChanged: (val) {
                      setStateModal(() {
                        field['defaultValue'] = val;
                      });
                      setState(() {});
                    },
                  ),
                ] else if (type == 'reminder') ...[
                  const Text(
                    "Default Duration:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _buildModalTextField(
                          label: "Days",
                          initialValue: (field['defaultValue'] as Map?)?['days']?.toString() ?? "30",
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            setStateModal(() {
                              final def = Map<String, dynamic>.from(field['defaultValue'] as Map? ?? {});
                              def['days'] = val;
                              field['defaultValue'] = def;
                            });
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildModalTextField(
                          label: "Months",
                          initialValue: (field['defaultValue'] as Map?)?['month']?.toString() ?? "0",
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            setStateModal(() {
                              final def = Map<String, dynamic>.from(field['defaultValue'] as Map? ?? {});
                              def['month'] = val;
                              field['defaultValue'] = def;
                            });
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildModalTextField(
                          label: "Years",
                          initialValue: (field['defaultValue'] as Map?)?['year']?.toString() ?? "0",
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            setStateModal(() {
                              final def = Map<String, dynamic>.from(field['defaultValue'] as Map? ?? {});
                              def['year'] = val;
                              field['defaultValue'] = def;
                            });
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  _buildModalTextField(
                    label: "Default String Value",
                    initialValue: field['defaultValue']?.toString() ?? "",
                    onChanged: (val) {
                      setStateModal(() {
                        field['defaultValue'] = val;
                      });
                      setState(() {});
                    },
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompositeModalSection(
    Map<String, dynamic> field,
    StateSetter setStateModal,
  ) {
    final elements = field['elements'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Row(
          children: [
            const Text(
              "COMPOSITE SUB-FIELDS",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            PopupMenuButton<String>(
              onSelected: (type) {
                setStateModal(() {
                  elements.add(_createDefaultElement("New Sub Field", type));
                });
                setState(() {});
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: "text", child: Text("Text Field")),
                PopupMenuItem(value: "number", child: Text("Number Field")),
                PopupMenuItem(value: "dateTime", child: Text("Date Field")),
                PopupMenuItem(value: "phoneNumber", child: Text("Phone Field")),
                PopupMenuItem(value: "reminder", child: Text("Reminder Field")),
                PopupMenuItem(
                  value: "multi-select",
                  child: Text("Choices Select"),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.indigo),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 12, color: Colors.indigo),
                    SizedBox(width: 4),
                    Text(
                      "ADD FIELD",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.indigo,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (elements.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Text(
              "No sub-fields in this composite group.",
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: elements.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, eIdx) {
              final elem = elements[eIdx] as Map<String, dynamic>;
              final eName = elem['name']?.toString() ?? "Untitled";
              final eType = elem['type']?.toString() ?? "text";
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  eName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  "Type: $eType",
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 14),
                      onPressed: eIdx > 0
                          ? () {
                              setStateModal(() {
                                final item = elements.removeAt(eIdx);
                                elements.insert(eIdx - 1, item);
                              });
                              setState(() {});
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 14),
                      onPressed: eIdx < elements.length - 1
                          ? () {
                              setStateModal(() {
                                final item = elements.removeAt(eIdx);
                                elements.insert(eIdx + 1, item);
                              });
                              setState(() {});
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        size: 14,
                        color: Colors.amber,
                      ),
                      onPressed: () => _openSubFieldEditorModal(
                        field,
                        elem,
                        eIdx,
                        setStateModal,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Colors.red,
                      ),
                      onPressed: () {
                        setStateModal(() {
                          elements.removeAt(eIdx);
                        });
                        setState(() {});
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        const Divider(),
        const Text(
          "VISUAL DISPLAY GROUPS (ROW LAYOUTS)",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        _buildDisplayGroupsModalBuilder(field, setStateModal),
      ],
    );
  }

  Widget _buildSimpleAccountModalSection(
    Map<String, dynamic> field,
    StateSetter setStateModal,
  ) {
    field['schema'] ??= {
      "type": "composite",
      "name": "Entry",
      "version": "1.0.0",
      "displayGroup": [],
      "elements": [],
    };
    final subSchema = field['schema'] as Map<String, dynamic>;
    return _buildCompositeModalSection(subSchema, setStateModal);
  }

  void _openSubFieldEditorModal(
    Map<String, dynamic> parentField,
    Map<String, dynamic> elem,
    int eIdx,
    StateSetter parentSetStateModal,
  ) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final type = elem['type']?.toString() ?? "text";
          final name = elem['name']?.toString() ?? "";

          // Define standard sub items
          final standardSubItems = [
            const DropdownMenuItem(value: "text", child: Text("Text")),
            const DropdownMenuItem(value: "number", child: Text("Number")),
            const DropdownMenuItem(value: "dateTime", child: Text("Date & Time")),
            const DropdownMenuItem(value: "phoneNumber", child: Text("Phone Number")),
            const DropdownMenuItem(value: "reminder", child: Text("Reminder")),
            const DropdownMenuItem(value: "multi-select", child: Text("Choices Select")),
          ];

          // Dynamic recovery for custom types to prevent dropdown crash
          final List<DropdownMenuItem<String>> dropdownSubItems = List.from(standardSubItems);
          final hasSubType = dropdownSubItems.any((item) => item.value == type);
          if (!hasSubType) {
            dropdownSubItems.add(DropdownMenuItem(
              value: type,
              child: Text("Custom/System Type: $type"),
            ));
          }

          return AlertDialog(
            title: const Text("Edit Sub-Field"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModalTextField(
                    label: "Sub-Field Name",
                    initialValue: name,
                    onChanged: (val) {
                      parentSetStateModal(() {
                        elem['name'] = val;
                      });
                      setStateDialog(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildModalTextField(
                    label: "Logical Field ID (optional)",
                    initialValue: elem['id']?.toString() ?? "",
                    onChanged: (val) {
                      parentSetStateModal(() {
                        if (val.trim().isEmpty) {
                          elem.remove('id');
                        } else {
                          elem['id'] = val.trim();
                        }
                      });
                      setStateDialog(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: "Type"),
                    items: dropdownSubItems,
                    onChanged: (val) {
                      if (val != null) {
                        parentSetStateModal(() {
                          elem['type'] = val;
                          if (val == 'multi-select') {
                            elem.remove('defaultValue');
                            elem['allowedValues'] ??= [];
                            elem['defaultValues'] ??= [];
                          }
                        });
                        setStateDialog(() {});
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: elem['searchable'] as bool? ?? false,
                        activeColor: const Color(0xFF6B1524),
                        onChanged: (val) {
                          parentSetStateModal(() {
                            elem['searchable'] = val ?? false;
                          });
                          setStateDialog(() {});
                          setState(() {});
                        },
                      ),
                      const Text("Searchable Index Field"),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (type == 'multi-select') ...[
                    _buildModalTextField(
                      label: "Selection Limit (e.g. 1 for radio)",
                      initialValue: elem['limit']?.toString() ?? "",
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        parentSetStateModal(() {
                          elem['limit'] = int.tryParse(val);
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildModalTextField(
                      label: "Default Value (comma-separated or single, optional)",
                      initialValue: elem['defaultValue']?.toString() ?? "",
                      onChanged: (val) {
                        parentSetStateModal(() {
                          if (val.trim().isEmpty) {
                            elem.remove('defaultValue');
                          } else {
                            elem['defaultValue'] = val;
                          }
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Choices Options",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildAllowedValuesModalEditor(elem, setStateDialog),
                  ] else if (type == 'text') ...[
                    Row(
                      children: [
                        Checkbox(
                          value: elem['multiline'] as bool? ?? false,
                          activeColor: const Color(0xFF6B1524),
                          onChanged: (val) {
                            parentSetStateModal(() {
                              elem['multiline'] = val ?? false;
                              if (val == true) {
                                elem['lines'] ??= 3;
                              } else {
                                elem.remove('lines');
                                elem.remove('multiline');
                              }
                            });
                            setStateDialog(() {});
                            setState(() {});
                          },
                        ),
                        const Text("Multiline Input"),
                        const SizedBox(width: 16),
                        Checkbox(
                          value: elem['timed'] as bool? ?? false,
                          activeColor: const Color(0xFF6B1524),
                          onChanged: (val) {
                            parentSetStateModal(() {
                              if (val == true) {
                                elem['timed'] = true;
                              } else {
                                elem.remove('timed');
                              }
                            });
                            setStateDialog(() {});
                            setState(() {});
                          },
                        ),
                        const Text("Timed Logs"),
                      ],
                    ),
                    if (elem['multiline'] == true) ...[
                      const SizedBox(height: 8),
                      _buildModalTextField(
                        label: "Multiline Vertical Height (rows)",
                        initialValue: elem['lines']?.toString() ?? "3",
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          elem['lines'] = int.tryParse(val) ?? 3;
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildModalTextField(
                      label: "Default Value",
                      initialValue: elem['defaultValue']?.toString() ?? "",
                      onChanged: (val) {
                        parentSetStateModal(() {
                          elem['defaultValue'] = val;
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                  ] else if (type == 'number') ...[
                    _buildModalTextField(
                      label: "Format Input Mask (optional)",
                      initialValue: elem['format']?.toString() ?? "",
                      onChanged: (val) {
                        parentSetStateModal(() {
                          if (val.trim().isEmpty) {
                            elem.remove('format');
                          } else {
                            elem['format'] = val.trim();
                          }
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildModalTextField(
                      label: "Default Value",
                      initialValue: elem['defaultValue']?.toString() ?? "",
                      onChanged: (val) {
                        parentSetStateModal(() {
                          elem['defaultValue'] = val;
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                  ] else if (type == 'dateTime') ...[
                    _buildModalTextField(
                      label: "DateTime Observers (comma-separated, optional)",
                      initialValue: (elem['observers'] as List?)?.join(', ') ?? "",
                      onChanged: (val) {
                        parentSetStateModal(() {
                          if (val.trim().isEmpty) {
                            elem.remove('observers');
                          } else {
                            elem['observers'] = val
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                          }
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildModalTextField(
                      label: "Default Value",
                      initialValue: elem['defaultValue']?.toString() ?? "",
                      onChanged: (val) {
                        parentSetStateModal(() {
                          elem['defaultValue'] = val;
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                  ] else if (type == 'reminder') ...[
                    const Text(
                      "Default Duration:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildModalTextField(
                            label: "Days",
                            initialValue: (elem['defaultValue'] as Map?)?['days']?.toString() ?? "30",
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              parentSetStateModal(() {
                                final def = Map<String, dynamic>.from(elem['defaultValue'] as Map? ?? {});
                                def['days'] = val;
                                elem['defaultValue'] = def;
                              });
                              setStateDialog(() {});
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildModalTextField(
                            label: "Months",
                            initialValue: (elem['defaultValue'] as Map?)?['month']?.toString() ?? "0",
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              parentSetStateModal(() {
                                final def = Map<String, dynamic>.from(elem['defaultValue'] as Map? ?? {});
                                def['month'] = val;
                                elem['defaultValue'] = def;
                              });
                              setStateDialog(() {});
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildModalTextField(
                            label: "Years",
                            initialValue: (elem['defaultValue'] as Map?)?['year']?.toString() ?? "0",
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              parentSetStateModal(() {
                                final def = Map<String, dynamic>.from(elem['defaultValue'] as Map? ?? {});
                                def['year'] = val;
                                elem['defaultValue'] = def;
                              });
                              setStateDialog(() {});
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    _buildModalTextField(
                      label: "Default Value",
                      initialValue: elem['defaultValue']?.toString() ?? "",
                      onChanged: (val) {
                        parentSetStateModal(() {
                          elem['defaultValue'] = val;
                        });
                        setStateDialog(() {});
                        setState(() {});
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CLOSE"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAllowedValuesModalEditor(
    Map<String, dynamic> field,
    StateSetter setStateModal,
  ) {
    final list = field['allowedValues'] as List? ?? [];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...list.asMap().entries.map((entry) {
          final idx = entry.key;
          final val = entry.value.toString();
          return Chip(
            visualDensity: VisualDensity.compact,
            label: Text(val, style: const TextStyle(fontSize: 11)),
            deleteIcon: const Icon(Icons.close, size: 12),
            onDeleted: () {
              setStateModal(() {
                list.removeAt(idx);
              });
              setState(() {});
            },
          );
        }),
        ActionChip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.add, size: 12),
          label: const Text("Add Option", style: TextStyle(fontSize: 11)),
          onPressed: () {
            String newVal = "";
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Add Choice Option"),
                content: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(hintText: "Option text..."),
                  onChanged: (val) => newVal = val,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("CANCEL"),
                  ),
                  TextButton(
                    onPressed: () {
                      if (newVal.isNotEmpty) {
                        setStateModal(() {
                          list.add(newVal);
                        });
                        setState(() {});
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text("ADD"),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDisplayGroupsModalBuilder(
    Map<String, dynamic> field,
    StateSetter setStateModal,
  ) {
    final displayGroup = field['displayGroup'] as List? ?? [];
    final elements = field['elements'] as List? ?? [];
    final allElementNames = elements
        .map((e) => (e as Map)['name']?.toString() ?? "")
        .where((n) => n.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...displayGroup.asMap().entries.map((entry) {
          final rIdx = entry.key;
          final rowFields = List<String>.from(entry.value as List? ?? []);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "Row ${rIdx + 1}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: Colors.red,
                      ),
                      onPressed: () {
                        setStateModal(() {
                          displayGroup.removeAt(rIdx);
                        });
                        setState(() {});
                      },
                      tooltip: "Remove Row",
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ...rowFields.asMap().entries.map((fEntry) {
                      final fIdx = fEntry.key;
                      final fName = fEntry.value;
                      return Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.white,
                        label: Text(
                          fName,
                          style: const TextStyle(fontSize: 11),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 12),
                        onDeleted: () {
                          setStateModal(() {
                            rowFields.removeAt(fIdx);
                            displayGroup[rIdx] = rowFields;
                          });
                          setState(() {});
                        },
                      );
                    }),
                    PopupMenuButton<String>(
                      onSelected: (selectedField) {
                        setStateModal(() {
                          if (!rowFields.contains(selectedField)) {
                            rowFields.add(selectedField);
                            displayGroup[rIdx] = rowFields;
                          }
                        });
                        setState(() {});
                      },
                      itemBuilder: (context) {
                        final available = allElementNames
                            .where((n) => !rowFields.contains(n))
                            .toList();
                        return available
                            .map((n) => PopupMenuItem(value: n, child: Text(n)))
                            .toList();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 10),
                            SizedBox(width: 2),
                            Text("Add Field", style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        ElevatedButton.icon(
          onPressed: () {
            setStateModal(() {
              displayGroup.add([]);
            });
            setState(() {});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade100,
            foregroundColor: Colors.black87,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          icon: const Icon(Icons.add_box_outlined, size: 14),
          label: const Text("ADD NEW ROW", style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  // --- Aggregator Modals Builders ---

  void _openShareModal(Map<String, dynamic> content) {
    _showModalEditor(
      context: context,
      title: "Share & Export Settings",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          final shareList = content['share'] as List? ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "SHARE PLUGINS",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      setStateModal(() {
                        content['share'] ??= [];
                        (content['share'] as List).add({"type": "local"});
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B1524),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text(
                      "ADD PLUGIN",
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (shareList.isEmpty)
                const Center(child: Text("No share plugins configured."))
              else
                ...shareList.asMap().entries.map((entry) {
                  final sIdx = entry.key;
                  final share = Map<String, dynamic>.from(entry.value as Map);
                  final type = share['type']?.toString() ?? 'local';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: type,
                                  decoration: const InputDecoration(
                                    labelText: "Share Destination",
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: "local",
                                      child: Text("Save locally on device"),
                                    ),
                                    DropdownMenuItem(
                                      value: "open",
                                      child: Text("Open directly in excel"),
                                    ),
                                    DropdownMenuItem(
                                      value: "e-mail",
                                      child: Text("E-mail attachment"),
                                    ),
                                    DropdownMenuItem(
                                      value: "url",
                                      child: Text("HTTP Webhook URL"),
                                    ),
                                    DropdownMenuItem(
                                      value: "ftp",
                                      child: Text("FTP Server Upload"),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setStateModal(() {
                                        shareList[sIdx] = {"type": val};
                                      });
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  setStateModal(() {
                                    shareList.removeAt(sIdx);
                                  });
                                },
                              ),
                            ],
                          ),
                          if (type == 'e-mail') ...[
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label: "Recipient E-mail Address",
                              initialValue: share['url']?.toString() ?? "",
                              onChanged: (val) => shareList[sIdx]['url'] = val,
                            ),
                          ],
                          if (type == 'url') ...[
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label: "Server Webhook URL",
                              initialValue: share['url']?.toString() ?? "",
                              onChanged: (val) => shareList[sIdx]['url'] = val,
                            ),
                          ],
                          if (type == 'ftp') ...[
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label:
                                  "FTP URI (ftp://username:password@hostname/path)",
                              initialValue: share['url']?.toString() ?? "",
                              onChanged: (val) => shareList[sIdx]['url'] = val,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  void _openReportEditorModal(
    Map<String, dynamic> content,
    Map<String, dynamic> report,
    int repIdx,
  ) {
    _showModalEditor(
      context: context,
      title: "Report Sheet: ${report['name'] ?? 'Untitled'}",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          final name = report['name']?.toString() ?? "";
          report['header'] ??= {"title": "", "subtitle": ""};
          final header = report['header'] as Map<String, dynamic>;
          final rows = report['row'] as List? ?? [];
          final summaries = report['summary'] as List? ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModalTextField(
                label: "Report Sheet Name",
                initialValue: name,
                onChanged: (val) {
                  setState(() {
                    report['name'] = val;
                  });
                  setStateModal(() {});
                },
              ),
              const SizedBox(height: 16),
              const Text(
                "EXCEL SHEET BANNER HEADER",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Colors.blueGrey,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildModalTextField(
                      label: "Header Title Banner",
                      initialValue: header['title']?.toString() ?? "",
                      onChanged: (val) => header['title'] = val,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildModalTextField(
                      label: "Header Subtitle Banner",
                      initialValue: header['subtitle']?.toString() ?? "",
                      onChanged: (val) => header['subtitle'] = val,
                    ),
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  const Text(
                    "DATA SOURCES & ROWS",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      setStateModal(() {
                        report['row'] ??= [];
                        (report['row'] as List).add({
                          "source": {"type": "database", "name": ""},
                          "columns": [],
                          "predicates": [],
                        });
                      });
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B1524),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text(
                      "ADD SOURCE",
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    "No source rows configured. Click ADD SOURCE to query database/reports.",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                )
              else
                ...rows.asMap().entries.map((entry) {
                  final rowIdx = entry.key;
                  final rowObj = entry.value as Map<String, dynamic>;
                  return _buildReportRowSourceCard(
                    rowObj,
                    rowIdx,
                    rows,
                    setStateModal,
                  );
                }),

              const Divider(),
              Row(
                children: [
                  const Text(
                    "AGGREGATION SUMMARY FORMULAS",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      setStateModal(() {
                        report['summary'] ??= [];
                        (report['summary'] as List).add({
                          "title": "New Formula",
                          "formula": "",
                          "column": "",
                        });
                      });
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B1524),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text(
                      "ADD FORMULA",
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (summaries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    "No summary formulas configured.",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                )
              else
                ...summaries.asMap().entries.map((entry) {
                  final sIdx = entry.key;
                  final formulaObj = entry.value as Map<String, dynamic>;
                  return _buildReportSummaryCard(
                    report,
                    formulaObj,
                    sIdx,
                    summaries,
                    setStateModal,
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReportRowSourceCard(
    Map<String, dynamic> rowObj,
    int rowIdx,
    List<dynamic> rows,
    StateSetter parentSetStateModal,
  ) {
    rowObj['source'] ??= {"type": "database", "name": ""};
    final source = rowObj['source'] as Map<String, dynamic>;
    final type = source['type']?.toString() ?? 'database';
    final name = source['name']?.toString() ?? '';
    final columns = rowObj['columns'] as List? ?? [];
    final predicates = rowObj['predicates'] as List? ?? [];

    // Find all databases and report aggregators in schema data
    final contentsList = _schemaData['contents'] as List? ?? [];
    final availableDbs = contentsList
        .where((c) => (c as Map)['type'] == 'database')
        .map((c) => (c as Map)['name']?.toString() ?? "")
        .where((n) => n.isNotEmpty)
        .toList();
    final availableReports = contentsList
        .where((c) => (c as Map)['type'] == 'aggregator')
        .map((c) => (c as Map)['name']?.toString() ?? "")
        .where((n) => n.isNotEmpty)
        .toList();

    final sourceOptions = type == 'database' ? availableDbs : availableReports;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: "Source Type"),
                    items: const [
                      DropdownMenuItem(
                        value: "database",
                        child: Text("Database Table"),
                      ),
                      DropdownMenuItem(
                        value: "report",
                        child: Text("Report Sheet"),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        parentSetStateModal(() {
                          source['type'] = val;
                          source['name'] = '';
                          rowObj['columns'] = [];
                          rowObj['predicates'] = [];
                        });
                        setState(() {});
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: sourceOptions.contains(name) ? name : null,
                    decoration: const InputDecoration(
                      labelText: "Select Target",
                    ),
                    items: sourceOptions
                        .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        parentSetStateModal(() {
                          source['name'] = val;
                          rowObj['columns'] = [];
                        });
                        setState(() {});
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    parentSetStateModal(() {
                      rows.removeAt(rowIdx);
                    });
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (name.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.list_alt, size: 14),
                    label: Text("Columns (${columns.length})"),
                    onPressed: () =>
                        _openRowColumnsModal(rowObj, parentSetStateModal),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.filter_list, size: 14),
                    label: Text("Filter Predicates (${predicates.length})"),
                    onPressed: () =>
                        _openRowPredicatesModal(rowObj, parentSetStateModal),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openRowColumnsModal(
    Map<String, dynamic> rowObj,
    StateSetter parentSetStateModal,
  ) {
    rowObj['source'] ??= {"type": "database", "name": ""};
    final source = rowObj['source'] as Map<String, dynamic>;
    final type = source['type']?.toString() ?? 'database';
    final name = source['name']?.toString() ?? '';
    final columns = rowObj['columns'] as List? ?? [];

    _showModalEditor(
      context: context,
      title: "Report Columns Setup",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          if (type == 'database') {
            // Find the database in schema and extract its leaf fields
            final contentsList = _schemaData['contents'] as List? ?? [];
            final dbContent = contentsList.firstWhere(
              (c) =>
                  (c as Map)['type'] == 'database' &&
                  (c as Map)['name'] == name,
              orElse: () => <String, dynamic>{},
            );
            final allDbFields = dbContent.isNotEmpty
                ? _extractLeafFieldsFromContent(dbContent)
                : <String>[];

            // Add automatic meta fields like '_counter.add.mm', '_counter.add.yy', 'Date'
            final metaFields = ["_counter.add.mm", "_counter.add.yy", "Date"];
            final combinedFields = [...allDbFields, ...metaFields];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Select which database columns to include in the report sheet:",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                if (combinedFields.isEmpty)
                  const Center(child: Text("No fields found in database."))
                else
                  ...combinedFields.map((fName) {
                    final isChecked = columns.contains(fName);
                    return CheckboxListTile(
                      title: Text(fName),
                      activeColor: const Color(0xFF6B1524),
                      value: isChecked,
                      onChanged: (val) {
                        setStateModal(() {
                          if (val == true) {
                            columns.add(fName);
                          } else {
                            columns.remove(fName);
                          }
                          rowObj['columns'] = columns;
                        });
                        parentSetStateModal(() {});
                        setState(() {});
                      },
                    );
                  }),
              ],
            );
          } else {
            // Report source type: column formula configurations
            // e.g. [{"title": "Charges", "formula": "'Daily'!A7"}]
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      "FORMULA COLUMNS",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () {
                        setStateModal(() {
                          columns.add({"title": "New Col", "formula": ""});
                          rowObj['columns'] = columns;
                        });
                        parentSetStateModal(() {});
                        setState(() {});
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B1524),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text("ADD COLUMN"),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (columns.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      "No formula columns added yet.",
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  )
                else
                  ...columns.asMap().entries.map((entry) {
                    final cIdx = entry.key;
                    final col = entry.value as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildModalTextField(
                                    label: "Column Header Title",
                                    initialValue:
                                        col['title']?.toString() ?? "",
                                    onChanged: (val) {
                                      col['title'] = val;
                                      setState(() {});
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    setStateModal(() {
                                      columns.removeAt(cIdx);
                                      rowObj['columns'] = columns;
                                    });
                                    parentSetStateModal(() {});
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label:
                                  "Excel Cell Reference Formula (e.g. 'Daily'!A7)",
                              initialValue: col['formula']?.toString() ?? "",
                              onChanged: (val) {
                                col['formula'] = val;
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          }
        },
      ),
    );
  }

  void _openRowPredicatesModal(
    Map<String, dynamic> rowObj,
    StateSetter parentSetStateModal,
  ) {
    final predicates = rowObj['predicates'] as List? ?? [];
    _showModalEditor(
      context: context,
      title: "Filtering & Formatting Predicates",
      child: StatefulBuilder(
        builder: (context, setStateModal) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "PREDICATES LIST",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      setStateModal(() {
                        predicates.add({
                          "operation": "date",
                          "column": "Date",
                          "parameter": {"match": true, "type": "day"},
                        });
                        rowObj['predicates'] = predicates;
                      });
                      parentSetStateModal(() {});
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B1524),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text("ADD PREDICATE"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (predicates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    "No predicates configured. Row data is unfiltered.",
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                )
              else
                ...predicates.asMap().entries.map((entry) {
                  final pIdx = entry.key;
                  final pred = entry.value as Map<String, dynamic>;
                  final operation = pred['operation']?.toString() ?? 'date';
                  final column = pred['column']?.toString() ?? '';
                  pred['parameter'] ??= {};
                  final parameter = pred['parameter'] as Map<String, dynamic>;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: operation,
                                  decoration: const InputDecoration(
                                    labelText: "Operation type",
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: "date",
                                      child: Text("Date Filter"),
                                    ),
                                    DropdownMenuItem(
                                      value: "convert",
                                      child: Text("Type Convert"),
                                    ),
                                    DropdownMenuItem(
                                      value: "generate",
                                      child: Text("Auto-Generate Report"),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setStateModal(() {
                                        pred['operation'] = val;
                                        if (val == 'convert') {
                                          pred['parameter'] = {"to": "date"};
                                          pred['column'] = "Date";
                                        } else if (val == 'generate') {
                                          pred['parameter'] = {};
                                          pred.remove('column');
                                        } else {
                                          pred['parameter'] = {
                                            "match": true,
                                            "type": "day",
                                          };
                                          pred['column'] = "Date";
                                        }
                                      });
                                      parentSetStateModal(() {});
                                      setState(() {});
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  setStateModal(() {
                                    predicates.removeAt(pIdx);
                                    rowObj['predicates'] = predicates;
                                  });
                                  parentSetStateModal(() {});
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                          if (operation != 'generate') ...[
                            const SizedBox(height: 8),
                            _buildModalTextField(
                              label: "Target Column Key",
                              initialValue: column,
                              onChanged: (val) {
                                pred['column'] = val;
                                setState(() {});
                              },
                            ),
                          ],
                          if (operation == 'date') ...[
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              title: const Text("Filter by match date value"),
                              value: parameter['match'] as bool? ?? true,
                              onChanged: (val) {
                                setStateModal(() {
                                  parameter['match'] = val ?? true;
                                });
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: parameter['type']?.toString() ?? "day",
                              decoration: const InputDecoration(
                                labelText: "Match Frequency",
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: "day",
                                  child: Text("Daily Match"),
                                ),
                                DropdownMenuItem(
                                  value: "month",
                                  child: Text("Monthly Match"),
                                ),
                                DropdownMenuItem(
                                  value: "year",
                                  child: Text("Yearly Match"),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setStateModal(() {
                                    parameter['type'] = val;
                                  });
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                          if (operation == 'convert') ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: parameter['to']?.toString() ?? "date",
                              decoration: const InputDecoration(
                                labelText: "Convert Format",
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: "date",
                                  child: Text("Date"),
                                ),
                                DropdownMenuItem(
                                  value: "number",
                                  child: Text("Number"),
                                ),
                                DropdownMenuItem(
                                  value: "string",
                                  child: Text("String"),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setStateModal(() {
                                    parameter['to'] = val;
                                  });
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReportSummaryCard(
    Map<String, dynamic> report,
    Map<String, dynamic> formulaObj,
    int sIdx,
    List<dynamic> summaries,
    StateSetter parentSetStateModal,
  ) {
    final title = formulaObj['title']?.toString() ?? 'Summary Formula';
    final column = formulaObj['column']?.toString() ?? '';
    final formula = formulaObj['formula']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.functions, color: Colors.orange),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          "Col: $column  |  Formula: $formula",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 14, color: Colors.amber),
              onPressed: () => _openSummaryFormulaModal(
                formulaObj,
                sIdx,
                parentSetStateModal,
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 14,
                color: Colors.red,
              ),
              onPressed: () {
                parentSetStateModal(() {
                  summaries.removeAt(sIdx);
                });
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openSummaryFormulaModal(
    Map<String, dynamic> formulaObj,
    int sIdx,
    StateSetter parentSetStateModal,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final title = formulaObj['title']?.toString() ?? '';
          final column = formulaObj['column']?.toString() ?? '';
          final formula = formulaObj['formula']?.toString() ?? '';

          return AlertDialog(
            title: const Text("Edit Summary Formula"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModalTextField(
                    label: "Header Cell Title",
                    initialValue: title,
                    onChanged: (val) {
                      parentSetStateModal(() {
                        formulaObj['title'] = val;
                      });
                      setStateDialog(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildModalTextField(
                    label: "Target Column Key",
                    initialValue: column,
                    onChanged: (val) {
                      parentSetStateModal(() {
                        formulaObj['column'] = val;
                      });
                      setStateDialog(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildModalTextField(
                    label:
                        r"Excel Formula Expression (e.g. SUM($Paid.START:$Paid.END))",
                    initialValue: formula,
                    onChanged: (val) {
                      parentSetStateModal(() {
                        formulaObj['formula'] = val;
                      });
                      setStateDialog(() {});
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CLOSE"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Edit Schema: ${widget.schema.name}"),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Color(0xFF6B1524)),
            onPressed: _save,
            tooltip: "Save Schema",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Segmented Tab Selector
                  _buildTabBar(),

                  // Body View based on tab selection
                  Expanded(
                    child: _activeTab == 0
                        ? _buildTreeEditor()
                        : Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  "Directly modify the JSON structure below. Changes will be validated for correct syntax and initialized live.",
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _rawJsonController,
                                    maxLines: null,
                                    minLines: null,
                                    expands: true,
                                    autofocus: false,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          "Enter schema JSON structure...",
                                      contentPadding: const EdgeInsets.all(16),
                                      fillColor: Colors.grey.shade50,
                                      filled: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE9967A),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  // Save / Cancel Bottom Action Row
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text("CANCEL"),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6B1524),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text("SAVE CHANGES"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          _buildTabButton(0, "Interactive Builder", Icons.account_tree),
          const SizedBox(width: 12),
          _buildTabButton(1, "Raw JSON", Icons.code),
        ],
      ),
    );
  }
}
