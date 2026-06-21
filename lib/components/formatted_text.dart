import 'package:flutter/material.dart';
import '../core/gen_interface.dart';

class FormattedText extends GenInterface {
  String name = '';
  String id = '';
  String extractedValue = '';
  String format = '';
  bool searchable = false;
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => 'formatted-text';

  @override
  String getName() => name;

  @override
  String getId() => id;

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    oSchema = jsonObj;
    this.repoIntf = repoIntf;
    name = jsonObj['name'] ?? '';
    id = jsonObj['id']?.toString() ?? '';
    extractedValue = jsonObj['defaultValue']?.toString() ?? '';
    format = jsonObj['format'] ?? '';
    searchable = jsonObj['searchable'] ?? false;
  }

  @override
  GenInterface clone() {
    final c = FormattedText();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      extractedValue = jsonDb[name]?.toString() ?? '';
    }
  }

  @override
  Map<String, dynamic> fetch() {
    return {name: extractedValue};
  }

  @override
  List<bool> match(String val, {bool exact = false}) {
    if (searchable) {
      String c1 = extractedValue.toLowerCase();
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
    bool? refresh,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextFormField(
        key: key,
        initialValue: extractedValue,
        decoration: InputDecoration(
          labelText: name,
          hintText: format,
          border: const OutlineInputBorder(),
        ),
        onChanged: (val) {
          extractedValue = val;
          onChanged(val);
        },
      ),
    );
  }

  @override
  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
    if (onlyValue) return Text(extractedValue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$name: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(extractedValue)),
        ],
      ),
    );
  }
}
