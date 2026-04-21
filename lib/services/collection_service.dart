import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'element_db.dart';
import 'aggregator_service.dart';

enum ContentType { database, aggregator }

class AppContent {
  final String name;
  final ContentType type;
  final dynamic service; // ElementDb or AggregatorService
  final Map<String, dynamic> schema;

  AppContent({
    required this.name,
    required this.type,
    required this.service,
    required this.schema,
  });
}

class CollectionService {
  String collectionName = '';
  String collectionDescription = '';
  final List<AppContent> contents = [];

  Future<Map<String, int>> init(dynamic collectionSchema) async {
    if (collectionSchema is! Map) {
      debugPrint("CollectionService.init error: collectionSchema is not a Map!");
      return {'database': 0, 'aggregator': 0};
    }
    
    final Map<String, dynamic> cs = Map<String, dynamic>.from(collectionSchema);
    debugPrint("CollectionService.init: starting for ${cs['name']}");
    collectionName = cs['name'] ?? '';
    collectionDescription = cs['description'] ?? '';
    contents.clear();

    final rawContents = cs['contents'];
    List<dynamic>? rawList;
    if (rawContents is List) {
      rawList = rawContents;
    } else if (rawContents is Map) {
      rawList = [rawContents];
    }

    int dbCount = 0;
    int aggCount = 0;

    if (rawList != null) {
      List<AppContent> dbsList = [];
      List<AppContent> aggsList = [];

      for (var schemaItem in rawList) {
        if (schemaItem is! Map) continue;
        final item = Map<String, dynamic>.from(schemaItem);
        final String name = item['name'] ?? 'Unnamed';
        final String type = item['type'] ?? '';

        if (type == 'database') {
          final edb = ElementDb();
          await edb.init(item, {
            'dataRefIntf': (r) => getDb(r),
            'open': (what) => open(what),
          });
          dbsList.add(AppContent(
            name: name,
            type: ContentType.database,
            service: edb,
            schema: item,
          ));
          dbCount++;
        } else if (type == 'aggregator') {
          final agg = AggregatorService();
          agg.init(item);
          aggsList.add(AppContent(
            name: name,
            type: ContentType.aggregator,
            service: agg,
            schema: item,
          ));
          aggCount++;
        }
      }
      contents.addAll(dbsList);
      contents.addAll(aggsList);
    }
    
    return {'database': dbCount, 'aggregator': aggCount};
  }

  ElementDb? getDb(String name) {
    try {
      final content = contents.firstWhere(
        (c) => c.type == ContentType.database && c.name == name
      );
      return content.service as ElementDb;
    } catch (_) {
      return null;
    }
  }

  Future<void> open(Map<String, dynamic> what) async {
    // Implementation for opening files/URLs
  }
}

final collectionServiceProvider = Provider((ref) => CollectionService());
