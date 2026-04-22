import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'element_db.dart';
import '../core/value_extractor.dart';
import 'storage_service.dart';

abstract class EventPredicate {
  String getName();
  Future<dynamic> execute(Map<String, dynamic> record, List<dynamic> prevResults);
}

class EventActionMatch extends EventPredicate {
  final Map<String, dynamic> schema;
  final List<dynamic> dbSchema;
  final ValueExtractor extractor = ValueExtractor();

  EventActionMatch(this.schema, this.dbSchema, dynamic repoIntf) {
    extractor.init(schema['parameter']['key'], dbSchema, repoIntf);
  }

  @override
  String getName() => "match";

  @override
  Future<dynamic> execute(Map<String, dynamic> record, List<dynamic> prevResults) async {
    final vals = extractor.extract(record);
    if (vals.isEmpty) return Future.error("No value extracted");

    final ts = _toTimestamp(vals[0]);
    final predicate = schema['parameter']['predicate'] ?? {};
    final now = DateTime.now();

    if (predicate.containsKey('before')) {
      final before = predicate['before'];
      final target = now.subtract(Duration(
        days: (before['dd'] ?? 0),
        // Simplification for months/years
      )).subtract(Duration(days: (before['mm'] ?? 0) * 30 + (before['yy'] ?? 0) * 365));
      
      if (ts < target.millisecondsSinceEpoch) return ts;
    }

    if (predicate.containsKey('after')) {
      final after = predicate['after'];
      final target = now.add(Duration(
        days: (after['dd'] ?? 0),
      )).add(Duration(days: (after['mm'] ?? 0) * 30 + (after['yy'] ?? 0) * 365));
      
      if (ts > target.millisecondsSinceEpoch) return ts;
    }

    return Future.error("No match");
  }

  int _toTimestamp(dynamic val) {
    if (val is num) return val.toInt();
    if (val is String) return DateTime.tryParse(val)?.millisecondsSinceEpoch ?? 0;
    return 0;
  }
}

class EventActionMeta extends EventPredicate {
  final Map<String, dynamic> schema;
  final List<dynamic> dbSchema;
  final StorageService storage;
  final ValueExtractor? srcExtractor;
  late String what;

  EventActionMeta(this.schema, this.dbSchema, this.storage, dynamic repoIntf)
      : srcExtractor = schema['parameter']['src'] != null ? ValueExtractor() : null {
    if (srcExtractor != null) {
      srcExtractor!.init(schema['parameter']['src'], dbSchema, repoIntf);
    }
    switch (schema['parameter']['modify']) {
      case "time.create": what = "c"; break;
      case "time.update": what = "u"; break;
      case "time.archive": what = "a"; break;
      case "time.delete": what = "d"; break;
      default: what = "";
    }
  }

  @override
  String getName() => "meta";

  @override
  Future<dynamic> execute(Map<String, dynamic> record, List<dynamic> prevResults) async {
    int value2Update = DateTime.now().millisecondsSinceEpoch;
    if (srcExtractor != null) {
      final vals = srcExtractor!.extract(record);
      if (vals.isNotEmpty && vals[0] is num) value2Update = vals[0].toInt();
    }

    final key = record.keys.first;
    final valueO = Map<String, dynamic>.from(record.values.first);
    bool updated = false;

    if (!valueO.containsKey("__meta__")) {
      valueO["__meta__"] = {"time": {"c": 0, "u": 0}, "flags": []};
      updated = true;
    }

    final meta = valueO["__meta__"] as Map<String, dynamic>;
    final time = meta["time"] as Map<String, dynamic>;

    switch (what) {
      case "c":
        if (time["c"] != value2Update) {
          time["c"] = value2Update;
          updated = true;
        }
        break;
      case "u":
        if (time["u"] != value2Update) {
          time["u"] = value2Update;
          updated = true;
        }
        break;
      case "a":
        if (!time.containsKey("a")) {
          time["a"] = value2Update;
          updated = true;
        }
        break;
      case "d":
        if (!time.containsKey("d")) {
          time["d"] = value2Update;
          updated = true;
        }
        break;
    }

    if (updated) {
      await storage.add(key, valueO);
      return value2Update;
    }
    return Future.error("Not updated");
  }
}

class EventActionDelete extends EventPredicate {
  final StorageService storage;
  EventActionDelete(this.storage);

  @override
  String getName() => "delete";

  @override
  Future<dynamic> execute(Map<String, dynamic> record, List<dynamic> prevResults) async {
    final key = record.keys.first;
    await storage.remove(key);
    return key;
  }
}

class EventAction {
  final String name;
  final List<EventPredicate> predicates = [];

  EventAction(this.name);

  void init(Map<String, dynamic> schema, List<dynamic> dbSchema, StorageService storage, dynamic repoIntf) {
    final preds = schema['predicates'] as List<dynamic>? ?? [];
    for (var p in preds) {
      switch (p['type']) {
        case 'match': predicates.add(EventActionMatch(p, dbSchema, repoIntf)); break;
        case 'meta': predicates.add(EventActionMeta(p, dbSchema, storage, repoIntf)); break;
        case 'delete': predicates.add(EventActionDelete(storage)); break;
        // Other types like export/generate can be added here
      }
    }
  }

  Future<Map<String, dynamic>> executeAll(List<Map<String, dynamic>>? records) async {
    Map<String, dynamic> stats = {"success": 0, "failure": 0, "updated": false};
    if (records == null) return stats;

    for (var record in records) {
      List<dynamic> results = [];
      bool sequenceSuccess = true;
      
      for (var pred in predicates) {
        try {
          final res = await pred.execute(record, results);
          results.add(res);
          stats["updated"] = true;
        } catch (e) {
          sequenceSuccess = false;
          break;
        }
      }
      
      if (sequenceSuccess) {
        stats["success"]++;
      } else {
        stats["failure"]++;
      }
    }
    return stats;
  }
}

class EventTriggerService {
  final ElementDb db;
  final Map<String, dynamic> eventsSchema;
  final List<EventAction> _actions = [];
  final Map<String, List<EventAction>> _triggers = {};

  EventTriggerService({required this.db, required this.eventsSchema}) {
    _init();
  }

  void _init() {
    final actionSchemas = eventsSchema['actions'] as List<dynamic>? ?? [];
    final dbSchema = db.dbSchema;

    for (var schema in actionSchemas) {
      final action = EventAction(schema['name']);
      action.init(schema, dbSchema, db.storage, db.intf);
      _actions.add(action);
    }

    _triggers['onDbStart'] = _getActions(eventsSchema['onDbStart']);
    _triggers['onDbStop'] = _getActions(eventsSchema['onDbStop']);
    _triggers['onDbEntryAdd'] = _getActions(eventsSchema['onDbEntryAdd']);
    _triggers['onDbEntryUpdate'] = _getActions(eventsSchema['onDbEntryUpdate']);
    _triggers['onDbEntryDelete'] = _getActions(eventsSchema['onDbEntryDelete']);
  }

  List<EventAction> _getActions(dynamic names) {
    if (names is! List) return [];
    List<EventAction> result = [];
    for (var name in names) {
      try {
        result.add(_actions.firstWhere((a) => a.name == name));
      } catch (e) {
        debugPrint("EventTrigger: Action '$name' not found.");
      }
    }
    return result;
  }

  Future<void> trigger(String eventName, [List<Map<String, dynamic>>? records]) async {
    final actions = _triggers[eventName];
    if (actions == null || actions.isEmpty) return;

    final targetRecords = records ?? await db.storage.fetch();

    for (var action in actions) {
      final result = await action.executeAll(targetRecords);
      if (result['updated'] == true) {
        // If data was changed (meta update or delete), we might need to refresh DB
        // But for now, we follow RN's lead which just logs results.
        debugPrint("EventTrigger: Action ${action.name} updated records.");
      }
    }
  }
}
