import 'package:flutter/material.dart';
import '../core/gen_interface.dart';
import '../core/widget_factory.dart';
import '../components/meta_default.dart';

class ElementModel {
  String key = '';
  List<GenInterface> components = [];
  Map<String, dynamic>? originalSchema;
  dynamic intf;

  ElementModel();

  void init(List<dynamic> schema, dynamic repoIntf) {
    intf = repoIntf;
    originalSchema = {'elements': schema};
    components = [];

    for (var s in schema) {
      final c = WidgetFactory.get(s['type']);
      if (c != null) {
        c.init(s, repoIntf);
        components.add(c);
      }
    }

    // Add default Meta component
    final m = MetaDefault();
    m.init(null, repoIntf);
    components.add(m);
  }

  ElementModel clone() {
    final ce = ElementModel();
    ce.init(originalSchema?['elements'] ?? [], intf);
    ce.key = key;
    ce.populate(fetch());
    return ce;
  }

  void populate(Map<String, dynamic> dbJson) {
    key = dbJson.keys.first;
    final data = dbJson.values.first;
    for (var component in components) {
      component.populate(data);
    }
  }

  Map<String, dynamic> fetch() {
    final Map<String, dynamic> val = {};
    final Map<String, dynamic> componentData = {};
    
    for (var component in components) {
      final cVal = component.fetch();
      componentData.addAll(cVal);
    }
    
    val[key] = componentData;
    return val;
  }

  Map<String, dynamic> validate() {
    for (var component in components) {
      final v = component.validate();
      if (v['valid'] == false) {
        return v;
      }
    }
    return {'name': key, 'valid': true, 'constraint': []};
  }

  List<bool> match(String val, {bool exact = false}) {
    for (var component in components) {
      final m = component.match(val, exact: exact);
      if (m[0]) return m;
    }
    return [false, false];
  }

  List<Widget> getEditors({required Function onChanged}) {
    return components.map((c) => c.editor(
      key: ValueKey("editor_${c.getType()}_${c.getName()}"),
      onChanged: (val) => onChanged(),
    )).toList();
  }

  List<Widget> getDisplays({bool onlyValue = false}) {
    return components.map((c) => c.display(onlyValue: onlyValue)).toList();
  }
}
