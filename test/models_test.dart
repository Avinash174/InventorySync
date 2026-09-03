import 'package:flutter_test/flutter_test.dart';
import 'package:inventorysync/models/inventory_item.dart';
import 'package:inventorysync/models/sync_message.dart';
import 'package:inventorysync/services/sync_manager.dart';

void main() {
  group('InventoryItem Model Tests', () {
    test('creates and serializes InventoryItem correctly', () {
      const item = InventoryItem(
        id: 'item-1',
        name: 'Laptop',
        quantity: 10,
      );

      expect(item.id, 'item-1');
      expect(item.name, 'Laptop');
      expect(item.quantity, 10);

      final map = item.toMap();
      final fromMap = InventoryItem.fromMap(map);

      expect(fromMap, equals(item));
    });

    test('copyWith updates fields and prevents negative quantity', () {
      const item = InventoryItem(
        id: 'item-1',
        name: 'Laptop',
        quantity: 5,
      );

      final updated = item.copyWith(quantity: 8);
      expect(updated.quantity, 8);
      expect(updated.name, 'Laptop');

      final negativeClamped = item.copyWith(quantity: -3);
      expect(negativeClamped.quantity, 0);
    });

    test('asserts non-negative quantity in constructor', () {
      expect(
        () => InventoryItem(
          id: 'item-1',
          name: 'Laptop',
          quantity: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SyncMessage Model Tests', () {
    test('validates valid sync message', () {
      const message = SyncMessage(
        messageId: 'msg-123',
        deviceId: 'dev-456',
        itemId: 'item-1',
        quantity: 12,
        timestamp: 1756900000000,
        roomId: 'warehouse-main',
      );

      expect(message.isValid, isTrue);

      final jsonString = message.toJson();
      final parsed = SyncMessage.fromJson(jsonString);

      expect(parsed, equals(message));
      expect(parsed.quantity, 12);
    });

    test('detects invalid sync message', () {
      const invalid = SyncMessage(
        messageId: '',
        deviceId: 'dev-456',
        itemId: 'item-1',
        quantity: 12,
        timestamp: 1756900000000,
      );

      expect(invalid.isValid, isFalse);
    });
  });

  group('SyncState Enum Tests', () {
    test('provides correct label and descriptions', () {
      expect(SyncState.online.label, '🟢 Online');
      expect(SyncState.localNetworkOnly.label, '🟡 Local Network Only');
      expect(SyncState.offline.label, '🔴 Offline');
    });
  });
}
