import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/schema_service.dart';
import 'services/collection_service.dart';
import 'services/file_service.dart';
import 'screens/collection_view.dart';
import 'package:file_picker/file_picker.dart';

// Providers
final schemaServiceProvider = Provider((ref) => SchemaService());
final collectionServiceProvider = Provider((ref) => CollectionService());
final fileServiceProvider = Provider((ref) => FileService());

final schemasProvider = FutureProvider<List<SchemaInfo>>((ref) async {
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

class AnyDbApp extends StatelessWidget {
  const AnyDbApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint("AnyDbApp: building");
    return MaterialApp(
      title: 'AnyDb Flutter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
      builder: (context, child) {
        debugPrint("MaterialApp: child is ${child?.runtimeType}");
        return child ?? const SizedBox.shrink();
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
      body: schemasAsync.when(
        data: (schemas) {
          debugPrint("HomePage: data state, schemas count = ${schemas.length}");
          return schemas.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("No schemas found."),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await ref.read(schemaServiceProvider).loadDefaultSchema();
                        ref.invalidate(schemasProvider);
                      },
                      child: const Text("Load Default Schema (RKM Physio)"),
                    ),
                    const SizedBox(height: 8),
                    const Text("OR click '+' to add your own JSON schema"),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: schemas.length,
                itemBuilder: (context, index) {
                  final schema = schemas[index];
                  return ListTile(
                    leading: const Icon(Icons.schema),
                    title: Text(schema.name),
                    subtitle: Text(schema.path),
                    onTap: () async {
                      final fileService = ref.read(fileServiceProvider);
                      debugPrint("HomePage: Loading schema from ${schema.path}");
                      final schemaData = await fileService.readJson(schema.path);
                      debugPrint("HomePage: schemaData type is ${schemaData?.runtimeType}");
                      
                      if (schemaData != null) {
                        final collectionService = ref.read(collectionServiceProvider);
                        await collectionService.init(schemaData);

                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => CollectionView(
                            dbs: collectionService.dbs,
                            title: schema.name,
                          )),
                        );
                      }
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () async {
                        await ref.read(schemaServiceProvider).exportSchema(schema);
                        ref.invalidate(schemasProvider);
                      },
                    ),
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
                final content = jsonDecode(utf8.decode(bytes));
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
