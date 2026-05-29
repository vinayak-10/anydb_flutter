import 'dart:html' as html;
import 'dart:async';

void clearUrlFragment() {
  try {
    final String currentUrl = html.window.location.href;
    final String baseUrl = currentUrl.split('#')[0];
    html.window.history.replaceState(null, '', baseUrl);
  } catch (e) {
    // Suppress web platform interop errors
  }
}

/// Navigates the current browser tab to [url].
/// On web this replaces the current page (same tab, no popup).
void navigateTo(String url) {
  try {
    html.window.location.href = url;
  } catch (e) {
    // Suppress
  }
}

/// Opens a centered popup window with the specified URL.
void openPopup(String url, String title, int width, int height) {
  try {
    final left = (html.window.screen!.width! - width) ~/ 2;
    final top = (html.window.screen!.height! - height) ~/ 2;
    html.window.open(
      url,
      title,
      'width=$width,height=$height,top=$top,left=$left,status=no,resizable=yes,scrollbars=yes',
    );
  } catch (e) {
    // Fallback if popup blocker interferes
    html.window.open(url, '_blank');
  }
}

/// Checks if this is a popup callback window and communicates back to opener.
void handleWebOauthCallback() {
  try {
    final opener = html.window.opener;
    final hash = html.window.location.hash;
    if (opener != null && hash.contains('access_token=')) {
      opener.postMessage(hash, html.window.location.origin);
      html.window.close();
    }
  } catch (e) {
    // Suppress
  }
}

StreamSubscription? _messageSub;

/// Registers a listener on the main window to catch fragment callbacks from the popup.
void registerWebMessageListener(void Function(String fragment) callback) {
  try {
    _messageSub?.cancel();
    _messageSub = html.window.onMessage.listen((event) {
      if (event.origin != html.window.location.origin) return;
      final data = event.data;
      if (data is String && data.contains('access_token=')) {
        callback(data);
      }
    });
  } catch (e) {
    // Suppress
  }
}

