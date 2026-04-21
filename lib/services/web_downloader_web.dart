// ignore_for_file: deprecated_member_use
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

void downloadWebData(String fileName, String data) {
  String url;
  if (data.startsWith('data:')) {
    url = data;
  } else {
    final bytes = utf8.encode(data);
    final blob = html.Blob([bytes]);
    url = html.Url.createObjectUrlFromBlob(blob);
  }
  
  html.AnchorElement(href: url)
    ..setAttribute("download", fileName)
    ..click();
    
  if (!data.startsWith('data:')) {
    html.Url.revokeObjectUrl(url);
  }
}
