import 'package:flutter/material.dart';
import '../core/gen_interface.dart';

class MultiSelect extends GenInterface {
  String name = "";
  String id = "";
  List<String> values = [];
  List<String> allowed = [];
  int limit = 0;
  int min = 0;
  bool searchable = false;

  @override
  String getType() => "multi-select";

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    name = jsonObj['name'] ?? "";
    id = jsonObj['id']?.toString() ?? "";
    values = List<String>.from(jsonObj['defaultValues'] ?? []);
    allowed = List<String>.from(jsonObj['allowedValues'] ?? []);
    limit = jsonObj['limit'] ?? allowed.length;
    min = jsonObj['min'] ?? 0;
    searchable = jsonObj['searchable'] ?? false;
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      values = List<String>.from(jsonDb[name] ?? []);
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: values};
  }

  @override
  List<bool> match(String val) {
    if (searchable) {
      for (var v in values) {
        if (v.toLowerCase() == val.toLowerCase()) return [true, true];
        if (v.toLowerCase().contains(val.toLowerCase())) return [true, false];
      }
    }
    return [false, false];
  }

  @override
  Map<String, dynamic> validate() {
    bool valid = true;
    List<String> failedConstraints = [];

    if (values.length < min) {
      valid = false;
      failedConstraints.add("Select at least $min");
    }

    return {'name': name, 'valid': valid, 'constraint': failedConstraints};
  }

  @override
  Widget editor({required Key key, Function? onChanged}) {
    return _MultiSelectEditor(
      key: key,
      label: name,
      allowed: allowed,
      initialValues: values,
      limit: limit,
      onChanged: (newValues) {
        values = newValues;
        if (onChanged != null) onChanged(newValues);
      },
    );
  }

  @override
  Widget display({bool onlyValue = false}) {
    final chips = values.map((v) => Chip(
      label: Text(v, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
      backgroundColor: Colors.blue[50],
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    )).toList();

    if (onlyValue) {
      return Wrap(spacing: 4, runSpacing: 4, children: chips);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: chips),
        ],
      ),
    );
  }
}

class _MultiSelectEditor extends StatefulWidget {
  final String label;
  final List<String> allowed;
  final List<String> initialValues;
  final int limit;
  final Function(List<String>) onChanged;

  const _MultiSelectEditor({
    super.key,
    required this.label,
    required this.allowed,
    required this.initialValues,
    required this.limit,
    required this.onChanged,
  });

  @override
  State<_MultiSelectEditor> createState() => _MultiSelectEditorState();
}

class _MultiSelectEditorState extends State<_MultiSelectEditor> {
  late List<String> _currentValues;

  @override
  void initState() {
    super.initState();
    _currentValues = List<String>.from(widget.initialValues);
  }

  void _handleSelect(String value, bool selected) {
    setState(() {
      if (selected) {
        if (_currentValues.length < widget.limit) {
          _currentValues.add(value);
        } else {
          // Limit reached, swap last one or ignore? RN logic swaps last one.
          _currentValues.removeLast();
          _currentValues.add(value);
        }
      } else {
        _currentValues.remove(value);
      }
    });
    widget.onChanged(_currentValues);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: widget.allowed.map((option) {
              final isSelected = _currentValues.contains(option);
              return FilterChip(
                label: Text(option),
                selected: isSelected,
                onSelected: (selected) => _handleSelect(option, selected),
                selectedColor: Colors.blue[100],
                checkmarkColor: Colors.blue,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
