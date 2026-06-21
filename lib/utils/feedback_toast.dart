import 'package:flutter/material.dart';

class FeedbackToast {
  /// Displays a floating success toast notification with optional action
  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    _show(
      context,
      message: message,
      isError: false,
      icon: Icons.check_circle_outline,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Displays a floating error toast notification with optional action
  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    _show(
      context,
      message: message,
      isError: true,
      icon: Icons.error_outline,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Displays an undoable success toast notification
  static void undoable(
    BuildContext context,
    String message, {
    required VoidCallback onUndo,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    _show(
      context,
      message: message,
      isError: false,
      icon: Icons.undo,
      actionLabel: "UNDO",
      onAction: onUndo,
      duration: duration,
    );
  }

  /// Displays a retryable error toast notification
  static void retryable(
    BuildContext context,
    String message, {
    required VoidCallback onRetry,
    Duration duration = const Duration(milliseconds: 5000),
  }) {
    _show(
      context,
      message: message,
      isError: true,
      icon: Icons.cloud_off,
      actionLabel: "RETRY",
      onAction: onRetry,
      duration: duration,
    );
  }

  /// Core private SnackBar builder
  static void _show(
    BuildContext context, {
    required String message,
    required bool isError,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    required Duration duration,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();

    final themeColor = isError
        ? const Color(0xFF6B1524)
        : const Color(0xFF6B1524);
    final borderColor = isError
        ? const Color(0xFFE9967A)
        : const Color(0xFFE5C158);
    final iconColor = isError
        ? const Color(0xFFE9967A)
        : const Color(0xFFE5C158);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        content: Container(
          decoration: BoxDecoration(
            color: themeColor,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: borderColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    onAction();
                  },
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
