import '../core/gen_interface.dart';
import '../core/widget_factory.dart';

class ValueExtractor {
  List<dynamic> values = [];
  String type = '';

  void init(
    Map<String, dynamic> schema,
    List<dynamic> dbSchema,
    dynamic repoIntf,
  ) {
    type = schema['type'] ?? '';
    if (type == 'values') {
      values = schema['value'] ?? [];
    } else if (type == 'function') {
      final funcSpecs = schema['value'] as List<dynamic>? ?? [];
      for (var spec in funcSpecs) {
        final on = spec['on'] as String? ?? '';
        for (var s in dbSchema) {
          if (s['name'] == on) {
            final component = WidgetFactory.get(s['type']);
            if (component != null) {
              component.init(s, repoIntf);
              values.add({'schema': spec, 'component': component});
            }
          }
        }
      }
    }
  }

  List<dynamic> extract(Map<String, dynamic> record) {
    if (type == 'values') {
      return _valueFn(record);
    } else if (type == 'function') {
      return _functionFn(record);
    }
    return [];
  }

  List<dynamic> _valueFn(Map<String, dynamic> record) {
    List<dynamic> results = [];
    final recordValue = record.values.first;
    for (var vkey in values) {
      if (vkey is! List) continue;
      dynamic rv = recordValue;
      int matchedCount = 0;
      for (var k in vkey) {
        if (rv is Map && rv.containsKey(k)) {
          rv = rv[k];
          matchedCount++;
        }
      }
      if (matchedCount == vkey.length) {
        results.add(rv);
      }
    }
    return results;
  }

  List<dynamic> _functionFn(Map<String, dynamic> record) {
    List<dynamic> results = [];
    final recordValue = record.values.first;
    for (var content in values) {
      final GenInterface component = content['component'];
      final Map<String, dynamic> spec = content['schema'];
      component.populate(recordValue);
      final invoked = component.invoke(
        method: spec['what'] ?? '',
        parameters: spec['parameters'] ?? {},
      );
      if (invoked != null) {
        results.add(invoked);
      }
    }
    return results;
  }
}
