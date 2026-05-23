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
    final user = ref.watch(googleUserProvider);
    final isLoggedIn = user != null;

    return Drawer(
      child: Column(
        children: [
          if (isLoggedIn)
            UserAccountsDrawerHeader(
              accountName: Text(user.displayName ?? "User"),
              accountEmail: Text(user.email),
              currentAccountPicture: user.photoUrl != null
                  ? CircleAvatar(backgroundImage: NetworkImage(user.photoUrl!))
                  : CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Text(
                        (user.displayName ?? "U").substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          else
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: const Row(
                children: [
                  Icon(Icons.account_circle, size: 60, color: Colors.white70),
                  SizedBox(width: 16),
                  Text(
                    'AnyDb Menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (currentSchemaName != null && !isLoggedIn)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      "Current Schema: $currentSchemaName",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                if (!isLoggedIn)
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Login to Google Drive'),
                    onTap: () async {
                      final account = await googleDriveService.login();
                      if (account != null) {
                        ref.read(googleUserProvider.notifier).setUser(account);
                        if (context.mounted) {
                          Navigator.pop(context); // Close the drawer
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Google Drive Authorized")));
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Login failed")));
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
                            await googleDriveService.manualBackup(content.name, data,
                                schemaName: currentSchemaName);
                            backedUpCount++;
                          }
                        }

                        if (!context.mounted) return;
                        Navigator.pop(context); // Close loading dialog
                        if (context.mounted) {
                          Navigator.pop(context); // Close the drawer
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                "Backup completed: $backedUpCount databases uploaded to Google Drive /xyz.maya/"),
                            backgroundColor: Colors.green.shade700,
                          ),
                        );
                      } catch (e) {
                        debugPrint("UI: Backup Error: $e");
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                "Backup failed: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e.toString()}"),
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
          ),
          if (isLoggedIn) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout from Google', style: TextStyle(color: Colors.red)),
              onTap: () async {
                await googleDriveService.logout();
                ref.read(googleUserProvider.notifier).setUser(null);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Logged out")));
                }
              },
            ),
            const SizedBox(height: 8),
          ]
        ],
      ),
    );
  }
}
