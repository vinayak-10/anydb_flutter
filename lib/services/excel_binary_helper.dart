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
  ///
  /// [previousBytes]: the raw bytes of the file *before* excel.save() was called on this
  /// iteration. package:excel strips all &lt;v&gt; cached-value tags when it re-serialises the
  /// workbook, so any &lt;v&gt; tags that were injected by a previous postProcessBytes call are
  /// lost. By passing the pre-save file state here we can recover those values and re-inject
  /// them alongside the current sheet's freshly calculated values.
  static List<int> postProcessBytes(
    List<int> bytes,
    Map<String, String> formulaValues, {
    List<int>? previousBytes,
  }) {
    try {
      // Build a merged registry:
      //  1. Start from ALL <f>/<v> pairs that existed in the previous file state.
      //     These are the values postProcessBytes injected on prior iterations but that
      //     excel.save() then stripped when the next sheet was appended.
      //  2. Overlay with the freshly calculated values for the current sheet.
      //     Current values always win so the final monthly-summary re-write can
      //     correctly override the stale placeholder zeros from earlier passes.
      final Map<String, String> mergedValues = {};
      if (previousBytes != null && previousBytes.isNotEmpty) {
        mergedValues.addAll(_extractAllFormulaValues(previousBytes));
      }
      mergedValues.addAll(formulaValues);

      final archive = ZipDecoder().decodeBytes(bytes);
      
      ArchiveFile? workbookXmlFile;
      ArchiveFile? relsFile;
      for (var file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          workbookXmlFile = file;
        } else if (file.name == 'xl/_rels/workbook.xml.rels') {
          relsFile = file;
        }
      }
      if (workbookXmlFile == null || relsFile == null) return bytes;
      
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

      // Sort sheets inside xl/workbook.xml
      var xmlContent = utf8.decode(workbookXmlFile.content);
      var sheetsMatch = RegExp(r'<sheets>(.*?)</sheets>').firstMatch(xmlContent);
      if (sheetsMatch == null) return bytes;

      var sheetsInner = sheetsMatch.group(1)!;
      var sheetRegex = RegExp(r'(<sheet\s+[^>]*name="([^"]+)"[^>]*>)');
      var matches = sheetRegex.allMatches(sheetsInner).toList();

      matches.sort((m1, m2) {
        var name1 = m1.group(2)!;
        var name2 = m2.group(2)!;
        return _compareSheetNames(name1, name2);
      });

      var sortedSheetsStr = matches.map((m) => m.group(1)!).join('');
      var newXmlContent = xmlContent.replaceFirst(sheetsInner, sortedSheetsStr);
      var newWorkbookContent = utf8.encode(newXmlContent);

      final newArchive = Archive();
      for (final file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          newArchive.addFile(ArchiveFile('xl/workbook.xml', newWorkbookContent.length, newWorkbookContent));
        } else {
          final sheetName = targetToSheetName[file.name];
          if (sheetName != null) {
            final xmlStr = utf8.decode(file.content);
            final sheetDoc = XmlDocument.parse(xmlStr);
            bool modified = false;
            
            for (final c in sheetDoc.findAllElements('c')) {
              final cellRef = c.getAttribute('r');
              if (cellRef == null) continue;

              XmlElement? f;
              for (var child in c.children) {
                if (child is XmlElement && child.name.local == 'f') {
                  f = child;
                  break;
                }
              }
              if (f != null) {
                final lookupKey = "$sheetName!$cellRef";
                final calculatedVal = mergedValues[lookupKey];
                if (calculatedVal != null) {
                  XmlElement? v;
                  for (var child in c.children) {
                    if (child is XmlElement && child.name.local == 'v') {
                      v = child;
                      break;
                    }
                  }
                  if (v == null) {
                    v = XmlElement(XmlName('v'));
                    c.children.add(v);
                  }
                  v.innerText = calculatedVal;
                  modified = true;
                }
              }
            }
            if (modified) {
              final newContent = utf8.encode(sheetDoc.toXmlString());
              newArchive.addFile(ArchiveFile(file.name, newContent.length, newContent));
            } else {
              newArchive.addFile(file);
            }
          } else {
            newArchive.addFile(file);
          }
        }
      }

      return ZipEncoder().encode(newArchive) ?? bytes;
    } catch (e, stack) {
      debugPrint("ExcelBinaryHelper Error: $e");
      debugPrint(stack.toString());
      return bytes;
    }
  }

  /// Walks every worksheet in [bytes] and returns a map of
  /// `"SheetName!CellRef" → cachedValue` for every cell that has both
  /// a `<f>` formula element and a `<v>` cached-value element.
  /// Used to recover pre-existing injected values before excel.save() strips them.
  static Map<String, String> _extractAllFormulaValues(List<int> bytes) {
    final Map<String, String> result = {};
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? workbookFile;
      ArchiveFile? relsFile;
      for (final f in archive.files) {
        if (f.name == 'xl/workbook.xml') workbookFile = f;
        if (f.name == 'xl/_rels/workbook.xml.rels') relsFile = f;
      }
      if (workbookFile == null || relsFile == null) return result;

      final wbDoc = XmlDocument.parse(utf8.decode(workbookFile.content));
      final relsDoc = XmlDocument.parse(utf8.decode(relsFile.content));

      final Map<String, String> rIdToSheetName = {};
      for (final sheet in wbDoc.findAllElements('sheet')) {
        final name = sheet.getAttribute('name');
        final rId = sheet.getAttribute('r:id');
        if (name != null && rId != null) rIdToSheetName[rId] = name;
      }

      final Map<String, String> targetToSheetName = {};
      for (final rel in relsDoc.findAllElements('Relationship')) {
        final rId = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (rId != null && target != null) {
          final sheetName = rIdToSheetName[rId];
          if (sheetName != null) targetToSheetName['xl/$target'] = sheetName;
        }
      }

      for (final f in archive.files) {
        final sheetName = targetToSheetName[f.name];
        if (sheetName == null) continue;

        final sheetDoc = XmlDocument.parse(utf8.decode(f.content));
        for (final c in sheetDoc.findAllElements('c')) {
          final cellRef = c.getAttribute('r');
          if (cellRef == null) continue;

          XmlElement? fElem;
          XmlElement? vElem;
          for (var child in c.children) {
            if (child is XmlElement && child.name.local == 'f') fElem = child;
            if (child is XmlElement && child.name.local == 'v') vElem = child;
          }
          // Only capture cells that have both a formula AND a non-empty cached value.
          if (fElem != null && vElem != null && vElem.innerText.isNotEmpty) {
            result['$sheetName!$cellRef'] = vElem.innerText;
          }
        }
      }
    } catch (e) {
      debugPrint('ExcelBinaryHelper._extractAllFormulaValues Error: $e');
    }
    return result;
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
