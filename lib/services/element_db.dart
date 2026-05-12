import 'package:flutter/foundation.dart';
import '../models/element_model.dart';
import 'storage_service.dart';
import 'meta_service.dart';
import 'event_trigger_service.dart';

class ElementDb {
  String key = '';
  List<dynamic> dbHeader = [];
  List<dynamic> dbSchema = [];
  final StorageService storage = StorageService();
  List<ElementModel> elements = [];
  List<dynamic> fullSchema = [];
  dynamic intf;
  late Meta metaService;
  EventTriggerService? _triggerService;

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

    final List<dynamic>? tsPath = sj['meta']?['ts'];
    metaService = Meta(dbKey: key, tsPath: tsPath);

    if (sj.containsKey('events')) {
      _triggerService = EventTriggerService(db: this, eventsSchema: sj['events']);
    }

    final storageConfig = sj['storage'] ?? [];
    await storage.init(key, storageConfig is List ? storageConfig : [storageConfig]);
    
    initialized = true;
    _triggerService?.trigger('onDbStart');
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

  List<Map<String, dynamic>> segregate(List<Map<String, dynamic>> records, {List<String> types = const ["Active"]}) {
    if (types.contains("All")) return records;

    return records.where((rec) {

      if (rec.isEmpty) return false;
      final val = rec.values.first;
      if (val is! Map) return false;

      final meta = val['__meta__'];
      final time = meta != null ? meta['time'] : null;

      bool isArchived = time != null && time.containsKey('a');
      bool isDeleted = time != null && time.containsKey('d');
      bool isActive = !isArchived && !isDeleted;

      bool match = false;
      for (var type in types) {
        if (type == "Active" && isActive) match = true;
        if (type == "Archived" && isArchived) match = true;
        if (type == "Deleted" && isDeleted) match = true;
      }
      return match;
    }).toList();
  }

  Future<int> initDb({bool forced = false, List<String> filter = const ["Active"]}) async {
    if (initialized && !forced && elements.isNotEmpty) {
      return elements.length;
    }

    elements = [];
    final allData = await storage.fetch();

    // 1. Trigger Database Start (Ported from RN)
    await _triggerService?.trigger('onDbStart', allData);

    // 2. Segregate/Filter records (Ported from RN)
    final filteredData = segregate(allData, types: filter);

    final now = DateTime.now().millisecondsSinceEpoch;
    const purgeThreshold = 72 * 60 * 60 * 1000; // 72 hours in ms

    for (var data in filteredData) {
      final key = data.keys.first;
      final val = data.values.first as Map<String, dynamic>;

      // Auto-purge logic for truly deleted items
      final meta = val['__meta__'];
      if (meta != null && meta['time'] != null && meta['time']['d'] != null) {
        final deleteTime = meta['time']['d'] as int;
        if (now - deleteTime > purgeThreshold) {
          await storage.remove(key);
          continue;
        }
      }

      final element = ElementModel();
      element.init(dbSchema, intf);
      element.populate(data);
      elements.add(element);
    }

    initialized = true;
    return elements.length;
  }


  Future<void> markArchive(ElementModel element) async {
    final data = element.fetch();
    final key = data.keys.first;
    final val = data.values.first as Map<String, dynamic>;
    
    val['__meta__'] ??= {};
    val['__meta__']['time'] ??= {};
    val['__meta__']['time']['a'] = DateTime.now().millisecondsSinceEpoch;
    
    await storage.add(key, val);
    await initDb(forced: true);
  }

  Future<void> markDelete(ElementModel element) async {
    final data = element.fetch();
    final key = data.keys.first;
    final val = data.values.first as Map<String, dynamic>;
    
    val['__meta__'] ??= {};
    val['__meta__']['time'] ??= {};
    val['__meta__']['time']['d'] = DateTime.now().millisecondsSinceEpoch;
    
    await storage.add(key, val);
    await initDb(forced: true);
  }

  Future<void> restore(ElementModel element) async {
    final data = element.fetch();
    final key = data.keys.first;
    final val = data.values.first as Map<String, dynamic>;
    
    if (val['__meta__'] != null && val['__meta__']['time'] != null) {
      val['__meta__']['time'].remove('a');
      val['__meta__']['time'].remove('d');
    }
    
    await storage.add(key, val);
    await initDb(forced: true);
  }

  Map<String, dynamic> getStats() {
    return metaService.getStats();
  }

  Future<void> addRecord(ElementModel element) async {
    final data = element.fetch();
    final recordKey = data.keys.first;
    final recordVal = data.values.first;
    
    await storage.add(recordKey, recordVal);
    
    // Check if record already exists in local list to prevent duplicates
    int existingIdx = elements.indexWhere((e) => e.key == recordKey);
    if (existingIdx != -1) {
      elements[existingIdx] = element;
      metaService.update(data);
    } else {
      elements.add(element);
      metaService.add(data);
    }
  }

  Future<void> removeRecord(String recordKey) async {
    await storage.remove(recordKey);
    elements.removeWhere((e) => e.key == recordKey);
    metaService.delete(recordKey);
  }

  Future<void> clear() async {
    await storage.clear();
    elements.clear();
    metaService = Meta(dbKey: key, tsPath: metaService.tsPath);
  }

  Future<void> importDb(List<dynamic> data, {bool wipeFirst = false}) async {
    if (wipeFirst) {
      await clear();
    }
    await storage.importData(data);
    await initDb(forced: true);
  }

  Future<List<dynamic>> exportDb() async {
    return await storage.exportData();
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

  Future<void> close() async {
    await _triggerService?.trigger('onDbStop');
  }
}
