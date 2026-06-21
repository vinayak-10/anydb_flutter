class SqliteHelper {
  static String? databasePathOverride;

  static Future<void> initTable(String dbName) async {
    return;
  }

  static Future<List<Map<String, dynamic>>> getAll(
    String dbName, {
    String filter = 'Active',
    bool allRecords = false,
  }) async {
    return [];
  }

  static Future<Map<String, dynamic>?> get(String dbName, String key) async {
    return null;
  }

  static Future<void> update(String dbName, String key, dynamic val) async {
    return;
  }

  static Future<void> updateAll(
    String dbName,
    Map<String, dynamic> items,
  ) async {
    return;
  }

  static Future<void> remove(String dbName, String key) async {
    return;
  }

  static Future<void> clear(String dbName) async {
    return;
  }

  static Future<Map<String, dynamic>?> getActiveByBusinessKey(
    String dbName,
    String businessKeyValue,
  ) async {
    return null;
  }

  static Future<void> initConfigurationsTable() async {
    return;
  }

  static Future<String?> getBusinessUniqueKey(String schemaName) async {
    return null;
  }

  static Future<void> setBusinessUniqueKey(
    String schemaName,
    String keyName,
  ) async {
    return;
  }

  static Future<String?> getBusinessUniqueKeyRaw(String schemaName) async {
    return null;
  }

  static Future<void> setBusinessUniqueKeyRaw(
    String schemaName,
    String keyName,
  ) async {
    return;
  }

  static Future<List<Map<String, dynamic>>> getAllRaw(String dbName) async {
    return [];
  }

  static Future<List<Map<String, String>>> getAllRawString(
    String dbName,
  ) async {
    return [];
  }

  static Future<List<Map<String, String>>> getActiveRecordsRawString(
    String dbName,
  ) async {
    return [];
  }

  static Future<List<Map<String, String>>> getInactiveRecordsRawString(
    String dbName,
  ) async {
    return [];
  }

  static Future<void> updateAllRaw(
    String dbName,
    Map<String, dynamic> items, [
    String? businessKeyName,
  ]) async {
    return;
  }

  static Future<void> updateRaw(
    String dbName,
    String key,
    dynamic val, [
    String? businessKeyName,
  ]) async {
    return;
  }

  static Future<void> initTimestampsTable() async {
    return;
  }

  static Future<void> backfillTimestamps(String dbName) async {
    return;
  }

  static Future<void> updateRecordTimestamp(
    String dbName,
    String id,
    int isActive,
    int timestamp,
  ) async {
    return;
  }

  static Future<List<String>> getTopRecentIds(
    String dbName,
    int limit, {
    String filter = 'Active',
  }) async {
    return [];
  }

  static Future<List<Map<String, String>>> getRecordsByIds(
    String dbName,
    List<String> ids,
  ) async {
    return [];
  }

  static Future<bool> isTableEmpty(String dbName) async {
    return true;
  }
}
