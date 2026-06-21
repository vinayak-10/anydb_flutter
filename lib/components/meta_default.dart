import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/gen_interface.dart';

class MetaDefault extends GenInterface {
  DateTime created = DateTime.now();
  DateTime? updated;
  DateTime? archived;
  DateTime? deleted;
  Map<String, dynamic>? oSchema;
  dynamic repoIntf;

  @override
  String getType() => "meta-default";

  @override
  String getName() => "__meta__";

  @override
  String getId() => "__meta__";

  @override
  void init(Map<String, dynamic>? jsonObj, dynamic repoIntf) {
    oSchema = jsonObj;
    this.repoIntf = repoIntf;
    created = DateTime.now();
    updated = DateTime.now();
  }

  @override
  GenInterface clone() {
    final c = MetaDefault();
    c.init(oSchema ?? {}, repoIntf);
    c.populate(fetch());
    return c;
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey('__meta__')) {
      final meta = jsonDb['__meta__'];
      if (meta.containsKey('u'))
        updated = DateTime.fromMillisecondsSinceEpoch(meta['u']);
      final time = meta['time'] ?? {};
      if (time.containsKey('c'))
        created = DateTime.fromMillisecondsSinceEpoch(time['c']);
      if (time.containsKey('u'))
        updated = DateTime.fromMillisecondsSinceEpoch(time['u']);
      if (time.containsKey('a'))
        archived = DateTime.fromMillisecondsSinceEpoch(time['a']);
      if (time.containsKey('d'))
        deleted = DateTime.fromMillisecondsSinceEpoch(time['d']);
    }
  }

  @override
  Widget display({
    bool onlyValue = false,
    List<dynamic>? displayComponent,
    VoidCallback? onChanged,
  }) {
    if (onlyValue) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Book-keeping Info",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const Divider(),
            _row("Created On", created, Colors.green),
            if (updated != null) _row("Updated On", updated!, Colors.orange),
            if (archived != null) _row("Archived On", archived!, Colors.blue),
            if (deleted != null) _row("Marked Delete On", deleted!, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, DateTime dt, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 13)),
          Text(
            DateFormat('yMMMd, HH:mm').format(dt),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
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
  Map<String, dynamic> fetch() {
    updated = DateTime.now();
    final Map<String, dynamic> time = {
      'c': created.millisecondsSinceEpoch,
      'u': updated!.millisecondsSinceEpoch,
    };
    if (archived != null) time['a'] = archived!.millisecondsSinceEpoch;
    if (deleted != null) time['d'] = deleted!.millisecondsSinceEpoch;

    return {
      '__meta__': {'time': time},
    };
  }
}
