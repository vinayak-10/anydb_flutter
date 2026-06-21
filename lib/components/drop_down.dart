import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/gen_interface.dart';
import '../core/settings_provider.dart';

class DropDown extends GenInterface {
  String name = "";
  String id = "";
  List<dynamic> values = [];
  bool searchable = false;
  Map<String, dynamic> source = {
    'intf': null,
    'initialized': false,
    'initFn': null,
    'data': {'displayKeys': [], 'store': []},
  };
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => "dropdown";

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

    final rawDefault = jo['defaultValue'];
    if (rawDefault is List) {
      values = rawDefault;
    } else if (rawDefault != null) {
      values = [rawDefault];
    } else {
      values = [];
    }

    searchable = jo['searchable'] ?? false;

    if (jo.containsKey('source')) {
      final sourceSchema = jo['source'];
      if (sourceSchema is Map && sourceSchema.containsKey('displayKeys')) {
        source['data']['displayKeys'] = sourceSchema['displayKeys'];
      }
    }
  }

  @override
  GenInterface clone() {
    final c = DropDown();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
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
  Widget editor({
    required Key key,
    required Function(dynamic) onChanged,
    Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent,
    dynamic frefs,
    int? index,
    bool? autoFocus,
    bool? refresh,
  }) {
    return _DropDownEditor(
      key: key,
      label: name,
      initialValue: values.isNotEmpty ? values.first : null,
      items: allowedValues(), // For now, we'll use a simple list or dummy data
      onChanged: (val) {
        values = [val];
        onChanged(val);
      },
    );
  }

  List<String> allowedValues() {
    // This should ideally come from the source reference
    return ["Option 1", "Option 2", "Option 3"];
  }

  @override
  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
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
    return Consumer(
      builder: (context, ref, child) {
        final settings = ref.watch(settingsProvider);
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownButtonFormField<String>(
            initialValue: widget.items.contains(_currentValue)
                ? _currentValue
                : null,
            style: TextStyle(
              fontSize: settings.inputFontSize,
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey[100],
            ),
            items: widget.items.map((String value) {
              return DropdownMenuItem<String>(value: value, child: Text(value));
            }).toList(),
            onChanged: (val) {
              setState(() => _currentValue = val);
              widget.onChanged(val);
            },
          ),
        );
      },
    );
  }
}
