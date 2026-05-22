import 'package:flutter/material.dart';
import '../core/gen_interface.dart';
import '../core/widget_factory.dart';

class MultiValue extends GenInterface {
  String name = '';
  String id = '';
  List<dynamic> componentsSchema = [];
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;
  List<List<GenInterface>> componentsArray = [];
  bool searchable = false;

  @override
  String getType() => 'multi-value';

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
    componentsSchema = jsonObj['elements'] ?? [];
    searchable = jsonObj['searchable'] ?? false;
  }

  @override
  GenInterface clone() {
    final c = MultiValue();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  @override
  Map<String, dynamic> fetch() {
    List<Map<String, dynamic>> rows = [];
    for (var components in componentsArray) {
      Map<String, dynamic> row = {};
      for (var component in components) {
        final cval = component.fetch();
        row[cval.keys.first] = cval.values.first;
      }
      rows.add(row);
    }
    return {name: rows};
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey(name)) {
      final List<dynamic> dataRows = jsonDb[name] ?? [];
      componentsArray.clear();
      for (var e in dataRows) {
        List<GenInterface> components = [];
        for (var s in componentsSchema) {
          final c = WidgetFactory.get(s['type']);
          if (c != null) {
            c.init(s, repoIntf);
            components.add(c);
          }
        }
        for (var component in components) {
          component.populate(e);
        }
        componentsArray.add(components);
      }
    }
  }

  @override
  List<bool> match(String val, {bool exact = false}) {
    if (searchable) {
      for (var components in componentsArray) {
        for (var component in components) {
          if (component.match(val, exact: exact)[0]) return [true, true];
        }
      }
    }
    return [false, false];
  }

  @override
  Widget editor({required Key key, required Function(dynamic) onChanged, Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent, dynamic frefs, int? index, bool? autoFocus, bool? refresh}) {
    return _MultiValueEditor(
      key: key,
      multiValue: this,
      onChanged: onChanged,
      cbNotifyParent: cbNotifyParent,
    );
  }

  @override
  Widget display({bool onlyValue = false, List<dynamic>? displayComponent, VoidCallback? onChanged}) {
    return _MultiValueDisplay(multiValue: this, onChanged: onChanged);
  }
}

class _MultiValueEditor extends StatefulWidget {
  final MultiValue multiValue;
  final Function(dynamic) onChanged;
  final Function(GenInterface, Map<String, dynamic>, List<dynamic>)? cbNotifyParent;

  const _MultiValueEditor({super.key, required this.multiValue, required this.onChanged, this.cbNotifyParent});

  @override
  State<_MultiValueEditor> createState() => _MultiValueEditorState();
}

class _MultiValueEditorState extends State<_MultiValueEditor> {
  void _addRow() {
    List<GenInterface> newComponents = [];
    for (var s in widget.multiValue.componentsSchema) {
      final c = WidgetFactory.get(s['type']);
      if (c != null) {
        c.init(s, widget.multiValue.repoIntf);
        newComponents.add(c);
      }
    }
    setState(() {
      widget.multiValue.componentsArray.insert(0, newComponents);
      widget.onChanged(null);
    });
  }

  void _deleteRow(int index) {
    setState(() {
      widget.multiValue.componentsArray.removeAt(index);
      widget.onChanged(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: ExpansionTile(
        title: Text(widget.multiValue.name),
        subtitle: Text("Total ${widget.multiValue.componentsArray.length} entries"),
        children: [
          TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add),
            label: const Text("Add More"),
          ),
          ...widget.multiValue.componentsArray.asMap().entries.map((entry) {
            int idx = entry.key;
            List<GenInterface> components = entry.value;
            return Dismissible(
              key: ValueKey("mv_dismiss_${idx}_${components.hashCode}"),
              background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) => _deleteRow(idx),
              child: ListTile(
                title: Column(
                  children: components.map((c) => c.editor(
                    key: ValueKey("mv_edit_${c.getName()}_$idx"),
                    onChanged: (val) {
                      widget.onChanged(val);
                    },
                    cbNotifyParent: widget.cbNotifyParent,
                  )).toList(),
                ),
                trailing: const Icon(Icons.drag_handle, color: Colors.grey),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MultiValueDisplay extends StatelessWidget {
  final MultiValue multiValue;
  final VoidCallback? onChanged;

  const _MultiValueDisplay({required this.multiValue, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 2,
      child: ExpansionTile(
        title: Text(multiValue.name),
        subtitle: Text("Total ${multiValue.componentsArray.length} entries"),
        children: multiValue.componentsArray.map((components) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: components.map((c) => Expanded(child: c.display(onlyValue: true, onChanged: onChanged))).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
