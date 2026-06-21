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
  List<dynamic> observers = [];
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => "multi-select";

  @override
  String getName() => name;

  @override
  String getId() => id;

  @override
  void init(dynamic jsonObj, dynamic repoIntf) {
    if (jsonObj is! Map) return;
    oSchema = Map<String, dynamic>.from(jsonObj);
    this.repoIntf = repoIntf;
    final Map<String, dynamic> jo = Map<String, dynamic>.from(jsonObj);

    name = jo['name']?.toString() ?? "";
    id = jo['id']?.toString() ?? "";
    allowed = List<String>.from(jo['allowedValues'] ?? []);

    final rawDefault = jo['defaultValue'];
    if (rawDefault is List) {
      values = List<String>.from(rawDefault);
    } else if (rawDefault is String && rawDefault.isNotEmpty) {
      values = rawDefault.split(',').map((e) => e.trim()).toList();
    } else {
      values = List<String>.from(jo['defaultValues'] ?? []);
    }

    final l = jo['limit'];
    limit = l is int
        ? l
        : (int.tryParse(l?.toString() ?? "") ?? allowed.length);

    final m = jo['min'];
    min = m is int ? m : (int.tryParse(m?.toString() ?? "") ?? 0);

    searchable = jo['searchable'] ?? false;
    observers = jo['observers'] is List ? jo['observers'] : [];
  }

  @override
  GenInterface clone() {
    final c = MultiSelect();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  @override
  List<dynamic> getObservers() => observers;

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
  List<bool> match(String val, {bool exact = false}) {
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
    if (values.length < min) {
      return {
        'name': name,
        'valid': false,
        'constraint': "Please select at least $min $name(s).",
      };
    }
    return {'name': name, 'valid': true, 'constraint': ''};
  }

  @override
  Widget editor({
    required Key key,
    required Function(dynamic) onChanged,
    Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent,
    dynamic frefs,
    int? index,
    bool? autoFocus,
    bool? refresh,
  }) {
    return _MultiSelectEditor(
      key: key,
      label: name,
      allowed: allowed,
      initialValues: values,
      limit: limit,
      onChanged: (newValues) {
        values = newValues;
        onChanged(newValues);
        if (cbNotifyParent != null) {
          cbNotifyParent(this, {name: newValues}, observers);
        }
      },
    );
  }

  @override
  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
    final chips = values
        .map(
          (v) => Chip(
            label: Text(
              v,
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            backgroundColor: Colors.blue[50],
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        )
        .toList();

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
