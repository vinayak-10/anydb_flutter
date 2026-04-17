import '../core/gen_interface.dart';

class MetaDefault extends GenInterface {
  DateTime created = DateTime.now();
  DateTime? updated;
  DateTime? archived;
  DateTime? deleted;

  @override
  String getType() => "meta-default";

  @override
  void init(Map<String, dynamic>? jsonObj, dynamic repoIntf) {
    created = DateTime.now();
  }

  @override
  void populate(Map<String, dynamic> jsonDb) {
    if (jsonDb.containsKey('__meta__')) {
      final meta = jsonDb['__meta__'];
      final time = meta['time'] ?? {};
      if (time.containsKey('c')) created = DateTime.fromMillisecondsSinceEpoch(time['c']);
      if (time.containsKey('u')) updated = DateTime.fromMillisecondsSinceEpoch(time['u']);
      if (time.containsKey('a')) archived = DateTime.fromMillisecondsSinceEpoch(time['a']);
      if (time.containsKey('d')) deleted = DateTime.fromMillisecondsSinceEpoch(time['d']);
    }
  }

  @override
  Map<String, dynamic> fetch() {
    final Map<String, dynamic> time = {'c': created.millisecondsSinceEpoch};
    if (updated != null) time['u'] = updated!.millisecondsSinceEpoch;
    if (archived != null) time['a'] = archived!.millisecondsSinceEpoch;
    if (deleted != null) time['d'] = deleted!.millisecondsSinceEpoch;
    
    return {'__meta__': {'time': time}};
  }
}
