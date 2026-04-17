import 'package:flutter/material.dart';
import '../services/element_db.dart';
import '../models/element_model.dart';

class ElementEditor extends StatefulWidget {
  final ElementDb db;
  final ElementModel element;
  final bool isNew;

  const ElementEditor({
    super.key,
    required this.db,
    required this.element,
    this.isNew = false,
  });

  @override
  State<ElementEditor> createState() => _ElementEditorState();
}

class _ElementEditorState extends State<ElementEditor> {
  late ElementModel _editingElement;

  @override
  void initState() {
    super.initState();
    // In a real app, you might want to deep-clone the element before editing
    _editingElement = widget.element;
  }

  Future<void> _save() async {
    final validation = _editingElement.validate();
    if (validation['valid'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Validation error: ${validation['constraint']}")),
      );
      return;
    }

    try {
      if (widget.isNew) {
        await widget.db.addRecord(_editingElement);
      } else {
        // Update logic: In your current ElementDb it just adds it back to storage
        await widget.db.addRecord(_editingElement);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? "New ${widget.db.key}" : "Edit ${widget.element.key}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Key/ID field (readonly if not new)
              TextFormField(
                initialValue: _editingElement.key,
                decoration: const InputDecoration(labelText: "Record ID/Key"),
                enabled: widget.isNew,
                onChanged: (val) => _editingElement.key = val,
              ),
              const Divider(height: 32),
              // Dynamic Editors from components
              ..._editingElement.getEditors(onChanged: () {
                // Trigger rebuild if necessary for dependent fields
                setState(() {});
              }),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text("SAVE RECORD"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
