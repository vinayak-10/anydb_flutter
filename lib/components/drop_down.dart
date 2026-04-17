import 'package:flutter/material.dart';
import '../core/gen_interface.dart';

class DropDown extends GenInterface {
  String name = "";
  String id = "";
  List<dynamic> values = [];
  bool searchable = false;
  Map<String, dynamic> source = {
    'intf': null,
    'initialized': false,
    'initFn': null,
    'data': {'displayKeys': [], 'store': []}
  };

  @override
  String getType() => "dropdown";

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    name = jsonObj['name'] ?? "";
    id = jsonObj['id']?.toString() ?? "";
    values = jsonObj['defaultValue'] is List ? jsonObj['defaultValue'] : [jsonObj['defaultValue']];
    searchable = jsonObj['searchable'] ?? false;

    if (jsonObj.containsKey('source')) {
      final sourceSchema = jsonObj['source'];
      if (sourceSchema.containsKey('displayKeys')) {
        source['data']['displayKeys'] = sourceSchema['displayKeys'];
      }
      // Placeholder for repoIntf reference
    }
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      final val = jsonDb[name];
      values = val is List ? val : [val];
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: values};
  }

  @override
  Widget editor({required Key key, Function? onChanged}) {
    return _DropDownEditor(
      key: key,
      label: name,
      initialValue: values.isNotEmpty ? values.first : null,
      items: allowedValues(), // For now, we'll use a simple list or dummy data
      onChanged: (val) {
        values = [val];
        if (onChanged != null) onChanged(val);
      },
    );
  }

  List<String> allowedValues() {
    // This should ideally come from the source reference
    return ["Option 1", "Option 2", "Option 3"]; 
  }

  @override
  Widget display({bool onlyValue = false}) {
    final displayValue = values.join(", ");
    if (onlyValue) return Text(displayValue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text("$name: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(displayValue),
        ],
      ),
    );
  }
}

class _DropDownEditor extends StatefulWidget {
  final String label;
  final dynamic initialValue;
  final List<String> items;
  final Function(dynamic) onChanged;

  const _DropDownEditor({
    super.key,
    required this.label,
    required this.initialValue,
    required this.items,
    required this.onChanged,
  });

  @override
  State<_DropDownEditor> createState() => _DropDownEditorState();
}

class _DropDownEditorState extends State<_DropDownEditor> {
  dynamic _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: DropdownButtonFormField<String>(
        initialValue: widget.items.contains(_currentValue) ? _currentValue : null,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.grey[100],
        ),
        items: widget.items.map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value),
          );
        }).toList(),
        onChanged: (val) {
          setState(() => _currentValue = val);
          widget.onChanged(val);
        },
      ),
    );
  }
}
