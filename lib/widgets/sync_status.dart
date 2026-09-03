import 'package:flutter/material.dart';
import '../services/sync_manager.dart';

class SyncStatusBadge extends StatelessWidget {
  final SyncState syncState;
  final int queuedCount;
  final VoidCallback? onTap;

  const SyncStatusBadge({
    super.key,
    required this.syncState,
    this.queuedCount = 0,
    this.onTap,
  });

  Color _getStatusColor() {
    switch (syncState) {
      case SyncState.online:
        return const Color(0xFF10B981); // Green
      case SyncState.localNetworkOnly:
        return const Color(0xFFF59E0B); // Amber / Yellow
      case SyncState.offline:
        return const Color(0xFFEF4444); // Red
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              syncState.label.replaceFirst(RegExp(r'^[^\s]+\s'), ''), // Clean text
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: color,
              ),
            ),
            if (queuedCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$queuedCount queued',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
