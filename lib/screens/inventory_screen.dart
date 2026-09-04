import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/inventory_provider.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/sync_status.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  Future<void> _handleRefresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final syncState = await ref.read(inventoryProvider.notifier).refresh();
    final queued = ref.read(queuedCountProvider);

    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          queued > 0
              ? 'Refreshed: ${syncState.label} ($queued queued)'
              : 'Refreshed: ${syncState.label}',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(inventoryProvider);
    final syncStateAsync = ref.watch(syncStateProvider);
    final syncManager = ref.watch(syncManagerProvider);
    final queuedCount = ref.watch(queuedCountProvider);

    final currentSyncState = syncStateAsync.value ?? syncManager.currentState;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inventory Sync',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect & Refresh',
            onPressed: () => _handleRefresh(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _handleRefresh(context, ref),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SyncStatusBadge(
                syncState: currentSyncState,
                queuedCount: queuedCount,
                onTap: () => _handleRefresh(context, ref),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No inventory items.')),
              )
            else
              ...items.map(
                (item) => InventoryItemCard(
                  key: ValueKey(item.id),
                  item: item,
                  onIncrement: () {
                    ref.read(inventoryProvider.notifier).increment(item.id);
                  },
                  onDecrement: () {
                    ref.read(inventoryProvider.notifier).decrement(item.id);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
