import 'package:flutter/material.dart';
import '../core/gen_interface.dart';

class MetaDisplay extends GenInterface {
  String name = '';
  String id = '';
  List<dynamic> fields = [];
  String separator = '';
  Map<String, dynamic> value = {};
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => 'meta';

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
    fields = jsonObj['fields'] ?? [];
    separator = jsonObj['separator'] ?? '';
    value = _getMeta(DateTime.now());
  }

  @override
  GenInterface clone() {
    final c = MetaDisplay();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  Map<String, dynamic> _getMeta(DateTime d) {
    Map<String, dynamic> val = {};
    for (var f in fields) {
      if (f == '_dd') {
        val[f] = d.day;
      } else if (f == '_mm') {
        val[f] = d.month; // Simplification, could format to short month
      } else if (f == '_yy') {
        val[f] = d.year;
      } else {
        val[f] = 1; // Fallback for counters like _counter.add.dd
      }
    }
    return val;
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    // Meta doesn't usually populate from DB in the same way, but it could.
  }

  @override
  Map<String, dynamic> fetch() {
    return {};
  }

  String _getValueString() {
    String valStr = "";
    for (var f in fields) {
      if (value.containsKey(f)) {
        valStr += value[f].toString();
      }
      valStr += separator;
    }
    return valStr;
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
    return display(onlyValue: false);
  }

  @override
  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
    final valStr = _getValueString();
    if (onlyValue) {
      return Text(valStr);
    }
    return Row(
      children: [
        Text("$name "),
        Text(valStr, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
