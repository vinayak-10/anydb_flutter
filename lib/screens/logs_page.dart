import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart'; // Import main to access providers

class LogsPage extends ConsumerStatefulWidget {
  final String schemaName;
  const LogsPage({super.key, required this.schemaName});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  List<String> _logFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final fileService = ref.read(fileServiceProvider);
    final path = await fileService.getLogsPath(widget.schemaName, external: true);
    final files = await fileService.getFiles(path, 'log');
    setState(() {
      _logFiles = files.reversed.toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Logs: ${widget.schemaName}")),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : _logFiles.isEmpty
          ? const Center(child: Text("No logs found"))
          : ListView.builder(
              itemCount: _logFiles.length,
              itemBuilder: (context, index) {
                final file = _logFiles[index];
                return ListTile(
                  leading: const Icon(Icons.description, color: Colors.orange),
                  title: Text(file.split('/').last),
                  onTap: () => _viewLog(file),
                );
              },
            ),
    );
  }

  void _viewLog(String path) async {
    final fileService = ref.read(fileServiceProvider);
    final content = await fileService.readJson(path);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Log Detail"),
        content: SingleChildScrollView(child: Text(content.toString())),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))],
      ),
    );
  }
}
