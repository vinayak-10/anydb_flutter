import 'package:flutter/foundation.dart';
import 'element_db.dart';
import '../models/element_model.dart';

class CollectionService {
  String collectionName = '';
  String collectionDescription = '';
  final List<ElementDb> dbs = [];
  // final List<Aggregator> aggregators = []; // To be implemented

  Future<Map<String, int>> init(dynamic collectionSchema) async {
    if (collectionSchema is! Map) {
      debugPrint("CollectionService.init error: collectionSchema is not a Map!");
      return {'database': 0, 'aggregator': 0};
    }
    
    final Map<String, dynamic> cs = Map<String, dynamic>.from(collectionSchema);
    debugPrint("CollectionService.init: starting for ${cs['name']}");
    collectionName = cs['name'] ?? '';
    collectionDescription = cs['description'] ?? '';
    dbs.clear();

    final rawContents = cs['contents'];
    debugPrint("CollectionService.init: rawContents type is ${rawContents.runtimeType}");
    List<dynamic>? contents;
    if (rawContents is List) {
      contents = rawContents;
    } else if (rawContents is Map) {
      contents = [rawContents];
    }

    if (contents != null) {
      for (var schemaItem in contents) {
        if (schemaItem is! Map) continue;
        final item = Map<String, dynamic>.from(schemaItem);
        
        debugPrint("CollectionService.init: item type is ${item.runtimeType}, value = ${item['name']}");
        if (item['type'] == 'database') {
          final edb = ElementDb();
          await edb.init(item, {
            'dataRefIntf': (r) => getDb(r),
            'open': (what) => open(what),
          });
          dbs.add(edb);
        }
      }
    }
    
    return {'database': dbs.length, 'aggregator': 0};
  }

  ElementDb? getDb(String name) {
    try {
      return dbs.firstWhere((db) => db.key == name);
    } catch (_) {
      return null;
    }
  }

  Future<void> open(Map<String, dynamic> what) async {
    // In Flutter, this would use url_launcher or a file viewer package
    final uri = what['uri'];
    if (uri != null) {
      // await InvokerService.open(uri);
    }
  }

  ElementModel? getElement(String keyDb, String keyElement) {
    final db = getDb(keyDb);
    if (db != null) {
      try {
        return db.elements.firstWhere((e) => e.key == keyElement);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
