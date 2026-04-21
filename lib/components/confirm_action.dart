import 'package:flutter/material.dart';

class ConfirmAction extends StatefulWidget {
  final Widget child;
  final VoidCallback onConfirm;
  final String title;
  final String message;

  const ConfirmAction({
    super.key,
    required this.child,
    required this.onConfirm,
    this.title = "Confirm Action",
    this.message = "Are you sure you want to proceed?",
  });

  @override
  State<ConfirmAction> createState() => _ConfirmActionState();
}

class _ConfirmActionState extends State<ConfirmAction> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showDialog(),
      child: widget.child,
    );
  }

  void _showDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.title),
        content: Text(widget.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("PROCEED", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (result == true) {
      widget.onConfirm();
    }
  }
}
