import 'package:flutter/material.dart';
import '../core/gen_interface.dart';

class TextNumber extends GenInterface {
  String name = "";
  String id = "";
  String value = "";
  dynamic constraint;
  List<dynamic> observers = [];
  bool searchable = false;
  Map<String, String> format = {"prefix": "", "suffix": ""};
  String? rawFormat;
  Map<String, bool> access = {"confirmWrite": false, "readOnly": false};

  @override
  String getType() => "number";

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    name = jsonObj['name']?.toString() ?? "";
    id = jsonObj['id']?.toString() ?? "";
    value = jsonObj['defaultValue']?.toString() ?? "";
    constraint = jsonObj['constraint'];
    observers = jsonObj['observers'] is List ? jsonObj['observers'] : [];
    searchable = jsonObj['searchable'] ?? false;

    final fmt = jsonObj['format'];
    if (fmt is Map) {
      format["prefix"] = fmt['prefix']?.toString() ?? "";
      format["suffix"] = fmt['suffix']?.toString() ?? "";
    } else if (fmt is String) {
      rawFormat = fmt;
    }

    final acc = jsonObj['access'];
    if (acc is Map) {
      access["confirmWrite"] = acc['confirmWrite'] ?? false;
      access["readOnly"] = acc['readOnly'] ?? false;
    }
  }


  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      value = jsonDb[name]?.toString() ?? "";
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: value == '' ? 0 : int.tryParse(value) ?? 0};
  }

  @override
  List<bool> match(String val) {
    if (searchable) {
      if (value == val) return [true, true];
      if (value.contains(val)) return [true, false];
    }
    return [false, false];
  }

  @override
  Map<String, dynamic> validate() {
    bool valid = true;
    List<String> failedConstraints = [];

    constraint.forEach((c, cVal) {
      bool pass = true;
      switch (c) {
        case "non-null":
          pass = (cVal == true && value.isNotEmpty);
          break;
        case "maxsize":
          pass = value.length <= (cVal as int);
          break;
        case "maxvalue":
          final intVal = int.tryParse(value);
          pass = intVal != null && intVal <= (cVal as int);
          break;
        case "+":
          final intVal = int.tryParse(value);
          pass = intVal != null && intVal >= 0;
          break;
        case "-":
          final intVal = int.tryParse(value);
          pass = intVal != null && intVal < 0;
          break;
      }
      if (!pass) {
        valid = false;
        failedConstraints.add(c);
      }
    });

    return {'name': name, 'valid': valid, 'constraint': failedConstraints};
  }

  @override
  Widget editor({required Key key, Function? onChanged}) {
    return _TextNumberEditor(
      key: key,
      label: name,
      initialValue: value,
      prefix: format["prefix"]!,
      suffix: format["suffix"]!,
      readOnly: access["readOnly"]!,
      confirmWrite: access["confirmWrite"]!,
      onChanged: (txt) {
        value = txt;
        if (onChanged != null) onChanged(txt);
      },
    );
  }

  @override
  Widget display({bool onlyValue = false}) {
    final displayValue = "${format['prefix']}$value${format['suffix']}";
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

class _TextNumberEditor extends StatefulWidget {
  final String label;
  final String initialValue;
  final String prefix;
  final String suffix;
  final bool readOnly;
  final bool confirmWrite;
  final Function(String) onChanged;

  const _TextNumberEditor({
    super.key,
    required this.label,
    required this.initialValue,
    required this.prefix,
    required this.suffix,
    required this.readOnly,
    required this.confirmWrite,
    required this.onChanged,
  });

  @override
  State<_TextNumberEditor> createState() => _TextNumberEditorState();
}

class _TextNumberEditorState extends State<_TextNumberEditor> {
  late TextEditingController _controller;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _isLocked = widget.confirmWrite;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return ListTile(
        title: Text(widget.label),
        subtitle: Text("${widget.prefix}${widget.initialValue}${widget.suffix}"),
      );
    }

    if (_isLocked) {
      return ListTile(
        title: Text(widget.label),
        subtitle: Text("${widget.prefix}${_controller.text}${widget.suffix}"),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => setState(() => _isLocked = false),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixText: widget.prefix,
          suffixText: widget.suffix,
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
