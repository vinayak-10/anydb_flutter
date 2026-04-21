import 'package:flutter/foundation.dart';
import 'element_db.dart';

class EventTriggerService {
  final ElementDb db;
  final Map<String, dynamic> eventsSchema;

  EventTriggerService({required this.db, required this.eventsSchema});

  Future<void> trigger(String eventName) async {
    final List<dynamic> actionsToRun = eventsSchema[eventName] ?? [];
    if (actionsToRun.isEmpty) return;

    final allActions = eventsSchema['actions'] as List<dynamic>? ?? [];

    for (var actionName in actionsToRun) {
      final action = allActions.firstWhere((a) => a['name'] == actionName, orElse: () => null);
      if (action != null) {
        await _executeAction(action);
      }
    }
  }

  Future<void> _executeAction(Map<String, dynamic> action) async {
    final predicates = action['predicates'] as List<dynamic>? ?? [];
    debugPrint("EventTrigger: Executing action ${action['name']}");

    for (var pred in predicates) {
      final type = pred['type'];

      switch (type) {
        case 'export':
          // Auto backup logic
          await db.storage.exportData();
          break;
        case 'generate':
          // Auto report logic
          // This would ideally call AggregatorService.generateReport
          break;
        case 'notify':
          // Show toast/notification
          break;
      }
    }
  }
}
