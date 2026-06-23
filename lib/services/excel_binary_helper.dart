import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// ExcelBinaryHelper: Decoupled zip/xml processor.
/// Handles sorting sheet lists inside xl/workbook.xml and injecting pre-calculated static formula values.
class ExcelBinaryHelper {
  static final Map<String, int> _monthMap = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Decodes, injects computed static values, sorts sheets, and re-compresses.
  static List<int> postProcessBytes(List<int> bytes, Map<String, String> formulaValues) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      _injectCalculatedValues(archive, formulaValues);
      
      ArchiveFile? workbookXmlFile;
      for (var file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          workbookXmlFile = file;
          break;
        }
      }
      if (workbookXmlFile == null) return bytes;

      var xmlContent = utf8.decode(workbookXmlFile.content);
      var sheetsMatch = RegExp(r'<sheets>(.*?)</sheets>').firstMatch(xmlContent);
      if (sheetsMatch == null) return bytes;

      var sheetsInner = sheetsMatch.group(1)!;
      var sheetRegex = RegExp(r'(<sheet\s+[^>]*name="([^"]+)"[^>]*>)');
      var matches = sheetRegex.allMatches(sheetsInner).toList();

      // Sort sheets chronologically (newest first, monthly first)
      matches.sort((m1, m2) {
        var name1 = m1.group(2)!;
        var name2 = m2.group(2)!;
        return _compareSheetNames(name1, name2);
      });

      var sortedSheetsStr = matches.map((m) => m.group(1)!).join('');
      var newXmlContent = xmlContent.replaceFirst(sheetsInner, sortedSheetsStr);
      var newContent = utf8.encode(newXmlContent);

      var newArchive = Archive();
      for (var file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          newArchive.addFile(ArchiveFile('xl/workbook.xml', newContent.length, newContent));
        } else {
          newArchive.addFile(file);
        }
      }

      return ZipEncoder().encode(newArchive) ?? bytes;
    } catch (e) {
      debugPrint("ExcelBinaryHelper Error: $e");
      return bytes;
    }
  }

  static void _injectCalculatedValues(Archive archive, Map<String, String> formulaValues) {
    try {
      ArchiveFile? workbookXmlFile;
      ArchiveFile? relsFile;
      for (var file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          workbookXmlFile = file;
        } else if (file.name == 'xl/_rels/workbook.xml.rels') {
          relsFile = file;
        }
      }
      if (workbookXmlFile == null || relsFile == null) return;
      
      final wbDoc = XmlDocument.parse(utf8.decode(workbookXmlFile.content));
      final relsDoc = XmlDocument.parse(utf8.decode(relsFile.content));
      
      final Map<String, String> rIdToSheetName = {};
      for (final sheet in wbDoc.findAllElements('sheet')) {
        final name = sheet.getAttribute('name');
        final rId = sheet.getAttribute('r:id');
        if (name != null && rId != null) {
          rIdToSheetName[rId] = name;
        }
      }
      
      final Map<String, String> targetToSheetName = {};
      for (final rel in relsDoc.findAllElements('Relationship')) {
        final rId = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (rId != null && target != null) {
          final sheetName = rIdToSheetName[rId];
          if (sheetName != null) {
            targetToSheetName['xl/$target'] = sheetName;
          }
        }
      }
      
      for (int i = 0; i < archive.files.length; i++) {
        final file = archive.files[i];
        final sheetName = targetToSheetName[file.name];
        if (sheetName != null) {
          final xmlStr = utf8.decode(file.content);
          final sheetDoc = XmlDocument.parse(xmlStr);
          bool modified = false;
          
          for (final c in sheetDoc.findAllElements('c')) {
            final cellRef = c.getAttribute('r');
            if (cellRef == null) continue;

            final f = c.getElement('f');
            final v = c.getElement('v');
            if (f != null && v != null) {
              final lookupKey = "$sheetName!$cellRef";
              final calculatedVal = formulaValues[lookupKey];
              if (calculatedVal != null) {
                // xml v6.x: use innerText setter for text-only elements like <v>
                // v.children returns UnmodifiableListView, so clear()/add() fails
                v.innerText = calculatedVal;
                modified = true;
              }
            }
          }
          if (modified) {
            final newContent = utf8.encode(sheetDoc.toXmlString());
            archive.files[i] = ArchiveFile(file.name, newContent.length, newContent);
          }
        }
      }
    } catch (e) {
      debugPrint("ExcelBinaryHelper._injectCalculatedValues Error: $e");
    }
  }

  static int _compareSheetNames(String a, String b) {
    final bool aMonthly = _isMonthly(a);
    final bool bMonthly = _isMonthly(b);
    if (aMonthly && !bMonthly) return -1;
    if (!aMonthly && bMonthly) return 1;

    final dateA = _parseSheetDate(a);
    final dateB = _parseSheetDate(b);
    if (dateA != null && dateB != null) {
      return dateB.compareTo(dateA); // Descending
    }
    return b.compareTo(a);
  }

  static bool _isMonthly(String name) {
    return RegExp(r'^[A-Za-z]{3}_\d{4}$').hasMatch(name);
  }

  static DateTime? _parseSheetDate(String name) {
    final monthlyRegex = RegExp(r'^([A-Za-z]{3})_(\d{4})$');
    final monthlyMatch = monthlyRegex.firstMatch(name);
    if (monthlyMatch != null) {
      final monthStr = monthlyMatch.group(1)!;
      final yearStr = monthlyMatch.group(2)!;
      final month = _monthMap[monthStr.toLowerCase()] ?? 1;
      final year = int.tryParse(yearStr) ?? DateTime.now().year;
      return DateTime(year, month, 1);
    }

    final cleaned = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ').trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      final day = int.tryParse(parts[0]);
      if (day != null && day >= 1 && day <= 31) {
        int? month = _monthMap[parts[1].toLowerCase()] ?? int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);
        if (month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
    }
    return DateTime.tryParse(cleaned) ?? DateTime.tryParse(name);
  }
}
