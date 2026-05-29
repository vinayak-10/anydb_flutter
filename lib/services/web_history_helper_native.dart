void clearUrlFragment() {
  // No-op on native platforms
}

/// No-op on native – URL navigation is handled by launchUrl on mobile/desktop.
void navigateTo(String url) {}

void openPopup(String url, String title, int width, int height) {}

void handleWebOauthCallback() {}

void registerWebMessageListener(void Function(String fragment) callback) {}

