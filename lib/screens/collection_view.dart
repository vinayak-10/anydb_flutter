import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../core/formula_engine.dart';
import '../services/collection_service.dart';
import '../services/element_db.dart';
import '../services/aggregator_service.dart';
import '../services/invoker_service.dart';
import '../services/file_service.dart';
import '../services/io_helper.dart' as io;
import '../services/web_downloader.dart';
import '../services/google_drive_service.dart';
import '../models/element_model.dart';
import '../core/gen_interface.dart';
import '../components/list_header.dart';
import '../components/simple_account.dart';
import '../components/composite.dart';
import '../components/drawer_content.dart';
import '../components/overlapping_screen.dart';
import 'element_editor.dart';

class CollectionView extends StatefulWidget {
  final List<AppContent> contents;
  final String title;

  const CollectionView({super.key, required this.contents, required this.title});

  @override
  State<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<CollectionView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0;
  bool _isSearching = false;
  bool _isExactMatch = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<GlobalKey<_DatabaseViewState>> _dbKeys = [];
  final Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.contents.length; i++) {
      _dbKeys.add(GlobalKey<_DatabaseViewState>());
    }
    _tabController = TabController(length: widget.contents.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
          _selectedKeys.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleBatchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Batch Delete"),
        content: Text("Are you sure you want to permanently delete ${_selectedKeys.length} records? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("DELETE", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final currentContent = widget.contents[_currentTabIndex];
      if (currentContent.type == ContentType.database) {
        final db = currentContent.service as ElementDb;
        for (var key in _selectedKeys) {
          await db.removeRecord(key);
        }
        _selectedKeys.clear();
        _dbKeys[_currentTabIndex].currentState?.refresh();
        setState(() {});
      }
    }
  }

  Future<void> _handleDone(ElementDb db) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Done"),
        content: const Text("This will trigger database closure actions (like auto-reports or backups). You can continue working after this."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("PROCEED")),
        ],
      ),
    );

    if (confirmed == true) {
      await db.close();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Database closure actions performed successfully"))
        );
      }
    }
  }

  Future<void> _exportDb(ElementDb db) async {
    final data = await db.exportDb();
    final fileService = FileService();
    final fileName = "${db.key}_export.json";

    if (kIsWeb) {
      downloadWebData(fileName, jsonEncode(data));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export downloaded to default browser location.")));
    } else {
      final path = await fileService.getExternalRoot();
      await fileService.writeJson(path, fileName, data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Exported to $path")));
    }
  }

  Future<void> _importDb(ElementDb db) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result != null) {
        final file = result.files.first;
        dynamic data;

        if (kIsWeb || file.path == null) {
          if (file.bytes != null) {
            final jsonStr = utf8.decode(file.bytes!);
            data = await compute(jsonDecode, jsonStr);
          }
        } else {
          final jsonStr = await io.readString(file.path!);
          data = await compute(jsonDecode, jsonStr);
        }

        if (data != null && data is List) {
          if (!mounted) return;
          
          final importMode = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Import Database"),
              content: const Text("Choose how you want to import the data:"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'wipe'),
                  child: const Text("WIPE & LOAD", style: TextStyle(color: Colors.red)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'merge'),
                  child: const Text("SMART MERGE", style: TextStyle(color: Colors.blue)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL"),
                ),
              ],
            ),
          );

          if (importMode == null) return;

          // Show loading dialog
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(child: CircularProgressIndicator()),
            );
          }

          try {
            await db.importDb(data, wipeFirst: importMode == 'wipe');
            _dbKeys[_currentTabIndex].currentState?.refresh();
            
            if (mounted) {
              Navigator.pop(context); // Close loading dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(importMode == 'wipe' ? "Database wiped and reloaded" : "Database merged successfully"),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                )
              );
            }
          } catch (e) {
            if (mounted) {
              Navigator.pop(context); // Close loading dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Import Error: $e"), backgroundColor: Colors.red)
              );
            }
          }
        } else {
          throw "Invalid file format. Expected a JSON list of records.";
        }
      }
    } catch (e) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text("Import Failed: $e"),
             backgroundColor: Colors.red,
             behavior: SnackBarBehavior.floating,
           )
         );
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.contents.isEmpty) {
      return const Scaffold(body: Center(child: Text("No contents in this Schema")));
    }

    final currentContent = widget.contents[_currentTabIndex];
    String title = currentContent.name;
    String subtitle = "";

    if (currentContent.type == ContentType.database) {
      final db = currentContent.service as ElementDb;
      if (db.dbHeader.isNotEmpty && db.dbHeader[0] is List && db.dbHeader[0].isNotEmpty) {
        title = db.dbHeader[0][0].toString();
      }
      if (db.dbHeader.length > 1 && db.dbHeader[1] is List && db.dbHeader[1].isNotEmpty) {
        subtitle = db.dbHeader[1][0].toString();
      }
    } else {
      final agg = currentContent.service as AggregatorService;
      if (agg.reports.isNotEmpty) {
        final firstReport = agg.reports.first;
        if (firstReport.header.isNotEmpty && firstReport.header[0] is List && firstReport.header[0].isNotEmpty) {
          title = firstReport.header[0][0].toString();
        }
        if (firstReport.header.length > 1 && firstReport.header[1] is List && firstReport.header[1].isNotEmpty) {
          subtitle = firstReport.header[1][0].toString();
        }
      }
    }

    return Scaffold(
      appBar: _selectedKeys.isNotEmpty 
        ? AppBar(
            backgroundColor: Colors.orange.shade100,
            title: Text("Selected (${_selectedKeys.length})"),
            leading: IconButton(
              icon: const Icon(Icons.close), 
              onPressed: () => setState(() => _selectedKeys.clear())
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete), 
                onPressed: () => _handleBatchDelete()
              ),
            ],
          )
        : AppBar(
            toolbarHeight: 110.0,
            centerTitle: false,
            leading: _isSearching 
              ? IconButton(
                  icon: const Icon(Icons.keyboard_backspace, color: Color(0xFFE9967A)),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                )
              : null,
            title: _isSearching 
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 22),
                        decoration: const InputDecoration(
                          hintText: 'Search...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 20),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _isExactMatch = !_isExactMatch),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isExactMatch ? const Color(0xFFE9967A) : Colors.grey.shade300,
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          "AB",
                          style: TextStyle(
                            fontSize: 10, 
                            fontWeight: FontWeight.bold,
                            color: _isExactMatch ? Colors.white : Colors.black54
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9967A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFDAB9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.search, size: 26, color: Colors.brown),
                            onPressed: () => setState(() => _isSearching = true),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          if (currentContent.type == ContentType.database)
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 26, color: Colors.brown), 
                              onPressed: () => _dbKeys[_currentTabIndex].currentState?.onAdd(),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          if (currentContent.type == ContentType.aggregator)
                            TextButton.icon(
                              onPressed: () {
                                final agg = currentContent.service as AggregatorService;
                                agg.openReport();
                              },
                              icon: const Icon(Icons.open_in_new, color: Colors.blue),
                              label: const Text("OPEN", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 26, color: Colors.brown),
                            onSelected: (value) {
                              final db = currentContent.service as ElementDb;
                              if (value == 'import') {
                                _importDb(db);
                              } else if (value == 'export') {
                                _exportDb(db);
                              } else if (value == 'done') {
                                _handleDone(db);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'import', child: Text("Import")),
                              const PopupMenuItem(value: 'export', child: Text("Export")),
                              const PopupMenuItem(value: 'done', child: Text("Done")),
                            ],
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        actions: (_selectedKeys.isEmpty && _isSearching) ? [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchController.clear();
              });
            },
          ),
        ] : null,
      ),
      drawer: DrawerContent(currentSchemaName: widget.title),
      body: TabBarView(
        controller: _tabController,
        children: widget.contents.asMap().entries.map<Widget>((entry) {
          final idx = entry.key;
          final c = entry.value;
          if (c.type == ContentType.database) {
            return _DatabaseView(
              key: _dbKeys[idx],
              db: c.service as ElementDb, 
              schemaTitle: widget.title,
              searchQuery: _searchQuery,
              isExactMatch: _isExactMatch,
              selectedKeys: _selectedKeys,
              onToggleSelection: (key) {
                setState(() {
                  if (_selectedKeys.contains(key)) {
                    _selectedKeys.remove(key);
                  } else {
                    _selectedKeys.add(key);
                  }
                });
              },
            );
          } else {
            return _AggregatorView(agg: c.service as AggregatorService, schemaTitle: widget.title);
          }
        }).toList(),
      ),
      bottomNavigationBar: Container(
        color: Theme.of(context).colorScheme.surface,
        child: TabBar(
          controller: _tabController,
          isScrollable: widget.contents.length > 3,
          tabs: widget.contents.map<Widget>((c) => Tab(
            text: c.name,
            icon: Icon(c.type == ContentType.database ? Icons.storage : Icons.assessment),
          )).toList(),
        ),
      ),
    );
  }
}

class _DatabaseView extends StatefulWidget {
  final ElementDb db;
  final String schemaTitle;
  final String searchQuery;
  final bool isExactMatch;
  final Set<String> selectedKeys;
  final Function(String) onToggleSelection;
  const _DatabaseView({
    super.key, 
    required this.db, 
    required this.schemaTitle, 
    required this.searchQuery, 
    required this.isExactMatch,
    required this.selectedKeys,
    required this.onToggleSelection,
  });

  @override
  State<_DatabaseView> createState() => _DatabaseViewState();
}

class _DatabaseViewState extends State<_DatabaseView> {
  String _currentFilter = 'Active';
  bool _initialized = false;
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _init({bool forced = false}) async {
    await widget.db.initDb(forced: forced);
    if (mounted) setState(() => _initialized = true);
  }

  void refresh() {
    _init(forced: true);
  }

  void onAdd() async {
    final newElement = ElementModel();
    newElement.init(widget.db.dbSchema, widget.db.intf);
    newElement.key = "Record ${widget.db.elements.length + 1}";
    await Navigator.push(context, MaterialPageRoute(builder: (context) => ElementEditor(db: widget.db, element: newElement, isNew: true)));
    _init(forced: true);
  }

  void _openEditor(ElementModel element) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => ElementView(db: widget.db, element: element)));
    _init(forced: true);
  }

  Future<void> _handleCardAction(String action, ElementModel element) async {
    if (action == 'archive') {
      await widget.db.markArchive(element);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Marked as Archived")));
    } else if (action == 'restore') {
      await widget.db.restore(element);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restored to Active")));
    } else if (action == 'delete') {
      final confirmed = await _showConfirm("Mark for Delete", "This will move the record to the 'Deleted' bin for 72 hours before it is permanently purged.");
      if (confirmed) {
        await widget.db.markDelete(element);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Marked for deletion (72h remaining)")));
      }
    } else if (action == 'permanent') {
      final confirmed = await _showConfirm("PERMANENT DELETE", "Are you sure? This action CANNOT be undone and the data will be lost forever.", isDestructive: true);
      if (confirmed) {
        await widget.db.removeRecord(element.key);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Record permanently deleted")));
      }
    }
    setState(() {});
  }

  Future<bool> _showConfirm(String title, String msg, {bool isDestructive = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: isDestructive ? Colors.red : Colors.black)),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text(isDestructive ? "DELETE" : "PROCEED", style: TextStyle(color: isDestructive ? Colors.red : Colors.blue))
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const Center(child: CircularProgressIndicator());

    final filteredElements = widget.db.applyFilter(_currentFilter)
        .where((e) => widget.searchQuery.isEmpty || e.match(widget.searchQuery, exact: widget.isExactMatch)[0])
        .toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ['Active', 'Archived', 'Deleted', 'All'].map((f) => 
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Text(f, style: const TextStyle(fontSize: 12)),
                    selected: _currentFilter == f,
                    onSelected: (selected) => setState(() => _currentFilter = f),
                  ),
                )
              ).toList(),
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _listScrollController,
              itemCount: filteredElements.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final element = filteredElements[index];
                if (element.components.isNotEmpty && element.components.first is ListHeader) {
                  final header = element.components.first as ListHeader;
                  header.setDbSchema(widget.db.dbSchema);

                  final Map<String, dynamic> recordData = element.fetch();
                  final metaData = (recordData.values.first as Map)['__meta__']?['time'] ?? {};
                  final isArchived = metaData.containsKey('a');
                  final isDeleted = metaData.containsKey('d');
                  
                  Color statusColor = Colors.black87;
                  if (isDeleted) {
                    statusColor = Colors.red;
                  } else if (isArchived) {
                    statusColor = Colors.blue;
                  }

                  final titleWidgets = header.displayHeader(context, headerType: 'title', allComponents: element.components);
                  final elementWidgets = header.displayHeader(context, headerType: 'elements', allComponents: element.components, onChanged: () async {
                    await widget.db.addRecord(element);
                    setState(() {});
                  });

                  final isSelected = widget.selectedKeys.contains(element.key);

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Card(
                      elevation: isSelected ? 4 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: isSelected
                          ? BorderSide(color: Colors.orange.shade700, width: 2.5)
                          : const BorderSide(color: Colors.black12, width: 1),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: widget.selectedKeys.isNotEmpty 
                          ? () => widget.onToggleSelection(element.key)
                          : () => _openEditor(element),
                        onLongPress: () => widget.onToggleSelection(element.key),
                        child: Padding(
                          padding: const EdgeInsets.all(28.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isSelected)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12.0, top: 4.0),
                                      child: Icon(Icons.check_circle, color: Colors.orange.shade700, size: 28),
                                    ),
                                  Expanded(
                                    child: DefaultTextStyle(                                      style: TextStyle(
                                        fontSize: 22, 
                                        fontWeight: FontWeight.w900, 
                                        color: statusColor,
                                        letterSpacing: -0.2
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: titleWidgets.map((group) => Wrap(spacing: 20, children: group)).toList(),
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_horiz, size: 32),
                                    onSelected: (val) => _handleCardAction(val, element),
                                    itemBuilder: (context) => [
                                      if (isArchived || isDeleted)
                                        const PopupMenuItem(value: 'restore', child: Text("Restore Record")),
                                      if (!isArchived)
                                        const PopupMenuItem(value: 'archive', child: Text("Archive Record")),
                                      if (!isDeleted)
                                        const PopupMenuItem(value: 'delete', child: Text("Mark for Delete")),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(value: 'permanent', child: Text("PURGE DATA", style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              
                              if (elementWidgets.isNotEmpty)
                                DefaultTextStyle(
                                  style: const TextStyle(fontSize: 18, color: Colors.black87),
                                  child: _buildGroupedSection(context, "PATIENT DETAILS", 
                                    Wrap(spacing: 20, children: elementWidgets[0]),
                                    color: Colors.white,
                                    isOutlined: true,
                                    headingColor: Colors.blueGrey.shade900
                                  ),
                                ),
                              
                              const SizedBox(height: 24),
                              
                              _buildGroupedSection(context, "FINANCIAL ACCOUNT & RENEWAL", 
                                DefaultTextStyle(
                                  style: const TextStyle(fontSize: 18, color: Colors.black87),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (elementWidgets.length > 1) Wrap(spacing: 20, children: elementWidgets[1]),
                                      if (elementWidgets.length > 2) ...[
                                        const Divider(height: 32, color: Colors.black12),
                                        Wrap(spacing: 20, children: elementWidgets[2]),
                                      ],
                                    ],
                                  ),
                                ),
                                color: Colors.orange.shade50,
                                headingColor: Colors.deepOrange.shade800
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final isSelected = widget.selectedKeys.contains(element.key);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: isSelected
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.orange.shade700, width: 2)
                      )
                    : null,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: isSelected ? Icon(Icons.check_circle, color: Colors.orange.shade700) : null,
                    title: Text(element.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: element.getDisplays(onlyValue: true),
                    ),
                    onTap: widget.selectedKeys.isNotEmpty 
                      ? () => widget.onToggleSelection(element.key)
                      : () => _openEditor(element),
                    onLongPress: () => widget.onToggleSelection(element.key),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.selectedKeys.isEmpty ? FloatingActionButton.extended(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text("NEW RECORD"),
      ) : null,
    );
  }

  Widget _buildGroupedSection(BuildContext context, String label, Widget content, {required Color color, bool isOutlined = false, Color? headingColor}) {
    return Container(
      width: double.maxFinite,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: headingColor ?? Colors.blueGrey, letterSpacing: 1.8)),
              const Spacer(),
              Icon(Icons.chevron_right, size: 14, color: headingColor ?? Colors.blueGrey),
            ],
          ),
          const Divider(height: 20, thickness: 0.8, color: Colors.black12),
          content,
        ],
      ),
    );
  }
}

class ElementView extends StatefulWidget {
  final ElementDb db;
  final ElementModel element;
  const ElementView({super.key, required this.db, required this.element});

  @override
  State<ElementView> createState() => _ElementViewState();
}

class _ElementViewState extends State<ElementView> {
  @override
  Widget build(BuildContext context) {
    Widget titleWidget = Text("View ${widget.element.key}");
    
    // Try to get a better title from ListHeader if available
    if (widget.element.components.isNotEmpty && widget.element.components.first is ListHeader) {
      final header = widget.element.components.first as ListHeader;
      final titleWidgets = header.displayHeader(context, headerType: 'title', allComponents: widget.element.components);
      if (titleWidgets.isNotEmpty) {
        titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: titleWidgets.map((group) => Wrap(spacing: 20, children: group)).toList(),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (context) => ElementEditor(db: widget.db, element: widget.element)));
              setState(() {});
            },
            tooltip: "Edit Full Record",
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.element.components.length,
        itemBuilder: (context, index) {
          final c = widget.element.components[index];
          if (c.getType() == 'list-header') return const SizedBox.shrink();

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.black12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(c.getName(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.edit_note, color: Colors.blue),
                        onPressed: () => _editComponent(c),
                        tooltip: "Edit ${c.getName()}",
                      ),
                    ],
                  ),
                  const Divider(color: Colors.black12),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: c.display(
                      onlyValue: false, 
                      onChanged: () async {
                        await widget.db.addRecord(widget.element);
                        setState(() {});
                      }
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _editComponent(GenInterface c) async {
    final cClone = c.clone();
    if (cClone == null) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        child: OverlappingScreen(
          title: "Edit ${c.getName()}",
          onSave: () => Navigator.pop(context, true),
          onCancel: () => Navigator.pop(context, false),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: StatefulBuilder(
              builder: (context, setModalState) => cClone.editor(
                key: ValueKey("overlap_edit_${c.getName()}"),
                onChanged: (val) {},
                cbNotifyParent: (notifier, data, observers) {
                  if (cClone is SimpleAccount) {
                    setModalState(() {
                      cClone.updateObservers(notifier, data, observers, cClone.getComponentAtIndex(0) ?? cClone);
                    });
                  } else if (cClone is Composite) {
                    setModalState(() {
                      // Internal composite logic
                    });
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      c.populate(cClone.fetch());
      await widget.db.addRecord(widget.element);
      setState(() {});
    }
  }
}

class AggregatorReportView extends ConsumerStatefulWidget {
  final AggregatorReport report;
  final AggregatorService agg;
  final DateTime selectedDate;
  final DateTimeRange? selectedRange;
  final String schemaTitle;

  const AggregatorReportView({
    super.key, 
    required this.report, 
    required this.agg,
    required this.selectedDate,
    required this.schemaTitle,
    this.selectedRange,
  });

  @override
  ConsumerState<AggregatorReportView> createState() => _AggregatorReportViewState();
}

class _AggregatorReportViewState extends ConsumerState<AggregatorReportView> {
  bool _isGenerating = false;
  List<dynamic> _aoa = [];
  String? _lastGeneratedPath;
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final cols = widget.report.getColumns();
    if (cols.isNotEmpty) {
      _aoa = [cols];
    }
    _generate();
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _share() async {
    try {
      final filePath = await widget.agg.generateWorkbook(
        widget.report,
        date: widget.selectedRange ?? widget.selectedDate,
      );
      
      if (filePath.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to generate report file")));
        return;
      }
      
      setState(() => _lastGeneratedPath = filePath);

      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Share Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await InvokerService.open(filePath);
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text("OPEN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: const Text("Save to Device (Internal Storage)"),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("File saved to: $filePath")));
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.green),
                title: const Text("Share via..."),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  try {
                    // ignore: deprecated_member_use
                    await Share.shareXFiles([XFile(filePath)], text: 'Report: ${widget.report.key}');
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text("Share Error: $e")));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.email, color: Colors.redAccent),
                title: const Text("Send via Email"),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  try {
                    // ignore: deprecated_member_use
                    await Share.shareXFiles([XFile(filePath)], subject: 'AnyDb Report: ${widget.report.key}');
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text("Email Error: $e")));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload, color: Colors.blue),
                title: const Text("Upload to Google Drive"),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  final googleDriveService = ref.read(googleDriveServiceProvider);
                  
                  try {
                    await googleDriveService.uploadFile(
                      filePath, 
                      '${widget.report.key}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
                      path: ['xyz.maya', 'anydb', widget.schemaTitle, 'Aggregators']
                    );
                    messenger.showSnackBar(
                      const SnackBar(content: Text("Uploaded to Google Drive successfully"))
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text("Upload failed: $e"), backgroundColor: Colors.red)
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Share Error: $e")));
      }
    }
  }

  void _generate() async {
    setState(() => _isGenerating = true);
    try {
      final result = await widget.agg.generate(
        widget.report,
        date: widget.selectedRange ?? widget.selectedDate,
      );

      final dataPart = result['data'] as Map<String, dynamic>;
      final records = dataPart['data'] as List<dynamic>;

      if (records.isEmpty) {
        setState(() {
          _aoa = [];
          _isGenerating = false;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No records found for selected criteria")));
        return;
      }

      final List<String> columnNames = records[0].keys.toList();
      List<dynamic> aoa = [columnNames];
      
      for (var record in records) {
        aoa.add(columnNames.map((name) => record[name] ?? '').toList());
      }

      // On Web, do not auto-generate the workbook file to avoid auto-downloads.
      // It will be generated only when the user clicks 'OPEN'.
      String? path;
      if (!kIsWeb) {
        path = await widget.agg.generateWorkbook(
          widget.report,
          date: widget.selectedRange ?? widget.selectedDate,
        );
      }

      setState(() {
        _aoa = aoa;
        _isGenerating = false;
        _lastGeneratedPath = path;
      });
    } catch (e) {
      debugPrint("Generation Error: $e");
      setState(() => _isGenerating = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Widget _buildTable() {
    if (_aoa.isEmpty) return const SizedBox.shrink();
    
    return Scrollbar(
      controller: _verticalScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _verticalScrollController,
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.blueGrey.shade100),
            dataRowMinHeight: 48,
            columns: _aoa[0].map<DataColumn>((c) => DataColumn(
              label: Text(c.toString(), style: const TextStyle(fontWeight: FontWeight.bold))
            )).toList(),
            rows: _aoa.skip(1).map<DataRow>((r) => DataRow(
              cells: r.map<DataCell>((c) {
                String displayVal = _formatValue(c);
                return DataCell(Text(displayVal, style: const TextStyle(fontSize: 14)));
              }).toList(),
            )).toList(),
          ),
        ),
      ),
    );
  }

  String _formatValue(dynamic c) {
    if (c == null) return "";
    if (c is List) {
      if (c.isEmpty) return "";
      return _formatValue(c.first);
    }
    if (c is DateTime) return DateFormat.yMd().format(c);
    if (c is int && c > 1000000000000) {
       return DateFormat.yMd().format(DateTime.fromMillisecondsSinceEpoch(c));
    }
    return c.toString();
  }

  Widget _buildSummaryFooter() {
    final summarySchema = widget.report.summary;
    if (summarySchema.isEmpty || _aoa.length < 2) return const SizedBox.shrink();

    final headers = _aoa[0] as List<dynamic>;
    final List<Map<String, dynamic>> dataRows = [];
    for (int i = 1; i < _aoa.length; i++) {
      final row = _aoa[i] as List<dynamic>;
      final Map<String, dynamic> mapped = {};
      for (int h = 0; h < headers.length; h++) {
        mapped[headers[h].toString()] = row[h];
      }
      dataRows.add(mapped);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        border: Border(
          top: BorderSide(color: Colors.indigo.shade200, width: 1),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 20,
        runSpacing: 16,
        children: summarySchema.entries.map((e) {
          final result = FormulaEngine.evaluate(e.value.toString(), dataRows, headers);
          debugPrint("UI: Summary Evaluation for '${e.key}': formula='${e.value}', result='$result'");
          
          String display = result.toString();
          if (result is num) {
            // Format numbers with commas and no decimals (matching common financial reports)
            display = NumberFormat("#,##,###").format(result);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                e.key.toUpperCase(), 
                style: TextStyle(
                  color: Colors.indigo.shade900, 
                  fontSize: 11, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1
                )
              ),
              const SizedBox(height: 4),
              SelectableText(
                display, 
                style: TextStyle(
                  color: Colors.indigo.shade700, 
                  fontSize: 18, 
                  fontWeight: FontWeight.w900,
                )
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Report: ${widget.report.key}"),
        actions: [
          if (_aoa.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, color: Colors.blue),
              label: const Text("OPEN", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              onPressed: () async {
                if (_lastGeneratedPath == null) {
                  // Explicitly generate for web/mobile if not yet done
                  final path = await widget.agg.generateWorkbook(
                    widget.report,
                    date: widget.selectedRange ?? widget.selectedDate,
                  );
                  setState(() => _lastGeneratedPath = path);
                  await widget.agg.openReport(path);
                } else {
                  await widget.agg.openReport(_lastGeneratedPath);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _aoa.isEmpty ? null : _share,
          ),
        ],
      ),
      bottomNavigationBar: _buildSummaryFooter(),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blueGrey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Date: ${DateFormat.yMMMMd().format(widget.selectedDate)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (widget.selectedRange != null)
                      Text("Range: ${DateFormat.yMd().format(widget.selectedRange!.start)} - ${DateFormat.yMd().format(widget.selectedRange!.end)}", style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isGenerating 
              ? const Center(child: CircularProgressIndicator())
              : _buildTable(),
          ),
        ],
      ),
    );
  }
}

class _AggregatorViewState extends State<_AggregatorView> {
  DateTime _selectedDate = DateTime.now();
  DateTimeRange? _selectedRange;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Select Parameters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.black12)),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.calendar_today),
                          title: const Text("Report Date"),
                          subtitle: Text(DateFormat.yMMMMd().format(_selectedDate)),
                          trailing: const Icon(Icons.edit),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setState(() => _selectedDate = picked);
                          },
                        ),
                        if (widget.agg.key.toLowerCase().contains("monthly") || 
                            widget.agg.reports.any((r) => r.key.toLowerCase().contains("monthly")))
                          ListTile(
                            leading: const Icon(Icons.date_range),
                            title: const Text("Date Range (Optional)"),
                            subtitle: Text(_selectedRange == null 
                                ? "Select range for Monthly Report" 
                                : "${DateFormat.yMd().format(_selectedRange!.start)} - ${DateFormat.yMd().format(_selectedRange!.end)}"),
                            trailing: const Icon(Icons.edit),
                            onTap: () async {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _selectedRange = picked);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const Text("Available Reports", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                const Divider(color: Colors.black12),
                if (widget.agg.reports.any((r) => r.key.toLowerCase().contains("monthly")))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
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
                                    Text("Generating Full Monthly Report...", style: TextStyle(fontWeight: FontWeight.bold)),
                                    SizedBox(height: 8),
                                    Text("Processing each day and aggregating totals", style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );

                        try {
                          final path = await widget.agg.generateMonthlyBatch(_selectedDate);
                          if (!mounted) return;
                          Navigator.pop(context); // Close loading dialog

                          if (path.contains("No data")) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(path)));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text("Monthly Report & All Daily Sheets generated successfully!"),
                              backgroundColor: Colors.green,
                            ));
                            // Trigger refresh in UI by triggering current report generation logic
                            setState(() {});
                            await widget.agg.openReport(path);
                          }
                        } catch (e) {
                          if (!mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text("Batch Error: $e"),
                            backgroundColor: Colors.red,
                          ));
                        }
                      },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text("GENERATE FULL MONTHLY", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.agg.reports.length,
                    itemBuilder: (context, index) {
                      final r = widget.agg.reports[index];
                      return ListTile(
                        leading: const Icon(Icons.summarize, color: Colors.blue),
                        title: Text(r.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text("${r.rows.length} data sources"),
                        trailing: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => AggregatorReportView(
                                report: r, 
                                agg: widget.agg,
                                selectedDate: _selectedDate,
                                selectedRange: _selectedRange,
                                schemaTitle: widget.schemaTitle,
                              ))
                            );
                          },
                          child: const Text("GENERATE"),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AggregatorView extends StatefulWidget {
  final AggregatorService agg;
  final String schemaTitle;
  const _AggregatorView({required this.agg, required this.schemaTitle});

  @override
  State<_AggregatorView> createState() => _AggregatorViewState();
}

class _RichHeader extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback onAdd;
  final VoidCallback onSearch;
  final VoidCallback onExport;
  final VoidCallback onImport;

  const _RichHeader({
    required this.title,
    required this.subtitle,
    required this.onAdd,
    required this.onSearch,
    required this.onExport,
    required this.onImport,
  });

  @override
  State<_RichHeader> createState() => _RichHeaderState();
}

class _RichHeaderState extends State<_RichHeader> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8A80), // Opaque deepOrangeAccent.shade100
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0), // Opaque orange.shade50
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.add_circle_outline, size: 24), onPressed: widget.onAdd, tooltip: "Add Record"),
                      IconButton(icon: const Icon(Icons.search, size: 24), onPressed: widget.onSearch, tooltip: "Search"),
                      IconButton(icon: const Icon(Icons.download_outlined, size: 24), onPressed: widget.onExport, tooltip: "Export"),
                      IconButton(icon: const Icon(Icons.upload_outlined, size: 24), onPressed: widget.onImport, tooltip: "Import"),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
