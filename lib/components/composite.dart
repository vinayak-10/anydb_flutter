import 'package:flutter/material.dart';
import '../core/gen_interface.dart';
import '../core/widget_factory.dart';

class Composite extends GenInterface {
  String name = "";
  String id = "";
  List<GenInterface> components = [];
  bool searchable = false;
  List<List<GenInterface>> editGroups = [];
  List<List<GenInterface>> displayGroups = [];
  
  @override
  String getType() => "composite";

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    name = jsonObj['name'] ?? "";
    id = jsonObj['id']?.toString() ?? "";
    searchable = jsonObj['searchable'] ?? false;

    final elements = jsonObj['elements'] as List<dynamic>?;
    components = [];
    if (elements != null) {
      for (var s in elements) {
        final c = WidgetFactory.get(s['type']);
        if (c != null) {
          c.init(s, repoIntf);
          components.add(c);
        }
      }
    }

    final displayGroupSchema = jsonObj['displayGroup'] as List<dynamic>?;
    if (displayGroupSchema != null) {
      editGroups = displayGroups = _groupComponents(displayGroupSchema);
    } else {
      editGroups = displayGroups = [components];
    }
  }

  List<List<GenInterface>> _groupComponents(List<dynamic> groupSchema) {
    List<List<GenInterface>> result = [];
    for (var row in groupSchema) {
      List<GenInterface> group = [];
      for (var name in row) {
        final c = _getComponentByName(name.toString());
        if (c != null) group.add(c);
      }
      result.add(group);
    }
    return result;
  }

  GenInterface? _getComponentByName(String n) {
    try {
      return components.firstWhere((c) => c.getName() == n);
    } catch (_) {
      return null;
    }
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      final data = jsonDb[name] as Map<String, dynamic>;
      for (var key in data.keys) {
        for (var component in components) {
          component.populate({key: data[key]});
        }
      }
      
      // Trigger observers logic would go here
    }
  }

  @override
  Map<String, dynamic> fetch() {
    final Map<String, dynamic> rows = {};
    for (var component in components) {
      final cval = component.fetch();
      rows.addAll(cval);
    }
    return {name: rows};
  }

  @override
  Map<String, dynamic> validate() {
    for (var component in components) {
      final v = component.validate();
      if (v['valid'] == false) return v;
    }
    return {'name': name, 'valid': true, 'constraint': []};
  }

  @override
  List<bool> match(String val) {
    if (searchable) {
      for (var component in components) {
        final m = component.match(val);
        if (m[0]) return m;
      }
    }
    return [false, false];
  }

  @override
  Widget editor({required Key key, Function? onChanged}) {
    return _CompositeEditor(
      key: key,
      label: name,
      groups: editGroups,
      onChanged: () {
        if (onChanged != null) onChanged();
      },
    );
  }

  @override
  Widget display({bool onlyValue = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!onlyValue) Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        ...displayGroups.map((group) => Wrap(
          spacing: 10,
          children: group.map((c) => c.display(onlyValue: false)).toList(),
        )),
      ],
    );
  }
}

class _CompositeEditor extends StatefulWidget {
  final String label;
  final List<List<GenInterface>> groups;
  final VoidCallback onChanged;

  const _CompositeEditor({
    super.key,
    required this.label,
    required this.groups,
    required this.onChanged,
  });

  @override
  State<_CompositeEditor> createState() => _CompositeEditorState();
}

class _CompositeEditorState extends State<_CompositeEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...widget.groups.map((group) => Column(
          children: [
            ...group.map((c) => c.editor(
              key: ValueKey(c.getName()),
              onChanged: (val) => widget.onChanged(),
            )),
            const Divider(color: Colors.green, thickness: 1),
          ],
        )),
      ],
    );
  }
}
