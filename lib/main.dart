import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/schema_service.dart';
import 'services/collection_service.dart';
import 'services/file_service.dart';
import 'screens/collection_view.dart';
import 'package:file_picker/file_picker.dart';
import 'core/settings_provider.dart';
import 'components/drawer_content.dart';
import 'services/google_drive_service.dart';

// Providers
final schemaServiceProvider = Provider((ref) => SchemaService());
final fileServiceProvider = Provider((ref) => FileService());

final appInitProvider = FutureProvider<void>((ref) async {
  final googleDriveService = ref.read(googleDriveServiceProvider);
  await googleDriveService.init();
  if (googleDriveService.currentUser != null) {
    ref.read(googleUserProvider.notifier).setUser(googleDriveService.currentUser);
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
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("App: main() started");
  runApp(
    const ProviderScope(
      child: AnyDbApp(),
    ),
  );
}

class AnyDbApp extends ConsumerWidget {
  const AnyDbApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint("AnyDbApp: building");
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'AnyDb Flutter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settings.fontScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    const Icon(Icons.schema_outlined, size: 80, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text("No schemas found at runtime.", style: TextStyle(fontSize: 18, color: Colors.grey)),
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
          return ListView.builder(
            itemCount: schemas.length,
            itemBuilder: (context, index) {
              final schema = schemas[index];
              return ListTile(
                leading: const Icon(Icons.schema, color: Colors.deepPurple),
                title: Text(schema.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(schema.path, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.output, color: Colors.blue),
                      tooltip: "Export Schema",
                      onPressed: () async {
                        await ref.read(schemaServiceProvider).exportSchema(schema);
                        ref.invalidate(schemasProvider);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: "Delete Schema",
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("Delete Schema?"),
                            content: Text("Are you sure you want to delete ${schema.name}?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("DELETE", style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await ref.read(schemaServiceProvider).deleteSchema(schema);
                          ref.invalidate(schemasProvider);
                        }
                      },
                    ),
                  ],
                ),
                onTap: () async {
                  final fileService = ref.read(fileServiceProvider);
                  debugPrint("HomePage: Loading schema from ${schema.path}");
                  final schemaData = await fileService.readJson(schema.path);
                  
                  if (schemaData != null) {
                      final collectionService = ref.read(collectionServiceProvider);
                      await collectionService.init(schemaData);

                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => CollectionView(
                          contents: collectionService.contents,
                          title: schema.name,
                        )),
                      );
                    }                },
              );
            },
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
                final Map<String, dynamic> content = decoded is Map ? decoded.cast<String, dynamic>() : decoded;
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
