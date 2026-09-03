import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorysync/main.dart';
import 'package:inventorysync/models/inventory_item.dart';
import 'package:inventorysync/providers/inventory_provider.dart';
import 'package:inventorysync/services/sync_manager.dart';
import 'package:inventorysync/widgets/inventory_item_card.dart';
import 'package:inventorysync/widgets/sync_status.dart';

import 'inventory_notifier_test.dart';

void main() {
  group('Widget Tests with Riverpod', () {
    late FakeLocalStorageService storage;
    late FakeSyncManager sync;

    setUp(() {
      storage = FakeLocalStorageService();
      sync = FakeSyncManager();
    });

    tearDown(() {
      sync.dispose();
    });

    testWidgets('renders Inventory Sync app with status and items', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            syncManagerProvider.overrideWithValue(sync),
          ],
          child: const InventorySyncApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inventory Sync'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Quantity: 10'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('tapping plus button increments quantity in UI', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            syncManagerProvider.overrideWithValue(sync),
          ],
          child: const InventorySyncApp(),
        ),
      );
      await tester.pumpAndSettle();

      final plusBtn = find.byIcon(Icons.add);
      expect(plusBtn, findsOneWidget);

      await tester.tap(plusBtn);
      await tester.pumpAndSettle();

      expect(find.text('Quantity: 11'), findsOneWidget);
    });

    testWidgets('SyncStatusBadge displays Local Network Only and Offline states', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SyncStatusBadge(
              syncState: SyncState.localNetworkOnly,
              queuedCount: 2,
            ),
          ),
        ),
      );

      expect(find.text('Local Network Only'), findsOneWidget);
      expect(find.text('2 queued'), findsOneWidget);
    });

    testWidgets('InventoryItemCard disables minus button when quantity is zero', (WidgetTester tester) async {
      var decremented = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryItemCard(
              item: const InventoryItem(id: 'item-zero', name: 'Zero Stock', quantity: 0),
              onIncrement: () {},
              onDecrement: () => decremented = true,
            ),
          ),
        ),
      );

      expect(find.text('Zero Stock'), findsOneWidget);
      expect(find.text('Quantity: 0'), findsOneWidget);

      final minusBtn = tester.widget<OutlinedButton>(find.widgetWithIcon(OutlinedButton, Icons.remove));
      expect(minusBtn.onPressed, isNull);
      expect(decremented, isFalse);
    });
  });
}
