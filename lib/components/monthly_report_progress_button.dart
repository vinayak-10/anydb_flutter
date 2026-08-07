import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/isolate_worker.dart';
import '../utils/feedback_toast.dart';

class MonthlyReportProgressButton extends ConsumerWidget {
  // ignore: prefer_const_constructors_in_immutables
  MonthlyReportProgressButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskState = ref.watch(monthlyReportTaskProvider);

    if (!taskState.isGenerating) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 400;

    void handleCancel() {
      ref.read(monthlyReportTaskProvider.notifier).cancel();
      FeedbackToast.info(
        context,
        "Monthly report generation cancelled",
      );
    }

    if (isCompact) {
      return Tooltip(
        message: "Generating Monthly Report (Tap to cancel)",
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: handleCancel,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF6B1524)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: handleCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6B1524).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF6B1524).withOpacity(0.3),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF6B1524)),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  "Monthly...",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6B1524),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
