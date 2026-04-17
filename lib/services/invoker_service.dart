import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'platform_check.dart';

class InvokerService {
  static Future<void> call(String number) async {
    String urlStr = 'tel:$number';
    if (isIOS()) {
      urlStr = 'telprompt:$number';
    }
    final Uri url = Uri.parse(urlStr);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  static Future<void> text(String number) async {
    final Uri url = Uri.parse('sms:$number');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  static Future<void> whatsapp(String number) async {
    // WhatsApp URL format can vary, this is a common one
    final Uri url = Uri.parse("whatsapp://send?phone=$number");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      // Fallback to web link if app not installed
      final webUrl = Uri.parse("https://wa.me/$number");
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    }
  }
}
