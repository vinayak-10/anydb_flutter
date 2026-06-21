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
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => "composite";

  @override
  String getName() => name;

  @override
  String getId() => id;

  @override
  void init(Map<String, dynamic> jsonObj, dynamic repoIntf) {
    oSchema = jsonObj;
    this.repoIntf = repoIntf;
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

  @override
  GenInterface clone() {
    final c = Composite();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
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

  @override
  GenInterface getComponent(String key) {
    final c = _getComponentByName(key);
    return c ?? this;
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
      for (var component in components) {
        component.populate(data);
      }
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
    return {'name': name, 'valid': true, 'constraint': ''};
  }

  @override
  List<bool> match(String val, {bool exact = false}) {
    if (searchable) {
      for (var component in components) {
        final m = component.match(val, exact: exact);
        if (m[0]) return m;
      }
    }
    return [false, false];
  }

  @override
  GenInterface? getComponentAtIndex(int index) {
    if (index >= 0 && index < components.length) {
      return components[index];
    }
    return null;
  }

  @override
  int getComponentIdIndex(String id) {
    for (int i = 0; i < components.length; i++) {
      if (components[i].getId() == id) return i;
    }
    return -1;
  }

  List<int> getObserverComponentIndexes(GenInterface of) {
    List<int> cilist = [];
    for (var key in of.getObservers()) {
      int ci = getComponentIndex(key.toString());
      if (ci != -1) {
        cilist.add(ci);
      }
    }
    return cilist;
  }

  int getComponentIndex(String key) {
    for (int i = 0; i < components.length; i++) {
      if (components[i].getName() == key) return i;
    }
    return -1;
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
    return _CompositeEditor(
      key: key,
      label: name,
      composite: this, // Pass reference to self
      groups: editGroups,
      frefs: frefs,
      index: index,
      autoFocus: autoFocus,
      refresh: refresh,
      cbNotifyParent: cbNotifyParent,
      onChanged: () {
        onChanged(null);
      },
    );
  }

  @override
  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
    if (displayComponent != null && displayComponent.isNotEmpty) {
      final component = _getComponentByName(displayComponent[0].toString());
      if (component != null) {
        return component.display(
          onlyValue: onlyValue,
          displayComponent: displayComponent.length > 1
              ? displayComponent.sublist(1)
              : null,
          onChanged: onChanged,
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!onlyValue)
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        ...displayGroups.map(
          (group) => Wrap(
            spacing: 10,
            children: group
                .map(
                  (c) => c.display(onlyValue: onlyValue, onChanged: onChanged),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _CompositeEditor extends StatefulWidget {
  final String label;
  final Composite composite;
  final List<List<GenInterface>> groups;
  final VoidCallback onChanged;
  final Function(GenInterface, Map<String, dynamic>, List<dynamic>)?
  cbNotifyParent;
  final dynamic frefs;
  final int? index;
  final bool? autoFocus;
  final bool? refresh;

  const _CompositeEditor({
    super.key,
    required this.label,
    required this.composite,
    required this.groups,
    required this.onChanged,
    this.cbNotifyParent,
    this.frefs,
    this.index,
    this.autoFocus,
    this.refresh,
  });

  @override
  State<_CompositeEditor> createState() => _CompositeEditorState();
}

class _CompositeEditorState extends State<_CompositeEditor> {
  bool _isAmountGroup(List<GenInterface> group) {
    if (group.length != 3) return false;
    final names = group.map((c) => c.getName()).toList();
    return names.contains("Charges") &&
        names.contains("Paid") &&
        names.contains("Discount");
  }

  bool _isAgeSexGroup(List<GenInterface> group) {
    if (group.length != 2) return false;
    final names = group.map((c) => c.getName()).toList();
    return names.contains("Age") && names.contains("Sex");
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ...widget.groups.map((group) {
          final isAmount = _isAmountGroup(group);
          final isAgeSex = _isAgeSexGroup(group);
          return Column(
            children: [
              if (isAmount || isAgeSex)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: group
                      .map(
                        (c) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                            ),
                            child: c.editor(
                              key: ValueKey(c.getName()),
                              onChanged: (val) => widget.onChanged(),
                              cbNotifyParent: (notifier, data, observers) {
                                // Calculate observers from the schema if not already provided
                                List<int> observerIndexes = widget.composite
                                    .getObserverComponentIndexes(notifier);

                                if (widget.cbNotifyParent != null) {
                                  // Notify parent (e.g. SimpleAccount) to handle cross-component logic
                                  widget.cbNotifyParent!(
                                    notifier,
                                    data,
                                    observerIndexes,
                                  );
                                } else {
                                  // Handle internal composite observers
                                  for (var idx in observerIndexes) {
                                    final obsComp = widget.composite
                                        .getComponentAtIndex(idx);
                                    obsComp?.notify({
                                      "notifier": data,
                                      "loading": false,
                                    });
                                  }
                                }

                                // Force re-render of this composite to show updated values in editors
                                setState(() {});
                                widget.onChanged();
                              },
                              frefs: widget.frefs,
                              index: widget.index,
                              autoFocus: widget.autoFocus,
                              refresh: widget.refresh,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                )
              else
                Wrap(
                  spacing: 10,
                  children: group
                      .map(
                        (c) => c.editor(
                          key: ValueKey(c.getName()),
                          onChanged: (val) => widget.onChanged(),
                          cbNotifyParent: (notifier, data, observers) {
                            // Calculate observers from the schema if not already provided
                            List<int> observerIndexes = widget.composite
                                .getObserverComponentIndexes(notifier);

                            if (widget.cbNotifyParent != null) {
                              // Notify parent (e.g. SimpleAccount) to handle cross-component logic
                              widget.cbNotifyParent!(
                                notifier,
                                data,
                                observerIndexes,
                              );
                            } else {
                              // Handle internal composite observers
                              for (var idx in observerIndexes) {
                                final obsComp = widget.composite
                                    .getComponentAtIndex(idx);
                                obsComp?.notify({
                                  "notifier": data,
                                  "loading": false,
                                });
                              }
                            }

                            // Force re-render of this composite to show updated values in editors
                            setState(() {});
                            widget.onChanged();
                          },
                          frefs: widget.frefs,
                          index: widget.index,
                          autoFocus: widget.autoFocus,
                          refresh: widget.refresh,
                        ),
                      )
                      .toList(),
                ),
              const Divider(color: Colors.green, thickness: 1),
            ],
          );
        }),
      ],
    );
  }
}
