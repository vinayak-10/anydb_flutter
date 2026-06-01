import 'package:flutter/material.dart';

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionButtonText;
  final VoidCallback? onActionButtonPressed;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionButtonText,
    this.onActionButtonPressed,
  });

  /// Factory for Archived view empty state
  factory EmptyStateView.archived() {
    return const EmptyStateView(
      icon: Icons.inventory_2_outlined,
      title: "No Archives Yet",
      subtitle: "Archive old records to keep your active dashboard clean and speedy.",
    );
  }

  /// Factory for Deleted view empty state
  factory EmptyStateView.deleted() {
    return const EmptyStateView(
      icon: Icons.delete_sweep_outlined,
      title: "Clean Slate",
      subtitle: "Deleted files stay here for 72 hours before being permanently purged.",
    );
  }

  /// Factory for empty search results
  factory EmptyStateView.searchEmpty() {
    return const EmptyStateView(
      icon: Icons.search_off_outlined,
      title: "No Matching Records",
      subtitle: "Double check your spelling or clear active search query filters.",
    );
  }

  /// Factory for empty active records (e.g. fresh database tab)
  factory EmptyStateView.active({required VoidCallback onCreateFirst}) {
    return EmptyStateView(
      icon: Icons.assignment_outlined,
      title: "Empty Database",
      subtitle: "There are no active records in this database yet. Tap below to create your first record!",
      actionButtonText: "Create First Record",
      onActionButtonPressed: onCreateFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF6B1524).withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: const Color(0xFF6B1524)),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                fontFamily: 'Outfit',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionButtonText != null && onActionButtonPressed != null) ...[
              const SizedBox(height: 28),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B1524),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: onActionButtonPressed,
                icon: const Icon(Icons.add, size: 18),
                label: Text(actionButtonText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
