import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/gen_interface.dart';
import '../core/settings_provider.dart';

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
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => "number";

  @override
  String getName() => name;

  @override
  String getId() => id;

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    oSchema = jsonObj;
    this.repoIntf = repoIntf;
    final Map<String, dynamic> jo = jsonObj;
    name = jo['name']?.toString() ?? "";
    id = jo['id']?.toString() ?? "";
    value = jo['defaultValue']?.toString() ?? "";
    constraint = jo['constraint'];
    observers = jo['observers'] is List ? jo['observers'] : [];
    searchable = jo['searchable'] ?? false;

    final fmt = jo['format'];
    if (fmt is Map) {
      final Map<String, dynamic> fmtMap = Map<String, dynamic>.from(fmt);
      format["prefix"] = fmtMap['prefix']?.toString() ?? "";
      format["suffix"] = fmtMap['suffix']?.toString() ?? "";
    } else if (fmt is String) {
      rawFormat = fmt;
    }

    final acc = jo['access'];
    if (acc is Map) {
      final Map<String, dynamic> accMap = Map<String, dynamic>.from(acc);
      access["confirmWrite"] = accMap['confirmWrite'] ?? false;
      access["readOnly"] = accMap['readOnly'] ?? false;
    }
  }

  @override
  GenInterface clone() {
    final c = TextNumber();
    c.init(oSchema!, repoIntf);
    c.populate(fetch());
    return c;
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
  List<bool> match(String val, {bool exact = false}) {
    if (searchable) {
      if (exact) {
        if (value == val) return [true, true];
      } else {
        if (value == val) return [true, true];
        if (value.contains(val)) return [true, false];
      }
    }
    return [false, false];
  }

  @override
  Map<String, dynamic> validate() {
    bool valid = true;
    List<String> failedConstraints = [];

    if (constraint is Map) {
      final Map<String, dynamic> cMap = Map<String, dynamic>.from(constraint);
      cMap.forEach((c, cVal) {
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
    }

    return {'name': name, 'valid': valid, 'constraint': failedConstraints};
  }

  @override
  String getValue() => value;

  @override
  List<dynamic> getObservers() => observers;

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
    return _TextNumberEditor(
      key: key,
      label: name,
      initialValue: value,
      prefix: format["prefix"]!,
      suffix: format["suffix"]!,
      readOnly: access["readOnly"]!,
      confirmWrite: access["confirmWrite"]!,
      autoFocus: autoFocus ?? false,
      onChanged: (txt) {
        value = txt;
        onChanged(txt);
        if (cbNotifyParent != null) {
          cbNotifyParent(this, {name: txt}, observers);
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
  final bool autoFocus;
  final Function(String) onChanged;

  const _TextNumberEditor({
    super.key,
    required this.label,
    required this.initialValue,
    required this.prefix,
    required this.suffix,
    required this.readOnly,
    required this.confirmWrite,
    required this.autoFocus,
    required this.onChanged,
  });

  @override
  State<_TextNumberEditor> createState() => _TextNumberEditorState();
}

class _TextNumberEditorState extends State<_TextNumberEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _isLocked = widget.confirmWrite;
  }

  @override
  void didUpdateWidget(_TextNumberEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return ListTile(
        title: Text(widget.label),
        subtitle: Text(
          "${widget.prefix}${widget.initialValue}${widget.suffix}",
        ),
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

    return Consumer(
      builder: (context, ref, child) {
        final settings = ref.watch(settingsProvider);
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: widget.autoFocus,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: settings.inputFontSize),
            decoration: InputDecoration(
              labelText: widget.label,
              prefixText: widget.prefix,
              suffixText: widget.suffix,
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onChanged,
          ),
        );
      },
    );
  }
}
