import 'package:flutter_test/flutter_test.dart';
import 'package:anydb_flutter/services/element_db.dart';

void main() {
  test('ElementDb.init should handle Map and List for header/schema', () async {
    final edb = ElementDb();
    
    final schemaJson = {
      'name': 'TestDB',
      'header': {
        'title': 'Test Title',
        'subtitle': 'Test Subtitle'
      },
      'schema': {
        'type': 'text',
        'name': 'Field1'
      },
      'storage': []
    };
    
    await edb.init(schemaJson, null);
    
    expect(edb.key, 'TestDB');
    expect(edb.dbHeader, isA<List>());
    expect(edb.dbHeader.length, 2);
    expect(edb.dbHeader[0][0], 'Test Title');
    
    expect(edb.dbSchema, isA<List>());
    expect(edb.dbSchema.length, 1);
    expect(edb.dbSchema[0]['name'], 'Field1');
  });

  test('ElementDb.init should handle already List header/schema', () async {
    final edb = ElementDb();
    
    final schemaJson = {
      'name': 'TestDB2',
      'header': [['Row1']],
      'schema': [{'type': 'text', 'name': 'Field2'}],
      'storage': []
    };
    
    await edb.init(schemaJson, null);
    
    expect(edb.dbHeader, isA<List>());
    expect(edb.dbHeader[0][0], 'Row1');
    expect(edb.dbSchema.length, 1);
    expect(edb.dbSchema[0]['name'], 'Field2');
  });
}
