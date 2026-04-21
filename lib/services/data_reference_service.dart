import 'storage_service.dart';

abstract class DataReferenceIntf {
  String name();
  Future<void> init(Map<String, dynamic> reference);
  Map<String, dynamic>? interface();
}

class DataReferenceDatabase extends DataReferenceIntf {
  String _name = '';
  List<Map<String, dynamic>> _store = [];

  @override
  String name() => _name;

  @override
  Future<void> init(Map<String, dynamic> reference) async {
    _name = reference['name'] ?? '';
    final source = reference['source'] as Map<String, dynamic>?;
    if (source == null) return;

    if (source['storage'] == 'local') {
      await _populate(source['name'], source['keys'] as List<dynamic>? ?? []);
    }
  }

  Future<void> _populate(String dbKey, List<dynamic> keys) async {
    final localStore = LocalStore();
    await localStore.init(dbKey, {});
    final all = await localStore.fetch();

    _store = [];
    for (var element in all) {
      final key = element.keys.first;
      final value = element.values.first;

      Map<String, dynamic> entry = {'key': key};
      int keyIndex = 0;
      for (var k in keys) {
        final kv = _getValue(k as List<dynamic>, value);
        if (kv != null) {
          entry[keyIndex.toString()] = kv;
          keyIndex++;
        }
      }
      _store.add(entry);
    }
  }

  dynamic _getValue(List<dynamic> path, dynamic value) {
    dynamic v = value;
    for (var k in path) {
      if (v is Map && v.containsKey(k)) {
        v = v[k];
      } else {
        return null;
      }
    }
    return v;
  }

  @override
  Map<String, dynamic> interface() {
    return {
      'fetch': () => {'name': _name, 'store': _store},
    };
  }
}

class DataReferenceService {
  DataReferenceIntf? reference;
  String _name = '';

  Future<String> init(Map<String, dynamic> refJson) async {
    final source = refJson['source'] as Map<String, dynamic>?;
    if (source == null) throw "Invalid reference source";

    if (source['type'] == 'database') {
      final dsdb = DataReferenceDatabase();
      await dsdb.init(refJson);
      reference = dsdb;
      _name = refJson['name'] ?? '';
      return _name;
    }
    throw "Unsupported reference type: ${source['type']}";
  }

  Map<String, dynamic>? interface() {
    return reference?.interface();
  }
}
