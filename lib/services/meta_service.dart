class Meta {
  final String dbKey;
  final List<dynamic>? tsPath;
  final Map<String, dynamic> counter = <String, dynamic>{
    "add": <String, dynamic>{}, 
    "update": <String, dynamic>{}, 
    "delete": <String, dynamic>{}
  };
  final Map<String, dynamic> keys = <String, dynamic>{};

  Meta({required this.dbKey, this.tsPath});

  void add(dynamic record) {
    if (record is! Map) return;
    final Map<String, dynamic> r = record.cast<String, dynamic>();
    
    int? ts = _extractTs(r);
    if (ts == null) return;

    final key = r.keys.first;
    if (keys.containsKey(key)) {
      _populate(ts, counter['update']);
    } else {
      keys[key] = null;
      _populate(ts, counter['add']);
    }
  }

  void update(dynamic record) {
    if (record is! Map) return;
    final Map<String, dynamic> r = record.cast<String, dynamic>();
    
    int? ts = _extractTs(r);
    if (ts != null) {
      _populate(ts, counter['update']);
    }
  }

  void delete(String key) {
    if (keys.containsKey(key)) {
      _populate(DateTime.now().millisecondsSinceEpoch, counter['delete']);
      keys.remove(key);
    }
  }

  int? _extractTs(Map<String, dynamic> record) {
    if (record.isEmpty) return null;
    final val = record.values.first;
    
    if (val is Map && val.containsKey('__meta__')) {
       final m = val['__meta__'];
       if (m is Map && m['time'] != null && m['time']['c'] != null) {
         return m['time']['c'];
       }
    }

    if (tsPath != null && val is Map) {
      dynamic current = val;
      for (var k in tsPath!) {
        if (current is Map && current.containsKey(k)) {
          current = current[k];
        } else {
          current = null;
          break;
        }
      }
      if (current is int) return current;
      if (current is String) return int.tryParse(current);
    }
    
    return DateTime.now().millisecondsSinceEpoch;
  }

  void _populate(int ts, dynamic target) {
    if (target is! Map) return;
    final Map<String, dynamic> t = target.cast<String, dynamic>();
    
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final data = [
      ["yy", d.year.toString()],
      ["mm", d.month.toString()],
      ["dd", d.day.toString()],
      ["hh", d.hour.toString()],
    ];

    Map<String, dynamic> current = t;
    for (var step in data) {
      final key = step[0];
      final value = step[1];

      if (!current.containsKey(key)) {
        current[key] = <String, dynamic>{"counter": 1};
      } else {
        current[key]["counter"]++;
      }

      final Map<String, dynamic> nextLevel = (current[key] as Map).cast<String, dynamic>();
      if (!nextLevel.containsKey(value)) {
        nextLevel[value] = <String, dynamic>{"counter": 1};
      } else {
        nextLevel[value]["counter"]++;
      }
      current = (nextLevel[value] as Map).cast<String, dynamic>();
    }
  }

  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    return {
      'Total': keys.length,
      'Adds': _fetchStats(now, counter['add']),
      'Updates': _fetchStats(now, counter['update']),
      'Deletes': _fetchStats(now, counter['delete']),
    };
  }

  Map<String, dynamic> _fetchStats(DateTime d, dynamic source) {
    if (source is! Map) return {'Year': 0, 'Month': 0, 'Today': 0};
    final Map<String, dynamic> s = source.cast<String, dynamic>();
    
    final yy = d.year.toString();
    final mm = d.month.toString();
    final dd = d.day.toString();
    
    int getVal(Map<String, dynamic> src, String k, String v) {
      if (src.containsKey(k)) {
        final Map<String, dynamic> child = (src[k] as Map).cast<String, dynamic>();
        if (child.containsKey(v)) {
          return child[v]['counter'] ?? 0;
        }
      }
      return 0;
    }

    Map<String, dynamic>? getChild(Map<String, dynamic> src, String k, String v) {
      if (src.containsKey(k)) {
        final Map<String, dynamic> child = (src[k] as Map).cast<String, dynamic>();
        if (child.containsKey(v)) {
          return (child[v] as Map).cast<String, dynamic>();
        }
      }
      return null;
    }

    final yyNode = getChild(s, "yy", yy);
    final mmNode = yyNode != null ? getChild(yyNode, "mm", mm) : null;

    return {
      'Year': getVal(s, "yy", yy),
      'Month': yyNode != null ? getVal(yyNode, "mm", mm) : 0,
      'Today': mmNode != null ? getVal(mmNode, "dd", dd) : 0,
    };
  }
}
