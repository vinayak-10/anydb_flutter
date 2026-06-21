import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/schema_service.dart';
import 'services/collection_service.dart';
import 'services/element_db.dart';
import 'services/file_service.dart';
import 'screens/collection_view.dart';
import 'screens/schema_field_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'core/settings_provider.dart';
import 'components/drawer_content.dart';
import 'services/google_drive_service.dart';
import 'services/web_history_helper.dart' as web_helper;
import 'services/isolate_worker.dart';
import 'core/logger.dart';

// Providers
final schemaServiceProvider = Provider((ref) => SchemaService());
final fileServiceProvider = Provider((ref) => FileService());

final appInitProvider = FutureProvider<void>((ref) async {
  final googleDriveService = ref.read(googleDriveServiceProvider);
  await googleDriveService.restoreSession();
  if (googleDriveService.currentUser != null) {
    ref
        .read(googleUserProvider.notifier)
        .setUser(googleDriveService.currentUser);
  }
});

final schemasProvider = FutureProvider<List<SchemaInfo>>((ref) async {
  await ref.watch(appInitProvider.future); // Wait for app init
  debugPrint("schemasProvider: init started");
  final service = ref.watch(schemaServiceProvider);
  await service.init();
  debugPrint("schemasProvider: found ${service.schemas.length} schemas");
  return service.schemas;
});

void main() {
  // Catch and process OAuth implicit flow popup callbacks instantly on web
  web_helper.handleWebOauthCallback();

  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("App: main() started");

  // 1. Capture all unhandled Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.log(
      "UNHANDLED FLUTTER ERROR: ${details.exceptionAsString()}\nStack: ${details.stack}",
    );
  };

  // 2. Capture all unhandled asynchronous / engine errors
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.log("UNHANDLED ASYNC ERROR: $error\nStack: $stack");
    return true; // Error is handled
  };

  // Eagerly warm up the persistent isolate pool in the background (non-blocking)
  if (!kIsWeb) {
    IsolateWorker.instance.init().catchError((e) {
      debugPrint("App: IsolateWorker warm up error: $e");
    });
  }

  runApp(const ProviderScope(child: AnyDbApp()));
}

class AnyDbApp extends ConsumerWidget {
  const AnyDbApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint("AnyDbApp: building");
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'anydb',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE9967A),
          primary: const Color(0xFFE9967A),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 2.0,
        ),
      ),
      home: const HomePage(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(settings.fontScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Timer? _autoSelectTimer;
  int _secondsRemaining = 5;
  String? _autoSelectSchemaName;
  bool _isAutoSelectActive = false;
  bool _hasInitializedAutoSelect = false;

  @override
  void dispose() {
    _autoSelectTimer?.cancel();
    super.dispose();
  }

  void _cancelAutoSelect() {
    if (_autoSelectTimer != null) {
      _autoSelectTimer!.cancel();
      _autoSelectTimer = null;
    }
    setState(() {
      _isAutoSelectActive = false;
    });
    ref.read(settingsProvider.notifier).setLastLoadedSchema(null);
  }

  Future<void> _loadSchema(SchemaInfo schema) async {
    final fileService = ref.read(fileServiceProvider);
    debugPrint("HomePage: Loading schema from ${schema.path}");
    final schemaData = await fileService.readJson(schema.path);

    if (schemaData != null) {
      final collectionService = ref.read(collectionServiceProvider);
      await collectionService.init(schemaData);

      // Bind database onChanged triggers to Riverpod databaseUpdateProvider state family
      for (var content in collectionService.contents) {
        if (content.type == ContentType.database) {
          final db = content.service as ElementDb;
          db.onChanged = () {
            ref.read(databaseUpdateProvider.notifier).increment(db.key);
          };
        }
      }

      if (!mounted) return;

      // Save last loaded schema path
      await ref
          .read(settingsProvider.notifier)
          .setLastLoadedSchema(schema.path);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CollectionView(
            contents: collectionService.contents,
            title: schema.name,
          ),
        ),
      );
    }
  }

  void _startTimer(SchemaInfo schema) {
    _autoSelectTimer?.cancel();
    _secondsRemaining = 5;
    _autoSelectSchemaName = schema.name;
    _isAutoSelectActive = true;

    _autoSelectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        _autoSelectTimer = null;
        setState(() {
          _isAutoSelectActive = false;
        });
        _loadSchema(schema);
      }
    });
  }

  void _checkAndStartAutoSelect(List<SchemaInfo> schemas) {
    if (_hasInitializedAutoSelect) return;
    _hasInitializedAutoSelect = true;

    final settings = ref.read(settingsProvider);
    final cachedPath = settings.lastLoadedSchemaPath;
    if (cachedPath != null && cachedPath.isNotEmpty) {
      final matchedSchema = schemas.firstWhere(
        (s) => s.path == cachedPath,
        orElse: () => SchemaInfo(name: '', path: ''),
      );
      if (matchedSchema.path.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startTimer(matchedSchema);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("HomePage: building");
    final schemasAsync = ref.watch(schemasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AnyDb: Select Schema'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      drawer: const DrawerContent(),
      body: schemasAsync.when(
        data: (schemas) {
          debugPrint("HomePage: data state, schemas count = ${schemas.length}");
          if (schemas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.schema_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No schemas found at runtime.",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      "Please put a schema .json file in your device's storage (xyz.maya/anydb/schema/) or click the '+' button to import one.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await ref.read(schemaServiceProvider).loadDefaultSchema();
                      ref.invalidate(schemasProvider);
                    },
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text("Seed from Built-in Default"),
                  ),
                ],
              ),
            );
          }

          // Trigger auto-select evaluation once schema list is populated
          _checkAndStartAutoSelect(schemas);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: schemas.length,
                  itemBuilder: (context, index) {
                    final schema = schemas[index];
                    return ListTile(
                      leading: const Icon(
                        Icons.schema,
                        color: Colors.deepPurple,
                      ),
                      title: Text(
                        schema.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        schema.path,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.upload, color: Colors.blue),
                            tooltip: "Export/Backup Schema",
                            onPressed: () => ref
                                .read(schemaServiceProvider)
                                .exportSchema(schema),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.amber),
                            tooltip: "Edit Schema",
                            onPressed: () async {
                              _cancelAutoSelect();
                              final updated = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      SchemaFieldEditor(schema: schema),
                                ),
                              );
                              if (updated == true) {
                                ref.invalidate(schemasProvider);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: "Delete Schema",
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Delete Schema"),
                                  content: Text(
                                    "Are you sure you want to delete '${schema.name}'? This will not delete database records.",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text("CANCEL"),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text("DELETE"),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref
                                    .read(schemaServiceProvider)
                                    .deleteSchema(schema);
                                ref.invalidate(schemasProvider);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        _cancelAutoSelect();
                        await _loadSchema(schema);
                      },
                    );
                  },
                ),
              ),
              if (_isAutoSelectActive)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 12.0,
                    top: 12.0,
                    bottom: 12.0,
                    right:
                        88.0, // Constrain card to stop before the bottom-right FAB
                  ),
                  child: Card(
                    color: const Color(0xFF6B1524), // Velvet Crimson
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: Color(0xFFE5C158),
                        width: 1.5,
                      ), // Gold Accent
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFE5C158),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Auto-selecting: $_autoSelectSchemaName",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Redirecting in $_secondsRemaining seconds...",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _cancelAutoSelect,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFE5C158),
                            ),
                            child: const Text(
                              "CANCEL",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () {
          debugPrint("HomePage: loading state");
          return const Center(child: CircularProgressIndicator());
        },
        error: (err, stack) {
          debugPrint("HomePage: error state - $err");
          return Center(child: Text("Error: $err"));
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          FilePickerResult? result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['json'],
            withData: kIsWeb,
          );

          if (result != null) {
            if (kIsWeb) {
              final bytes = result.files.single.bytes;
              if (bytes != null) {
                final decoded = jsonDecode(utf8.decode(bytes));
                final Map<String, dynamic> content = decoded is Map
                    ? decoded.cast<String, dynamic>()
                    : decoded;
                await ref.read(schemaServiceProvider).addSchema(content);
              }
            } else {
              final path = result.files.single.path;
              if (path != null) {
                await ref.read(schemaServiceProvider).addSchema(path);
              }
            }
            ref.invalidate(schemasProvider);
          }
        },
        tooltip: 'Add Schema',
        child: const Icon(Icons.add),
      ),
    );
  }
}
