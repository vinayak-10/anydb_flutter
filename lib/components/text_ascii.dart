import 'package:flutter/material.dart';
import '../core/gen_interface.dart';

class TextAscii extends GenInterface {
  String name = "";
  String id = "";
  String value = "";
  bool searchable = false;
  bool timed = false;
  bool multiline = false;
  int lines = 1;
  int maxsize = 100;

  @override
  String getType() => "text";

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    name = jsonObj['name']?.toString() ?? "";
    id = jsonObj['id']?.toString() ?? "";
    value = jsonObj['defaultValue']?.toString() ?? "";
    searchable = jsonObj['searchable'] ?? false;
    timed = jsonObj['timed'] ?? false;
    multiline = jsonObj['multiline'] ?? false;
    lines = jsonObj['lines'] is int ? jsonObj['lines'] : 1;
    maxsize = jsonObj['maxsize'] is int ? jsonObj['maxsize'] : 100;
  }

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
  List<bool> match(String val) {
    if (searchable) {
      String c1 = value.toLowerCase();
      String c2 = val.toLowerCase();
      if (c1 == c2) return [true, true];
      if (c1.contains(c2)) return [true, false];
    }
    return [false, false];
  }

  @override
  Widget editor({required Key key, Function? onChanged}) {
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
        if (onChanged != null) onChanged(txt);
      },
    );
  }

  @override
  Widget display({bool onlyValue = false}) {
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
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: widget.multiline ? null : widget.lines,
        maxLength: widget.maxsize,
        decoration: InputDecoration(
          labelText: widget.label,
          filled: true,
          fillColor: Colors.grey[100],
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
