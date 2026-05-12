import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'platform_check.dart';
import 'web_downloader.dart';

class InvokerService {
  /// Replicates Invoker.call from JS
  static Future<void> call(String number) async {
    debugPrint("Invoker: Call with number $number");
    String urlStr = 'tel:$number';
    if (isIOS()) {
      urlStr = 'telprompt:$number';
    }
    final Uri url = Uri.parse(urlStr);
    try {
      await launchUrl(url);
    } catch (e) {
      debugPrint("Invoker: Call URL open fail for $urlStr with err $e");
    }
  }

  /// Replicates Invoker.text from JS
  static Future<void> text(String number) async {
    debugPrint("Invoker: sms with number $number");
    final Uri url = Uri.parse('sms:$number');
    try {
      await launchUrl(url);
    } catch (e) {
      debugPrint("Invoker: Text URL open fail for $url with err $e");
    }
  }

  /// Replicates Invoker.whatsapp from JS
  static Future<void> whatsapp(String number) async {
    debugPrint("Invoker: whatsapp with number $number");
    // Clean number: remove non-digits
    final cleanNumber = number.replaceAll(RegExp(r'\D'), '');
    final Uri url = Uri.parse("whatsapp://send?phone=$cleanNumber");
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        // Fallback to web link
        final webUrl = Uri.parse("https://wa.me/$cleanNumber");
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Invoker: WhatsApp URL open fail with err $e");
    }
  }

  /// Replicates Invoker.open from JS (using open_filex)
  static Future<void> open(String path) async {
    if (kIsWeb) {
      debugPrint("Invoker: Web open/download: $path");
      if (path.startsWith('http')) {
        await launchUrl(Uri.parse(path));
      } else if (path.startsWith('data:') || path.contains(';base64,')) {
        // Handle data URI with optional filename separated by |
        final parts = path.split('|');
        final data = parts[0];
        final fileName = parts.length > 1 ? parts[1] : "report.xlsx";
        downloadWebData(fileName, data);
      } else if (path.length > 200) {
        // Handle raw base64 data
        final data = "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$path";
        downloadWebData("report.xlsx", data);
      } else {
        // Trigger a download for the path/filename on Web
        downloadWebData(path, "");
      }
      return;
    }

    if (!path.startsWith('http') && !path.startsWith('file')) {
      if (!path.contains('/') && !path.contains('\\')) {
        debugPrint("Invoker: Full path is required for $path");
      }
    }

    // open_filex on Linux/Android/iOS expects a raw path, not a file:// URI.
    String finalPath = path;
    if (finalPath.startsWith('file://')) {
      finalPath = finalPath.replaceFirst('file://', '');
    }

    debugPrint("Invoker: opening path: $finalPath");
    try {
      final result = await OpenFilex.open(finalPath);
      if (result.type != ResultType.done) {
        debugPrint("Invoker: URL open fail for $finalPath with err ${result.message}");
      }
    } catch (e) {
      debugPrint("Invoker: Open fail for $finalPath with err $e");
    }
  }

  /// Replicates Invoker.share from JS (using share_plus)
  static Future<void> share(String filePath) async {
    debugPrint("Invoker: share file $filePath");
    if (filePath.isEmpty) return;
    
    try {
      // In JS: url: "file://" + filepath
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(filePath)], subject: "Share File");
    } catch (e) {
      debugPrint("Invoker: Share fail for $filePath with err $e");
    }
  }
}
