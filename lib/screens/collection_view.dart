import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
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

class CollectionView extends ConsumerStatefulWidget {
  final List<AppContent> contents;
  final String title;

  const CollectionView({super.key, required this.contents, required this.title});

  @override
  ConsumerState<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends ConsumerState<CollectionView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0;
  bool _isSearching = false;
  bool _isExactMatch = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<GlobalKey<_DatabaseViewState>> _dbKeys = [];
  final Set<String> _selectedKeys = {};
  Map<String, dynamic>? _preloadedReportData;

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
        title: const Text("Finalize Day"),
        content: const Text("This will export the database locally, backup to Google Drive, and generate your Daily and Monthly reports. Continue?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("PROCEED")),
        ],
      ),
    );

    if (confirmed == true) {
      final statusNotifier = ValueNotifier<String>("Finalizing database records...");

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ValueListenableBuilder<String>(
            valueListenable: statusNotifier,
            builder: (context, status, child) {
              return Center(
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Please wait, this may take a few moments",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }

      try {
        // 1. Export database locally
        statusNotifier.value = "Saving database records locally...";
        await _exportDb(db);

        // 2. Cloud Backup to Google Drive
        try {
          final data = await db.exportDb();
          final jsonStr = jsonEncode(data);
          final googleDriveService = ref.read(googleDriveServiceProvider);
          
          if (googleDriveService.isLoggedIn) {
            statusNotifier.value = "Uploading backup to Google Drive...";
            await googleDriveService.uploadJson(
              jsonStr, 
              "${db.key}_backup_${DateTime.now().millisecondsSinceEpoch}.json",
              path: ['xyz.maya', 'anydb', widget.title, 'Database']
            );
          } else {
             throw "Not logged into Google Drive";
          }
        } catch (cloudErr) {
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text("Cloud Backup Skip: $cloudErr"), backgroundColor: Colors.orange)
             );
          }
        }

        // 3. Generate Reports
        statusNotifier.value = "Generating Daily and Monthly reports...";
        final aggregatorContent = widget.contents.firstWhere((c) => c.type == ContentType.aggregator);
        final agg = aggregatorContent.service as AggregatorService;
        
        // Daily Report (Current Day)
        final dailyReport = agg.reports.firstWhere(
          (r) => r.key.toLowerCase().contains("daily"), 
          orElse: () => agg.reports.first
        );
        final dailyPath = await agg.generateWorkbook(dailyReport, date: DateTime.now());
        
        // Monthly Report (Current Month till date)
        final monthlyReport = agg.reports.firstWhere(
          (r) => r.key.toLowerCase().contains("monthly"), 
          orElse: () => agg.reports.last
        );
        final monthlyPath = await agg.generateWorkbook(monthlyReport, date: DateTime.now());

        // Load the Daily result for UI
        final dailyResult = await agg.generate(dailyReport, date: DateTime.now());
        dailyResult['path'] = dailyPath;

        await db.close();
        
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          
          setState(() {
            _preloadedReportData = dailyResult;
            final aggIdx = widget.contents.indexWhere((c) => c.type == ContentType.aggregator);
            if (aggIdx != -1) {
              _tabController.animateTo(aggIdx);
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Database finalized and reports generated!"), 
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: "OPEN MONTHLY",
                textColor: Colors.white,
                onPressed: () async {
                   await agg.openReport(monthlyPath);
                },
              ),
            )
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Action Failed: $e"), backgroundColor: Colors.red)
          );
        }
      } finally {
        statusNotifier.dispose();
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
              builder: (context) => Center(
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          importMode == 'wipe' 
                              ? "Wiping and importing database..." 
                              : "Merging and importing database...",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Rebuilding local indexes and schema alignment",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
      backgroundColor: Colors.white,
      appBar: _selectedKeys.isNotEmpty 
        ? AppBar(
            backgroundColor: Colors.orange.shade50,
            elevation: 0,
            title: Text("Selected (${_selectedKeys.length})", style: const TextStyle(color: Colors.black87)),
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.black87), 
              onPressed: () => setState(() => _selectedKeys.clear())
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red), 
                onPressed: () => _handleBatchDelete()
              ),
            ],
          )
        : AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
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
            return _AggregatorView(
              agg: c.service as AggregatorService, 
              schemaTitle: widget.title,
              initialReportData: _preloadedReportData,
            );
          }
        }).toList(),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        child: SafeArea(
          bottom: true,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: widget.contents.map<Widget>((c) => Tab(
              text: c.name,
              icon: Icon(c.type == ContentType.database ? Icons.storage : Icons.assessment),
            )).toList(),
          ),
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
    await widget.db.initDb(forced: forced, filter: [_currentFilter]);
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
    if (!_initialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              "Loading Element Database...",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.blueGrey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Reading records for $_currentFilter view",
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    final filteredElements = widget.db.applyFilter(_currentFilter)
        .where((e) => widget.searchQuery.isEmpty || e.match(widget.searchQuery, exact: widget.isExactMatch)[0])
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ['Active', 'Archived', 'Deleted', 'All'].map((f) => 
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Text(f, style: const TextStyle(fontSize: 12)),
                    selected: _currentFilter == f,
                    backgroundColor: Colors.white,
                    selectedColor: const Color(0xFFE9967A).withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: _currentFilter == f ? const Color(0xFFE9967A) : Colors.grey.shade200)),
                    onSelected: (selected) {
                      if (selected && _currentFilter != f) {
                        setState(() {
                          _currentFilter = f;
                          _initialized = false;
                        });
                        _init(forced: true);
                      }
                    },
                  ),
                )
              ).toList(),
            ),
          ),
          const Divider(height: 1, color: Colors.black12),
          Expanded(
            child: ListView.separated(
              controller: _listScrollController,
              itemCount: filteredElements.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
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
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.orange.shade300 : Colors.grey.shade200,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected 
                              ? Colors.orange.withOpacity(0.08)
                              : Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: widget.selectedKeys.isNotEmpty 
                        ? () => widget.onToggleSelection(element.key)
                        : () => _openEditor(element),
                      onLongPress: () => widget.onToggleSelection(element.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
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
                                  child: DefaultTextStyle(
                                    style: TextStyle(
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
                            const SizedBox(height: 16),
                            
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
                            
                            const SizedBox(height: 16),
                            
                            _buildGroupedSection(context, "FINANCIAL ACCOUNT & RENEWAL", 
                              DefaultTextStyle(
                                style: const TextStyle(fontSize: 18, color: Colors.black87),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (elementWidgets.length > 1) Wrap(spacing: 20, children: elementWidgets[1]),
                                    if (elementWidgets.length > 2) ...[
                                      const Divider(height: 24, color: Colors.black12),
                                      Wrap(spacing: 20, children: elementWidgets[2]),
                                    ],
                                  ],
                                ),
                              ),
                              color: Colors.white,
                              headingColor: Colors.blueGrey.shade900
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final isSelected = widget.selectedKeys.contains(element.key);
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Colors.orange.shade300 : Colors.grey.shade200,
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected 
                            ? Colors.orange.withOpacity(0.08)
                            : Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        itemCount: widget.element.components.length,
        itemBuilder: (context, index) {
          final c = widget.element.components[index];
          if (c.getType() == 'list-header') return const SizedBox.shrink();

          return Card(
            margin: const EdgeInsets.only(bottom: 4),
            elevation: 0,
            color: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Colors.black12),
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

  void _generate({bool force = false}) async {
    setState(() => _isGenerating = true);
    try {
      final result = await widget.agg.generate(
        widget.report,
        date: widget.selectedRange ?? widget.selectedDate,
        force: force,
      );

      // result is the standardized Map payload
      final List<Map<String, dynamic>> records = List<Map<String, dynamic>>.from(result['data'] as List);

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
    if (c is num) {
      if (c % 1 == 0) return c.toInt().toString();
      return c.toStringAsFixed(2);
    }
    final s = c.toString();
    final n = double.tryParse(s.replaceAll(',', ''));
    if (n != null) {
      if (n % 1 == 0) return n.toInt().toString();
      return n.toStringAsFixed(2);
    }
    return s;
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
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.indigo.shade200, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: true,
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 20,
          runSpacing: 16,
          children: summarySchema.entries.map((e) {
            final result = FormulaEngine.evaluate(e.value.toString(), dataRows, headers);
            debugPrint("UI: Summary Evaluation for '${e.key}': formula='${e.value}', result='$result'");
            
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
                  _formatValue(result), 
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text("Report: ${widget.report.key}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: _isGenerating ? null : () => _generate(force: true),
            tooltip: "Recalculate from Database",
          ),
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
            color: Colors.white,
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
          const Divider(height: 1, color: Colors.black12),
          Expanded(
            child: _isGenerating 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        "Generating Excel Report...",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Applying formula engine and templates",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey.shade400,
                        ),
                      ),
                    ],
                  ),
                )
              : _buildTable(),
          ),
        ],
      ),
    );
  }
}

class _AggregatorView extends ConsumerStatefulWidget {
  final AggregatorService agg;
  final String schemaTitle;
  final Map<String, dynamic>? initialReportData;
  const _AggregatorView({required this.agg, required this.schemaTitle, this.initialReportData});

  @override
  ConsumerState<_AggregatorView> createState() => _AggregatorViewState();
}

class _AggregatorViewState extends ConsumerState<_AggregatorView> {
  DateTime _selectedDate = DateTime.now();
  DateTimeRange? _selectedRange;
  Map<String, dynamic>? _reportData;

  @override
  void initState() {
    super.initState();
    if (widget.initialReportData != null) {
      _reportData = widget.initialReportData;
    }
  }

  @override
  void didUpdateWidget(_AggregatorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialReportData != oldWidget.initialReportData && widget.initialReportData != null) {
      setState(() {
        _reportData = widget.initialReportData;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
      children: [
        if (_reportData != null)
           Expanded(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_reportData!['name'] ?? "Report", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
                        Row(
                          children: [
                            if (_reportData!['path'] != null)
                              IconButton(
                                icon: const Icon(Icons.share, color: Colors.indigo),
                                onPressed: () {
                                   _showShareDialog(context, _reportData!['path']);
                                },
                                tooltip: "Share",
                              ),
                            if (_reportData!['path'] != null)
                              IconButton(
                                icon: const Icon(Icons.open_in_new, color: Colors.indigo),
                                onPressed: () => widget.agg.openReport(_reportData!['path']),
                                tooltip: "Open",
                              ),
                            IconButton(onPressed: () => setState(() => _reportData = null), icon: const Icon(Icons.close)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                            columns: [
                              const DataColumn(label: Text("S.no.", style: TextStyle(fontWeight: FontWeight.bold))),
                              ...(((_reportData!['data'] ?? []) as List).isNotEmpty 
                                  ? ((_reportData!['data'] as List)[0] as Map).keys.toList() 
                                  : ["No Data"]).map((k) => DataColumn(label: Text(k.toString(), style: const TextStyle(fontWeight: FontWeight.bold)))),
                            ],
                            rows: ((_reportData!['data'] ?? []) as List).asMap().entries.map((entry) {
                              final idx = entry.key;
                              final map = entry.value as Map;
                              return DataRow(cells: [
                                DataCell(Text((idx + 1).toString())),
                                ...map.values.map((v) => DataCell(Text(_formatValue(v)))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200, width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("REPORT SUMMARY", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                          const Divider(),
                          if (_reportData!['summary'] is Map)
                            Wrap(
                              spacing: 20,
                              runSpacing: 10,
                              children: (_reportData!['summary'] as Map).entries.map((e) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.key.toString(), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                  Text(_formatValue(e.value), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              )).toList(),
                            )
                          else
                            Text(_reportData!['summary']?.toString() ?? "No Summary Available"),
                        ],
                      ),
                    ),
                 ],
               ),
             ),
           )
        else
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
                  color: Colors.white,
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
                          final path = await widget.agg.generateMonthlyBatch(_selectedDate, force: true);
                          
                          // Load the generated monthly data into UI
                          final monthlyReport = widget.agg.reports.firstWhere((r) => r.key.toLowerCase().contains("monthly"));
                          final result = await widget.agg.generate(monthlyReport, date: _selectedDate, force: true);
                          
                          if (!context.mounted) return;
                          setState(() {
                            _reportData = result;
                            _reportData!['path'] = path; // Save the path for sharing
                          });

                          // Ensure table is rendered before closing progress indicator
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                             if (context.mounted) {
                                Navigator.pop(context); // Close loading dialog
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text("Monthly Report & All Daily Sheets generated successfully!"),
                                  backgroundColor: Colors.green,
                                ));
                             }
                          });
                        } catch (e) {
                          if (!context.mounted) return;
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
    if (c is num) {
      if (c % 1 == 0) return c.toInt().toString();
      return c.toStringAsFixed(2);
    }
    final s = c.toString();
    final n = double.tryParse(s.replaceAll(',', ''));
    if (n != null) {
      if (n % 1 == 0) return n.toInt().toString();
      return n.toStringAsFixed(2);
    }
    return s;
  }

  void _showShareDialog(BuildContext context, String filePath) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Export Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.indigo),
                title: const Text("Share File"),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    // Standard share dialog for all platforms
                    // ignore: deprecated_member_use
                    await Share.shareXFiles([XFile(filePath)], text: 'Monthly Report');
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
                      p.basename(filePath),
                      path: ['xyz.maya', 'anydb', widget.schemaTitle, 'Aggregators']
                    );
                    messenger.showSnackBar(const SnackBar(content: Text("Uploaded to Google Drive successfully")));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text("Upload failed: $e"), backgroundColor: Colors.red));
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
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
