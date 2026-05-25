import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/gen_interface.dart';
import '../core/settings_provider.dart';

class TextAscii extends GenInterface {
  String name = "";
  String id = "";
  String value = "";
  bool searchable = false;
  bool timed = false;
  bool multiline = false;
  int lines = 1;
  int maxsize = 100;
  List<dynamic> observers = [];
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => "text";

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
    searchable = jo['searchable'] ?? false;
    timed = jo['timed'] ?? false;
    multiline = jo['multiline'] ?? false;
    lines = jo['lines'] is int ? jo['lines'] : 1;
    maxsize = jo['maxsize'] is int ? jo['maxsize'] : 100;
    observers = jo['observers'] is List ? jo['observers'] : [];
  }

  @override
  GenInterface clone() {
    final c = TextAscii();
    c.init(oSchema!, repoIntf);
    c.populate(fetch());
    return c;
  }

  @override
  List<dynamic> getObservers() => observers;

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      value = jsonDb[name].toString();
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: value};
  }

  @override
  List<bool> match(String val, {bool exact = false}) {
    if (searchable) {
      String c1 = value.toLowerCase();
      String c2 = val.toLowerCase();
      if (exact) {
        if (c1 == c2) return [true, true];
      } else {
        if (c1 == c2) return [true, true];
        if (c1.contains(c2)) return [true, false];
      }
    }
    return [false, false];
  }

  @override
  Widget editor({
    required Key key, 
    required Function(dynamic) onChanged, 
    Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent,
    dynamic frefs, 
    int? index, 
    bool? autoFocus, 
    bool? refresh
  }) {
    return _TextAsciiEditor(
      key: key,
      label: name,
      initialValue: value,
      multiline: multiline,
      lines: lines,
      maxsize: maxsize,
      timed: timed,
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
  Widget display({bool onlyValue = false, List<dynamic>? displayComponent, VoidCallback? onChanged}) {
    if (onlyValue) return Text(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$name: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TextAsciiEditor extends StatefulWidget {
  final String label;
  final String initialValue;
  final bool multiline;
  final int lines;
  final int maxsize;
  final bool timed;
  final Function(String) onChanged;

  const _TextAsciiEditor({
    super.key,
    required this.label,
    required this.initialValue,
    required this.multiline,
    required this.lines,
    required this.maxsize,
    required this.timed,
    required this.onChanged,
  });

  @override
  State<_TextAsciiEditor> createState() => _TextAsciiEditorState();
}

class _TextAsciiEditorState extends State<_TextAsciiEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_TextAsciiEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && widget.timed) {
      final now = DateTime.now();
      // Simple date formatting without external library for now
      final dateStr = "${now.day}/${now.month}/${now.year} - ";
      if (!_controller.text.contains(dateStr)) {
        final newValue = "${_controller.text}\n$dateStr";
        _controller.text = newValue;
        widget.onChanged(newValue);
      }
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
    return Consumer(
      builder: (context, ref, child) {
        final settings = ref.watch(settingsProvider);
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: widget.multiline ? null : widget.lines,
            maxLength: widget.maxsize,
            style: TextStyle(fontSize: settings.inputFontSize),
            decoration: InputDecoration(
              labelText: widget.label,
              filled: true,
              fillColor: Colors.grey[100],
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onChanged,
          ),
        );
      },
    );
  }
}
