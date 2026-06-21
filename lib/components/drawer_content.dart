import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/settings_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/google_drive_service.dart';
import '../services/collection_service.dart';
import '../services/element_db.dart';
import '../services/sqlite_helper.dart';
import '../screens/logs_page.dart';
import '../main.dart';
import '../services/schema_service.dart';
import '../screens/schema_field_editor.dart';
import '../screens/collection_view.dart';
import '../services/file_service.dart';

class DrawerContent extends ConsumerWidget {
  final String? currentSchemaName;
  final VoidCallback? onBackToHome;
  const DrawerContent({super.key, this.currentSchemaName, this.onBackToHome});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final googleDriveService = ref.watch(googleDriveServiceProvider);
    final user = ref.watch(googleUserProvider);
    final isLoggedIn = user != null;

    final schemasAsync = ref.watch(schemasProvider);
    final schemas = schemasAsync.value ?? [];

    // Resolve the active/last-loaded schema
    final String? resolvedSchemaName =
        currentSchemaName ??
        (settings.lastLoadedSchemaPath != null
            ? (schemas.isNotEmpty &&
                      schemas.any(
                        (s) => s.path == settings.lastLoadedSchemaPath,
                      ))
                  ? schemas
                        .firstWhere(
                          (s) => s.path == settings.lastLoadedSchemaPath,
                        )
                        .name
                  : null
            : null);

    SchemaInfo? activeSchema;
    if (resolvedSchemaName != null) {
      for (final s in schemas) {
        if (s.name == resolvedSchemaName) {
          activeSchema = s;
          break;
        }
      }
    }

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            if (isLoggedIn)
              UserAccountsDrawerHeader(
                accountName: Text(user.displayName ?? "User"),
                accountEmail: Text(user.email),
                currentAccountPicture: user.photoUrl != null
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(user.photoUrl!),
                      )
                    : CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Text(
                          (user.displayName ?? "U")
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                otherAccountsPictures: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SvgPicture.asset(
                      'assets/anydb_logo_yantra_prism.svg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            else
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SvgPicture.asset(
                        'assets/anydb_logo_yantra_prism.svg',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'AnyDb Menu',
                      style: TextStyle(color: Colors.white, fontSize: 24),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (resolvedSchemaName != null && !isLoggedIn)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Text(
                        "Current Schema: $resolvedSchemaName",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (resolvedSchemaName != null) ...[
                    ListTile(
                      leading: const Icon(Icons.home),
                      title: const Text('Back to Home'),
                      onTap: () async {
                        Navigator.of(context).pop(); // Close the drawer first
                        if (onBackToHome != null) {
                          onBackToHome!();
                        } else if (activeSchema != null) {
                          // Navigate back to home schema
                          final fileService = ref.read(fileServiceProvider);
                          final schemaData = await fileService.readJson(
                            activeSchema.path,
                          );
                          if (schemaData != null) {
                            final collectionService = ref.read(
                              collectionServiceProvider,
                            );
                            await collectionService.init(schemaData);

                            // Bind database onChanged triggers
                            for (var content in collectionService.contents) {
                              if (content.type == ContentType.database) {
                                final db = content.service as ElementDb;
                                db.onChanged = () {
                                  ref
                                      .read(databaseUpdateProvider.notifier)
                                      .increment(db.key);
                                };
                              }
                            }

                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CollectionView(
                                    contents: collectionService.contents,
                                    title: activeSchema!.name,
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                    if (onBackToHome != null)
                      ListTile(
                        leading: const Icon(Icons.account_tree),
                        title: const Text('Change Schema'),
                        onTap: () {
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        },
                      ),
                    // Edit Schema moved to Advanced Settings modal
                  ],
                  // View Logs moved to Advanced Settings modal
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Text(
                      'Preferences',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.format_size),
                    title: const Text('Font Size'),
                    subtitle: Text(
                      'Current Scale: ${settings.fontScale.toStringAsFixed(1)}',
                    ),
                    trailing: SizedBox(
                      width: 96,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => ref
                                .read(settingsProvider.notifier)
                                .decreaseFont(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => ref
                                .read(settingsProvider.notifier)
                                .increaseFont(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: const Text('Input Font Size'),
                    subtitle: Text(
                      'Current: ${settings.inputFontSize.toStringAsFixed(0)}pt (${settings.inputFontScale.toStringAsFixed(1)}x)',
                    ),
                    trailing: SizedBox(
                      width: 96,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => ref
                                .read(settingsProvider.notifier)
                                .decreaseInputFont(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => ref
                                .read(settingsProvider.notifier)
                                .increaseInputFont(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.splitscreen),
                    title: const Text('Tablet Split-Screen'),
                    subtitle: const Text('Dual-pane layout on wide screens'),
                    activeColor: const Color(0xFFE9967A),
                    value: settings.enableTabletSplitView,
                    onChanged: (val) {
                      ref
                          .read(settingsProvider.notifier)
                          .setTabletSplitView(val);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.account_circle_outlined),
                    title: const Text('Use Google Photo as Logo'),
                    subtitle: const Text(
                      'Display profile pic on search landing page',
                    ),
                    activeColor: const Color(0xFFE9967A),
                    value: settings.useGoogleProfilePic,
                    onChanged: (val) {
                      ref
                          .read(settingsProvider.notifier)
                          .setUseGoogleProfilePic(val);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: const Text('Custom Search Landing Logo'),
                    subtitle: Text(
                      settings.customSearchPicPath != null
                          ? "Path: ...${settings.customSearchPicPath!.split('/').last}"
                          : "Default vector logo active",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: settings.customSearchPicPath != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () => ref
                                .read(settingsProvider.notifier)
                                .setCustomSearchPicPath(null),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      FilePickerResult? result = await FilePicker.platform
                          .pickFiles(type: FileType.image);
                      if (result != null && result.files.single.path != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setCustomSearchPicPath(result.files.single.path);
                      }
                    },
                  ),
                  if (resolvedSchemaName != null) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(
                        Icons.admin_panel_settings,
                        color: Color(0xFF6B1524),
                      ),
                      title: const Text('Advanced Settings'),
                      onTap: () {
                        Navigator.pop(context); // Close the drawer first
                        _showAdvancedModal(
                          context,
                          ref,
                          activeSchema,
                          resolvedSchemaName,
                          onBackToHome: onBackToHome,
                        );
                      },
                    ),
                  ],
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Text(
                      'Cloud Services',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!isLoggedIn)
                    ListTile(
                      leading: const Icon(Icons.login),
                      title: const Text('Login to Google Drive'),
                      onTap: () async {
                        final account = await googleDriveService.login();
                        if (account != null) {
                          ref
                              .read(googleUserProvider.notifier)
                              .setUser(account);
                          if (context.mounted) {
                            Navigator.pop(context); // Close the drawer
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Google Drive Authorized"),
                              ),
                            );
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Login failed")),
                            );
                          }
                        }
                      },
                    ),
                  if (isLoggedIn && resolvedSchemaName != null)
                    ListTile(
                      leading: const Icon(Icons.backup, color: Colors.blue),
                      title: const Text('Manual Backup to Drive'),
                      onTap: () async {
                        final collectionService = ref.read(
                          collectionServiceProvider,
                        );
                        final contents = collectionService.contents;

                        if (contents.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("No database loaded to backup"),
                            ),
                          );
                          return;
                        }

                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) =>
                              const Center(child: CircularProgressIndicator()),
                        );

                        try {
                          int backedUpCount = 0;
                          for (var content in contents) {
                            if (content.type == ContentType.database) {
                              final db = content.service as ElementDb;
                              await db.initDb();
                              final data = await db.exportDb();
                              await googleDriveService.manualBackup(
                                content.name,
                                data,
                                schemaName: resolvedSchemaName,
                              );
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
                                "Backup completed: $backedUpCount databases uploaded to Google Drive /xyz.maya/",
                              ),
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
                                "Backup failed: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e.toString()}",
                              ),
                              action: SnackBarAction(
                                label: "DETAILS",
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      content: SingleChildScrollView(
                                        child: Text(e.toString()),
                                      ),
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
                title: const Text(
                  'Logout from Google',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  await googleDriveService.logout();
                  ref.read(googleUserProvider.notifier).setUser(null);
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("Logged out")));
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

List<String> _extractLeafFieldNames(List<dynamic> schema) {
  final List<String> fields = [];
  // Types that are containers with nested `elements`
  const containerTypes = {'composite', 'list-header'};

  void extract(List<dynamic> items) {
    for (var item in items) {
      if (item is! Map) continue;
      final type = item['type']?.toString() ?? '';
      final name = item['name']?.toString() ?? '';

      if (containerTypes.contains(type)) {
        // Recurse into nested elements
        final elements = item['elements'];
        if (elements is List) {
          extract(elements);
        }
      } else if (type == 'simple-account') {
        // simple-account has schema.elements
        final innerSchema = item['schema'];
        if (innerSchema is Map) {
          final elements = innerSchema['elements'];
          if (elements is List) {
            extract(elements);
          }
        }
      } else if (type != 'meta' && name.isNotEmpty) {
        // Leaf field — skip meta fields as they are auto-generated
        fields.add(name);
      }
    }
  }

  extract(schema);
  return fields;
}

List<String> getPrioritizedFields(List<String> allSchemaFields) {
  final likelyKeywords = [
    'id',
    'number',
    'code',
    'key',
    'phone',
    'card',
    'sku',
    'serial',
    'barcode',
  ];

  // Split into priority items and secondary items
  final priorityList = allSchemaFields.where((field) {
    final lowerField = field.toLowerCase();
    return likelyKeywords.any((keyword) => lowerField.contains(keyword));
  }).toList();

  final secondaryList = allSchemaFields
      .where((field) => !priorityList.contains(field))
      .toList();

  // Return prioritized list with likely candidates at the top
  return [...priorityList, ...secondaryList];
}

void _showAdvancedModal(
  BuildContext context,
  WidgetRef ref,
  SchemaInfo? activeSchema,
  String? resolvedSchemaName, {
  VoidCallback? onBackToHome,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFFFAF8F5), // Premium Alabaster Cream
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
    ),
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20.0,
            right: 20.0,
            top: 20.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Advanced Settings",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1524), // Velvet Crimson
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24.0),
              if (resolvedSchemaName != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Business Unique Key',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final collectionService = ref.read(
                      collectionServiceProvider,
                    );
                    final contents = collectionService.contents;

                    ElementDb? activeDb;
                    for (var content in contents) {
                      if (content.type == ContentType.database) {
                        activeDb = content.service as ElementDb;
                        break;
                      }
                    }

                    if (activeDb == null) {
                      return const SizedBox.shrink();
                    }

                    final schemaFields = _extractLeafFieldNames(
                      activeDb.dbSchema,
                    );

                    if (schemaFields.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return FutureBuilder<String?>(
                      future: SqliteHelper.getBusinessUniqueKey(
                        resolvedSchemaName,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: SizedBox(
                              height: 48,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }

                        final currentKey = snapshot.data;

                        // Prioritize the fields using our smart sorting heuristic!
                        final prioritizedFields = getPrioritizedFields(
                          schemaFields,
                        );

                        // Ensure currentKey is in the dropdown items (or set to default if not set yet)
                        final activeKey =
                            (currentKey != null &&
                                prioritizedFields.contains(currentKey))
                            ? currentKey
                            : (prioritizedFields.isNotEmpty
                                  ? prioritizedFields.first
                                  : null);

                        return StatefulBuilder(
                          builder: (context, setStateDropdown) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: DropdownButtonFormField<String>(
                                value: activeKey,
                                isExpanded: true,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                        vertical: 10.0,
                                      ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                ),
                                items: prioritizedFields.map((field) {
                                  final isLikely =
                                      [
                                        'id',
                                        'number',
                                        'code',
                                        'key',
                                        'phone',
                                        'card',
                                        'sku',
                                        'serial',
                                        'barcode',
                                      ].any(
                                        (k) =>
                                            field.toLowerCase().contains(k),
                                      );
                                  return DropdownMenuItem<String>(
                                    value: field,
                                    child: Row(
                                      children: [
                                        Icon(
                                          isLikely
                                              ? Icons.key
                                              : Icons.label_outline,
                                          size: 16,
                                          color: isLikely
                                              ? Colors.indigo
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            field,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: isLikely
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: isLikely
                                                  ? Colors.indigo.shade900
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newVal) async {
                                  if (newVal != null) {
                                    await SqliteHelper.setBusinessUniqueKey(
                                      resolvedSchemaName,
                                      newVal,
                                    );
                                    setStateDropdown(() {
                                      // Update local dropdown state
                                    });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Unique key updated to '$newVal'",
                                          ),
                                          backgroundColor: Colors.indigo,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16.0),
              ],
              if (activeSchema != null)
                ListTile(
                  leading: const Icon(
                    Icons.edit_note,
                    color: Color(0xFF6B1524),
                  ),
                  title: const Text('Edit Schema'),
                  onTap: () async {
                    Navigator.of(context).pop(); // Close the modal
                    final updated = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SchemaFieldEditor(schema: activeSchema),
                      ),
                    );
                    if (updated == true) {
                      ref.invalidate(schemasProvider);
                      final fileService = ref.read(fileServiceProvider);
                      final schemaData = await fileService.readJson(
                        activeSchema.path,
                      );
                      if (schemaData != null) {
                        final collectionService = ref.read(
                          collectionServiceProvider,
                        );
                        await collectionService.init(schemaData);
                        if (context.mounted) {
                          if (onBackToHome != null) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CollectionView(
                                  contents: collectionService.contents,
                                  title: activeSchema.name,
                                ),
                              ),
                            );
                          }
                        }
                      }
                    }
                  },
                ),
              if (resolvedSchemaName != null)
                ListTile(
                  leading: const Icon(Icons.history_edu, color: Color(0xFF6B1524)),
                  title: const Text('View Logs'),
                  onTap: () {
                    Navigator.of(context).pop(); // Close the modal
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            LogsPage(schemaName: resolvedSchemaName),
                      ),
                    );
                  },
                ),
              if (resolvedSchemaName != null) ...[
                const Divider(height: 24.0),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    'Maintenance',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6B1524),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.cached,
                    color: Color(0xFF6B1524),
                  ),
                  title: const Text('Clear Report Cache'),
                  subtitle: const Text(
                    'Deletes cached .xlsx files for the current schema',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final fileService = ref.read(fileServiceProvider);
                    try {
                      await fileService.purgeWorkspaceCache(resolvedSchemaName);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Report cache cleared successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Cache clear failed: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Color(0xFF6B1524),
                  ),
                  title: const Text('Prune Old Exported Files'),
                  subtitle: const Text(
                    'Removes exported files older than 30 days from Documents',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final fileService = ref.read(fileServiceProvider);
                    try {
                      final count = await fileService.pruneExportedFiles(30);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              count > 0
                                  ? 'Pruned $count old file(s) from Documents'
                                  : 'No old files found to prune',
                            ),
                            backgroundColor: Colors.indigo,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Prune failed: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
