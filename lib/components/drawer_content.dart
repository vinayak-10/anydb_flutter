import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/settings_provider.dart';
import '../services/google_drive_service.dart';
import '../services/collection_service.dart';
import '../services/element_db.dart';
import '../screens/logs_page.dart';

class DrawerContent extends ConsumerWidget {
  final String? currentSchemaName;
  const DrawerContent({super.key, this.currentSchemaName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final googleDriveService = ref.watch(googleDriveServiceProvider);
    final isLoggedIn = ref.watch(googleLoginProvider);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AnyDb Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
                if (currentSchemaName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      currentSchemaName!,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Back to Home'),
            onTap: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_tree),
            title: const Text('Change Schema'),
            onTap: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          if (currentSchemaName != null)
            ListTile(
              leading: const Icon(Icons.history_edu),
              title: const Text('View Logs'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => LogsPage(schemaName: currentSchemaName!)),
                );
              },
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('Preferences', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Font Size'),
            subtitle: Text('Current Scale: ${settings.fontScale.toStringAsFixed(1)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () => ref.read(settingsProvider.notifier).decreaseFont(),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => ref.read(settingsProvider.notifier).increaseFont(),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('Cloud Services', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: Icon(isLoggedIn ? Icons.logout : Icons.cloud_upload),
            title: Text(isLoggedIn ? 'Google Drive Logout' : 'Google Drive Login'),
            onTap: () async {
              if (isLoggedIn) {
                await googleDriveService.logout();
                ref.read(googleLoginProvider.notifier).set(false);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Logged out")));
              } else {
                final success = await googleDriveService.login();
                if (!context.mounted) return;
                if (success) {
                  ref.read(googleLoginProvider.notifier).set(true);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Google Drive Authorized")));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Login failed")));
                }
              }
            },
          ),
          if (isLoggedIn)
            ListTile(
              leading: const Icon(Icons.backup, color: Colors.blue),
              title: const Text('Manual Backup to Drive'),
              onTap: () async {
                final collectionService = ref.read(collectionServiceProvider);
                final contents = collectionService.contents;
                
                if (contents.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No database loaded to backup")),
                  );
                  return;
                }

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  int backedUpCount = 0;
                  for (var content in contents) {
                    if (content.type == ContentType.database) {
                      final db = content.service as ElementDb;
                      await db.initDb();
                      final data = await db.exportDb();
                      await googleDriveService.manualBackup(content.name, data, schemaName: currentSchemaName);
                      backedUpCount++;
                    }

                  }
                  
                  if (!context.mounted) return;
                  Navigator.pop(context); // Close loading dialog
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Backup completed: $backedUpCount databases uploaded to Google Drive /xyz.maya/"),
                      backgroundColor: Colors.green.shade700,
                    ),
                  );
                } catch (e) {
                  debugPrint("UI: Backup Error: $e");
                  if (!context.mounted) return;
                  Navigator.pop(context); 
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Backup failed: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e.toString()}"),
                      action: SnackBarAction(
                        label: "DETAILS",
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              content: SingleChildScrollView(child: Text(e.toString())),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}
