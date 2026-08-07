import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/google_drive_service.dart';
import '../services/collection_service.dart';
import '../services/element_db.dart';
import '../utils/feedback_toast.dart';
import 'package:intl/intl.dart';

class GoogleDriveAuthButton extends ConsumerWidget {
  final String? schemaName;
  final bool compact;

  const GoogleDriveAuthButton({
    super.key,
    this.schemaName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driveState = ref.watch(googleDriveStateProvider);
    final googleDriveService = ref.watch(googleDriveServiceProvider);

    final bool isLoggedIn = driveState.isLoggedIn;
    final bool isDirty = driveState.isDirty;
    final bool isUploading = driveState.isUploading;

    final Color statusColor = !isLoggedIn
        ? Colors.redAccent
        : !isDirty
            ? Colors.green.shade600
            : Colors.blue.shade600;

    final String tooltipText = !isLoggedIn
        ? "Google Drive: Not Logged In (Tap to Login)"
        : !isDirty
            ? "Google Drive: Synced (Up to date)"
            : "Google Drive: ${driveState.entriesSinceLastBackup} entries modified since last backup";

    Widget iconWidget;
    if (isUploading) {
      iconWidget = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
        ),
      );
    } else if (!isLoggedIn) {
      iconWidget = Icon(
        Icons.cloud_off_rounded,
        color: statusColor,
        size: compact ? 22 : 24,
      );
    } else if (!isDirty) {
      iconWidget = Icon(
        Icons.cloud_done_rounded,
        color: statusColor,
        size: compact ? 22 : 24,
      );
    } else {
      iconWidget = Icon(
        Icons.cloud_queue_rounded,
        color: statusColor,
        size: compact ? 22 : 24,
      );
    }

    return IconButton(
      icon: iconWidget,
      tooltip: tooltipText,
      constraints: compact ? const BoxConstraints() : null,
      padding: compact ? const EdgeInsets.symmetric(horizontal: 6) : null,
      onPressed: () async {
        if (!isLoggedIn) {
          final user = await googleDriveService.login();
          if (user != null) {
            ref.read(googleDriveStateProvider.notifier).setUser(user);
            if (context.mounted) {
              FeedbackToast.success(
                context,
                "Connected to Google Drive (${user.email})",
              );
            }
          } else {
            if (context.mounted) {
              FeedbackToast.info(context, "Google Drive login cancelled");
            }
          }
        } else {
          _showDriveStatusMenu(context, ref, schemaName);
        }
      },
    );
  }

  void _showDriveStatusMenu(
    BuildContext context,
    WidgetRef ref,
    String? schemaName,
  ) {
    final driveState = ref.read(googleDriveStateProvider);
    final user = driveState.user;
    final googleDriveService = ref.read(googleDriveServiceProvider);

    final lastUpload = driveState.lastUploadTime;
    String lastUploadText = "No uploads in current session";
    if (lastUpload != null) {
      final now = DateTime.now();
      final diff = now.difference(lastUpload);
      if (diff.inMinutes < 1) {
        lastUploadText = "Last backup: Just now";
      } else if (diff.inMinutes < 60) {
        lastUploadText = "Last backup: ${diff.inMinutes}m ago";
      } else if (diff.inHours < 24) {
        lastUploadText =
            "Last backup: ${DateFormat('HH:mm').format(lastUpload)} (${diff.inHours}h ago)";
      } else {
        lastUploadText =
            "Last backup: ${DateFormat('MMM d, HH:mm').format(lastUpload)}";
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFAF8F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: User account details
                Row(
                  children: [
                    if (user?.photoUrl != null)
                      CircleAvatar(
                        radius: 22,
                        backgroundImage: NetworkImage(user!.photoUrl!),
                      )
                    else
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF6B1524),
                        child: Text(
                          (user?.displayName ?? user?.email ?? "U")
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? "Google Drive Account",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6B1524),
                            ),
                          ),
                          Text(
                            user?.email ?? "",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: !driveState.isDirty
                            ? Colors.green.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !driveState.isDirty
                              ? Colors.green.shade300
                              : Colors.blue.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: !driveState.isDirty
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            !driveState.isDirty
                                ? "Synced"
                                : "Changes Pending",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: !driveState.isDirty
                                  ? Colors.green.shade900
                                  : Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Status info
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        lastUploadText,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 18,
                      color: driveState.entriesSinceLastBackup > 0
                          ? Colors.blue.shade700
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        driveState.entriesSinceLastBackup > 0
                            ? "${driveState.entriesSinceLastBackup} entries added/modified since last backup"
                            : "No new entries added since last backup",
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: driveState.entriesSinceLastBackup > 0
                              ? Colors.blue.shade900
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Cloud Folder: Google Drive /xyz.maya/",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Actions: Backup Now & Logout
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B1524),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text(
                          "Backup Now",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          _triggerBackgroundBackup(context, ref, schemaName);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text("Logout"),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await googleDriveService.logout();
                        ref
                            .read(googleDriveStateProvider.notifier)
                            .setUser(null);
                        if (context.mounted) {
                          FeedbackToast.info(
                            context,
                            "Logged out of Google Drive",
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _triggerBackgroundBackup(
    BuildContext context,
    WidgetRef ref,
    String? schemaName,
  ) async {
    final googleDriveService = ref.read(googleDriveServiceProvider);
    final collectionService = ref.read(collectionServiceProvider);
    final contents = collectionService.contents;

    if (contents.isEmpty) {
      FeedbackToast.error(context, "No active database available to backup");
      return;
    }

    FeedbackToast.info(
      context,
      "Background backup started for ${contents.where((c) => c.type == ContentType.database).length} databases...",
    );

    ref.read(googleDriveStateProvider.notifier).setUploading(true);

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
            schemaName: schemaName,
          );
          backedUpCount++;
        }
      }
      ref
          .read(googleDriveStateProvider.notifier)
          .setLastUploadTime(DateTime.now());
      if (context.mounted) {
        FeedbackToast.success(
          context,
          "Backup complete: $backedUpCount databases synced to Google Drive!",
        );
      }
    } catch (e) {
      if (context.mounted) {
        FeedbackToast.error(context, "Background backup error: $e");
      }
    } finally {
      ref.read(googleDriveStateProvider.notifier).setUploading(false);
    }
  }
}
