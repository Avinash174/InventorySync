import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/inventory_provider.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/sync_status.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

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
            tooltip: 'Reconnect',
            onPressed: () {
              ref.read(inventoryProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(inventoryProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SyncStatusBadge(
                syncState: currentSyncState,
                queuedCount: queuedCount,
                onTap: () {
                  ref.read(inventoryProvider.notifier).refresh();
                },
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
