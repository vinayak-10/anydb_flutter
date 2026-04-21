import 'package:flutter/material.dart';
import '../core/gen_interface.dart';

class ListHeader extends GenInterface {
  String name = '';
  String titleStr = '';
  String id = '';
  List<dynamic>? title;
  List<dynamic>? elements;
  List<dynamic>? actions;
  dynamic repoIntf;
  List<dynamic> dbSchema = [];
  Map<String, dynamic>? oSchema;

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    oSchema = jsonObj;
    name = jsonObj['name'] ?? '';
    titleStr = jsonObj['title']?.toString() ?? '';
    id = jsonObj['id']?.toString() ?? '';
    title = jsonObj['title'] as List<dynamic>?;
    elements = jsonObj['elements'] as List<dynamic>?;
    actions = jsonObj['actions'] as List<dynamic>?;
    this.repoIntf = repoIntf;
  }

  @override
  GenInterface clone() {
    final c = ListHeader();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  void setDbSchema(List<dynamic> schema) {
    dbSchema = schema;
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {}

  @override
  Map<String, dynamic> fetch() => {};

  @override
  List<bool> match(String val, {bool exact = false}) => [false, false];

  @override
  String getName() => name;

  @override
  String getType() => 'list-header';

  @override
  Widget editor({required Key key, required Function(dynamic) onChanged, Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent, dynamic frefs, int? index, bool? autoFocus, bool? refresh}) {
    return Text("Edit $name", key: key);
  }

  @override
  Widget display({bool onlyValue = false, List<dynamic>? displayComponent, VoidCallback? onChanged}) {
    return const SizedBox.shrink();
  }

  List<List<Widget>> displayHeader(BuildContext context, {required String headerType, required List<GenInterface> allComponents, VoidCallback? onChanged}) {
    List<dynamic>? config;
    if (headerType == 'title') {
      config = title;
    } else if (headerType == 'elements') {
      config = elements;
    } else if (headerType == 'actions') {
      config = actions;
    }

    if (config == null || config.isEmpty) {
      return [];
    }

    return _getListComponents(config, allComponents, onChanged);
  }

  List<List<Widget>> _getListComponents(List<dynamic> config, List<GenInterface> allComponents, VoidCallback? onChanged) {
    List<List<Widget>> components = [];
    for (var v in config) {
      if (v['type'] == 'values') {
        final vc = _getValuesComponents(v['value'] as List<dynamic>, allComponents);
        if (vc.isNotEmpty) components.add(vc);
      } else if (v['type'] == 'function') {
        final fc = _getFunctionComponents(v['value'] as List<dynamic>, allComponents, onChanged);
        if (fc.isNotEmpty) components.add(fc);
      }
    }
    return components;
  }

  List<Widget> _getValuesComponents(List<dynamic> values, List<GenInterface> allComponents) {
    List<Widget> displayHeaders = [];
    for (var componentPath in values) {
      if (componentPath is! List) {
        continue;
      }
      final component = _getComponent(componentPath[0], allComponents);
      if (component != null) {
        final displayComponent = componentPath.sublist(1);
        displayHeaders.add(component.display(
          onlyValue: true,
          displayComponent: displayComponent.isEmpty ? null : displayComponent,
        ));
      }
    }

    return displayHeaders;
  }

  List<Widget> _getFunctionComponents(List<dynamic> values, List<GenInterface> allComponents, VoidCallback? onChanged) {
    List<Widget> contentObjs = [];
    for (var content in values) {
      final funcContents = content['content'] as List<dynamic>? ?? [];
      for (var baseContent in funcContents) {
        if (baseContent['operation'] == 'invoke') {
          final on = baseContent['on'] as List<dynamic>?;
          if (on != null && on.isNotEmpty) {
             final component = _getNestedComponent(on.cast<String>(), allComponents);
             if (component != null) {
               final invoker = component.invoke(
                 method: baseContent['what'],
                 parameters: baseContent['parameters'] ?? {},
                 onChanged: onChanged,
               );
               if (invoker != null) {
                 contentObjs.add(invoker);
               }
             }
          }
        }
      }
    }

    return contentObjs;
  }

  GenInterface? _getComponent(String key, List<GenInterface> list) {
    for (var c in list) {
      if (c.getName() == key) {
        return c;
      }
    }
    return null;
  }

  GenInterface? _getNestedComponent(List<String> keys, List<GenInterface> list) {
    GenInterface? parent = _getComponent(keys[0], list);
    if (parent == null) {
      return null;
    }

    for (int i = 1; i < keys.length; i++) {
      parent = parent?.getComponent(keys[i]);
    }
    return parent;
  }
}
