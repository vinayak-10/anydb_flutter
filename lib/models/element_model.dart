import 'package:flutter/material.dart';
import '../core/gen_interface.dart';
import '../core/widget_factory.dart';
import '../components/meta_default.dart';

class ElementModel {
  String key = '';
  List<GenInterface> _components = [];
  Map<String, dynamic>? originalSchema;
  dynamic intf;

  bool _isHydrated = true;
  Map<String, dynamic>? _lazyData;

  ElementModel();

  ElementModel.lazy(List<dynamic> schema, dynamic repoIntf, Map<String, dynamic> dbJson) {
    originalSchema = {'elements': schema};
    intf = repoIntf;
    key = dbJson.keys.first;
    _lazyData = dbJson;
    _isHydrated = false;
  }

  void ensureHydrated() {
    if (!_isHydrated && _lazyData != null) {
      _isHydrated = true;
      final schema = originalSchema?['elements'] as List<dynamic>? ?? [];
      _components = [];

      for (var s in schema) {
        final c = WidgetFactory.get(s['type']);
        if (c != null) {
          c.init(s, intf);
          _components.add(c);
        }
      }

      // Add default Meta component
      final m = MetaDefault();
      m.init(null, intf);
      _components.add(m);

      final data = _lazyData!.values.first;
      for (var component in _components) {
        component.populate(data);
      }
    }
  }

  List<GenInterface> get components {
    ensureHydrated();
    return _components;
  }

  set components(List<GenInterface> val) {
    _components = val;
  }

  void init(List<dynamic> schema, dynamic repoIntf) {
    intf = repoIntf;
    originalSchema = {'elements': schema};
    _components = [];
    _isHydrated = true;
    _lazyData = null;

    for (var s in schema) {
      final c = WidgetFactory.get(s['type']);
      if (c != null) {
        c.init(s, repoIntf);
        _components.add(c);
      }
    }

    // Add default Meta component
    final m = MetaDefault();
    m.init(null, repoIntf);
    _components.add(m);
  }

  ElementModel clone() {
    ensureHydrated();
    final ce = ElementModel();
    ce.init(originalSchema?['elements'] ?? [], intf);
    ce.key = key;
    ce.populate(fetch());
    return ce;
  }

  void populate(Map<String, dynamic> dbJson) {
    if (!_isHydrated) {
      key = dbJson.keys.first;
      _lazyData = dbJson;
      return;
    }
    key = dbJson.keys.first;
    final data = dbJson.values.first;
    for (var component in components) {
      component.populate(data);
    }
  }

  Map<String, dynamic> fetch() {
    if (!_isHydrated && _lazyData != null) {
      return _lazyData!;
    }
    ensureHydrated();
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
    ensureHydrated();
    for (var component in components) {
      final v = component.validate();
      if (v['valid'] == false) {
        return v;
      }
    }
    return {'name': key, 'valid': true, 'constraint': []};
  }

  List<bool> match(String val, {bool exact = false}) {
    ensureHydrated();
    for (var component in components) {
      final m = component.match(val, exact: exact);
      if (m[0]) return m;
    }
    return [false, false];
  }

  List<Widget> getEditors({required Function onChanged}) {
    ensureHydrated();
    return components.map((c) => c.editor(
      key: ValueKey("editor_${c.getType()}_${c.getName()}"),
      onChanged: (val) => onChanged(),
    )).toList();
  }

  List<Widget> getDisplays({bool onlyValue = false}) {
    ensureHydrated();
    return components.map((c) => c.display(onlyValue: onlyValue)).toList();
  }
}
