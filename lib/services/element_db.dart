import 'package:flutter/foundation.dart';
import '../models/element_model.dart';
import 'storage_service.dart';

class ElementDb {
  String key = '';
  List<dynamic> dbHeader = [];
  List<dynamic> dbSchema = [];
  final StorageService storage = StorageService();
  List<ElementModel> elements = [];
  List<dynamic> fullSchema = [];
  dynamic intf;

  bool initialized = false;

  Future<void> init(dynamic schemaJson, dynamic interface) async {
    if (schemaJson is! Map) {
      debugPrint("ElementDb.init error: schemaJson is not a Map! It is ${schemaJson.runtimeType}");
      return;
    }
    
    final Map<String, dynamic> sj = Map<String, dynamic>.from(schemaJson);
    debugPrint("ElementDb.init: starting for ${sj['name']}");
    fullSchema = <dynamic>[sj];
    key = sj['name']?.toString() ?? "";
    
    final rawHeader = sj['header'] ?? [];
    debugPrint("ElementDb.init: rawHeader type is ${rawHeader.runtimeType}");
    dbHeader = _prepareHeader(rawHeader);
    
    final rawSchema = sj['schema'] ?? [];
    debugPrint("ElementDb.init: rawSchema type is ${rawSchema.runtimeType}");
    dbSchema = _prepareSchema(rawSchema);
    
    intf = interface;

    final storageConfig = sj['storage'] ?? [];
    await storage.init(key, storageConfig is List ? storageConfig : [storageConfig]);
    initialized = true;
    debugPrint("ElementDb.init: finished for $key");
  }

  List<dynamic> _prepareHeader(dynamic h) {
    if (h is List) return List<dynamic>.from(h);
    if (h is Map) {
      return <dynamic>[
        <dynamic>[h['title']?.toString() ?? ''],
        <dynamic>[h['subtitle']?.toString() ?? '']
      ];
    }
    return <dynamic>[];
  }

  List<dynamic> _prepareSchema(dynamic s) {
    if (s is List) return List<dynamic>.from(s);
    if (s is Map) return <dynamic>[s];
    return <dynamic>[];
  }

  Future<int> initDb({bool forced = false}) async {
    if (initialized && !forced && elements.isNotEmpty) {
      return elements.length;
    }

    elements = [];
    final allData = await storage.fetch();
    
    for (var data in allData) {
      final element = ElementModel();
      element.init(dbSchema, intf);
      element.populate(data);
      elements.add(element);
    }

    return elements.length;
  }

  Future<void> addRecord(ElementModel element) async {
    final data = element.fetch();
    final recordKey = data.keys.first;
    final recordVal = data.values.first;
    
    await storage.add(recordKey, recordVal);
    elements.add(element);
  }

  Future<void> removeRecord(String recordKey) async {
    await storage.remove(recordKey);
    elements.removeWhere((e) => e.key == recordKey);
  }

  List<ElementModel> applyFilter(String filterType) {
    if (filterType == 'All') return elements;
    
    return elements.where((e) {
      final data = e.fetch();
      final val = data.values.first;
      final meta = val['__meta__'];
      
      if (filterType == 'Active') {
        if (meta == null) return true;
        final time = meta['time'] ?? {};
        return !time.containsKey('a') && !time.containsKey('d');
      }
      
      if (filterType == 'Archived') {
        if (meta == null) return false;
        final time = meta['time'] ?? {};
        return time.containsKey('a');
      }

      if (filterType == 'Deleted') {
        if (meta == null) return false;
        final time = meta['time'] ?? {};
        return time.containsKey('d');
      }
      
      return true;
    }).toList();
  }

  List<ElementModel> search(String query) {
    if (query.isEmpty) return elements;
    return elements.where((e) => e.match(query)[0]).toList();
  }
}
