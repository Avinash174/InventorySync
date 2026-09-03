import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorysync/models/inventory_item.dart';
import 'package:inventorysync/models/sync_message.dart';
import 'package:inventorysync/providers/inventory_provider.dart';
import 'package:inventorysync/services/local_storage_service.dart';
import 'package:inventorysync/services/mqtt_service.dart';
import 'package:inventorysync/services/sync_manager.dart';
import 'package:inventorysync/services/udp_service.dart';

class FakeLocalStorageService implements LocalStorageService {
  final Map<String, InventoryItem> items = {
    'item-1': const InventoryItem(id: 'item-1', name: 'Laptop', quantity: 10),
  };
  final List<SyncMessage> queue = [];
  final Set<String> processed = {};

  @override
  Future<void> init() async {}

  @override
  List<InventoryItem> getInventoryItems() => items.values.toList();

  @override
  InventoryItem? getItem(String id) => items[id];

  @override
  Future<void> saveItem(InventoryItem item) async {
    items[item.id] = item;
  }

  @override
  List<SyncMessage> getQueuedMessages() => List.from(queue);

  @override
  int getQueuedCount() => queue.length;

  @override
  Future<void> queueMessage(SyncMessage message) async {
    queue.add(message);
  }

  @override
  Future<void> removeQueuedMessage(String messageId) async {
    queue.removeWhere((e) => e.messageId == messageId);
  }

  @override
  bool isMessageProcessed(String messageId) => processed.contains(messageId);

  @override
  void markMessageProcessed(String messageId) {
    processed.add(messageId);
  }

  @override
  String getDeviceId() => 'test-device';

  @override
  String getRoomId() => 'warehouse-main';

  @override
  Future<void> setRoomId(String roomId) async {}
}

class FakeSyncManager implements SyncManager {
  SyncState state = SyncState.online;
  final _stateController = StreamController<SyncState>.broadcast();
  final _updateController = StreamController<SyncMessage>.broadcast();
  final List<InventoryItem> sentUpdates = [];

  @override
  SyncState get currentState => state;

  @override
  Stream<SyncState> get stateStream => _stateController.stream;

  @override
  Stream<SyncMessage> get incomingUpdates => _updateController.stream;

  @override
  String get deviceId => 'test-device';

  @override
  String get roomId => 'warehouse-main';

  @override
  MqttService get mqttService => throw UnimplementedError();

  @override
  UdpService get udpService => throw UnimplementedError();

  @override
  LocalStorageService get localStorage => throw UnimplementedError();

  @override
  Connectivity get connectivity => throw UnimplementedError();

  @override
  Future<void> init() async {}

  @override
  Future<void> sendInventoryUpdate(InventoryItem item) async {
    sentUpdates.add(item);
  }

  @override
  Future<void> reconnect() async {}

  @override
  Future<void> updateRoom(String newRoomId) async {}

  @override
  void dispose() {
    _stateController.close();
    _updateController.close();
  }

  void emitRemoteUpdate(SyncMessage msg) {
    _updateController.add(msg);
  }
}

void main() {
  group('InventoryNotifier Riverpod Tests', () {
    late FakeLocalStorageService storage;
    late FakeSyncManager sync;
    late ProviderContainer container;

    setUp(() {
      storage = FakeLocalStorageService();
      sync = FakeSyncManager();
      container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          syncManagerProvider.overrideWithValue(sync),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      sync.dispose();
    });

    test('initial state loads inventory items from LocalStorageService', () {
      final items = container.read(inventoryProvider);
      expect(items.length, 1);
      expect(items.first.name, 'Laptop');
      expect(items.first.quantity, 10);
    });

    test('increment increases quantity and dispatches update via SyncManager', () async {
      await container.read(inventoryProvider.notifier).increment('item-1');

      final items = container.read(inventoryProvider);
      expect(items.first.quantity, 11);
      expect(sync.sentUpdates.last.quantity, 11);
    });

    test('decrement decreases quantity and prevents negative quantity', () async {
      await container.read(inventoryProvider.notifier).decrement('item-1');

      final items = container.read(inventoryProvider);
      expect(items.first.quantity, 9);
      expect(sync.sentUpdates.last.quantity, 9);
    });

    test('remote updates trigger automatic state refresh in notifier', () async {
      // Subscribe to provider
      container.read(inventoryProvider);

      storage.items['item-1'] = const InventoryItem(id: 'item-1', name: 'Laptop', quantity: 99);
      sync.emitRemoteUpdate(const SyncMessage(
        messageId: 'msg-remote',
        deviceId: 'other-device',
        itemId: 'item-1',
        quantity: 99,
        timestamp: 1000,
      ));

      await Future.delayed(const Duration(milliseconds: 30));

      final items = container.read(inventoryProvider);
      expect(items.first.quantity, 99);
    });
  });
}
