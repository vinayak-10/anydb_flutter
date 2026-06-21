import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../services/io_helper.dart' as io;

class LogsPage extends ConsumerStatefulWidget {
  final String? schemaName; // Make optional as logger is global
  const LogsPage({super.key, this.schemaName});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  List<dynamic> _logFiles = [];
  bool _loading = true;
  String? _logsRoot;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final fileService = ref.read(fileServiceProvider);
    final root = await fileService.getExternalRoot();
    _logsRoot = p.join(root, 'Logs');

    List<dynamic> allLogs = [];
    if (await io.dirExists(_logsRoot!)) {
      await _collectLogs(_logsRoot!, allLogs);
    }

    // Sort by modification time, newest first
    allLogs.sort((a, b) {
      final statA = io.getFileStatSync(a.path);
      final statB = io.getFileStatSync(b.path);
      return statB.modified.compareTo(statA.modified);
    });

    if (mounted) {
      setState(() {
        _logFiles = allLogs;
        _loading = false;
      });
    }
  }

  Future<void> _collectLogs(String dirPath, List<dynamic> results) async {
    final entities = io.listDir(dirPath);
    for (var entity in entities) {
      if (io.isDirectory(entity)) {
        await _collectLogs(entity.path, results);
      } else if (entity.path.endsWith('.log')) {
        results.add(entity);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("System Logs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _loadLogs();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history_edu, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "No system logs found.",
                    style: TextStyle(color: Colors.grey),
                  ),
                  Text(
                    "Root: $_logsRoot",
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _logFiles.length,
              itemBuilder: (context, index) {
                final file = _logFiles[index];
                final stat = io.getFileStatSync(file.path);
                final name = p.basename(file.path);
                final relativeDir = p.relative(
                  p.dirname(file.path),
                  from: _logsRoot,
                );

                return ListTile(
                  leading: const Icon(Icons.description, color: Colors.orange),
                  title: Text(name),
                  subtitle: Text(
                    "$relativeDir • ${DateFormat('yyyy-MM-dd HH:mm').format(stat.modified)}",
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () => Share.shareXFiles([
                      XFile(file.path),
                    ], text: 'anydb Log: $name'),
                  ),
                  onTap: () => _viewLog(file.path, name),
                );
              },
            ),
    );
  }

  void _viewLog(String path, String name) async {
    final content = await io.readString(path);
    if (!mounted) return;

    // Show summarized view
    final lines = content.split('\n');
    final recentLines = lines.length > 50
        ? lines.sublist(lines.length - 51).join('\n')
        : content;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.article_outlined, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          height: 400,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SingleChildScrollView(
            child: Text(
              recentLines.isEmpty ? "(Empty Log)" : recentLines,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Share.shareXFiles([XFile(path)], text: 'anydb Log: $name'),
            child: const Text("SHARE FULL LOG"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }
}
