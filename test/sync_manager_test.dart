import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorysync/models/inventory_item.dart';
import 'package:inventorysync/models/sync_message.dart';
import 'package:inventorysync/services/local_storage_service.dart';
import 'package:inventorysync/services/mqtt_service.dart';
import 'package:inventorysync/services/sync_manager.dart';
import 'package:inventorysync/services/udp_service.dart';

class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> currentResults = [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => currentResults;

  void emit(List<ConnectivityResult> results) {
    currentResults = results;
    _controller.add(results);
  }

  void dispose() {
    _controller.close();
  }
}

class FakeMqttService implements MqttService {
  final _msgController = StreamController<String>.broadcast();
  final _connController = StreamController<bool>.broadcast();
  bool connected = false;
  bool shouldFailPublish = false;
  List<String> published = [];

  @override
  Stream<String> get messageStream => _msgController.stream;

  @override
  Stream<bool> get connectionStream => _connController.stream;

  @override
  bool get isConnected => connected;

  @override
  String get topic => 'inventory-sync/warehouse-main';

  @override
  void configure({required String deviceId, required String roomId}) {}

  @override
  Future<bool> connect({bool force = false}) async {
    connected = true;
    _connController.add(true);
    return true;
  }

  @override
  bool publish(String payload, {String? targetTopic}) {
    if (!connected || shouldFailPublish) return false;
    published.add(payload);
    return true;
  }

  @override
  void updateRoom(String newRoomId) {}

  @override
  void disconnect() {
    connected = false;
    _connController.add(false);
  }

  @override
  void dispose() {
    _msgController.close();
    _connController.close();
  }

  void simulateIncoming(String payload) {
    _msgController.add(payload);
  }
}

class FakeUdpService implements UdpService {
  final _msgController = StreamController<String>.broadcast();
  bool running = false;
  List<String> broadcasted = [];

  @override
  int get port => 4040;

  @override
  Stream<String> get messageStream => _msgController.stream;

  @override
  bool get isRunning => running;

  @override
  Future<bool> start() async {
    running = true;
    return true;
  }

  @override
  Future<bool> broadcast(String message) async {
    broadcasted.add(message);
    return true;
  }

  @override
  void stop() {
    running = false;
  }

  @override
  void dispose() {
    _msgController.close();
  }

  void simulateIncoming(String payload) {
    _msgController.add(payload);
  }
}

class FakeLocalStorageService implements LocalStorageService {
  final Map<String, InventoryItem> items = {
    'item-1': const InventoryItem(id: 'item-1', name: 'Laptop', quantity: 10),
  };
  final List<SyncMessage> queue = [];
  final Set<String> processed = {};

  @override
  Future<void> init() async {}

  @override
  List<InventoryItem> getInventoryItems() {
    final list = items.values.toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

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
  String getDeviceId() => 'test-device-1';

  @override
  String getRoomId() => 'warehouse-main';

  @override
  Future<void> setRoomId(String roomId) async {}

  String themeMode = 'system';

  @override
  String getThemeMode() => themeMode;

  @override
  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncManager Tests', () {
    late FakeMqttService mqtt;
    late FakeUdpService udp;
    late FakeLocalStorageService storage;
    late FakeConnectivity connectivity;
    late SyncManager syncManager;

    setUp(() async {
      mqtt = FakeMqttService();
      udp = FakeUdpService();
      storage = FakeLocalStorageService();
      connectivity = FakeConnectivity();

      syncManager = SyncManager(
        mqttService: mqtt,
        udpService: udp,
        localStorage: storage,
        connectivity: connectivity,
      );

      await syncManager.init();
    });

    tearDown(() {
      syncManager.dispose();
      connectivity.dispose();
    });

    test('ignores self-generated updates', () async {
      const msg = SyncMessage(
        messageId: 'msg-self',
        deviceId: 'test-device-1', // same device
        itemId: 'item-1',
        delta: 1,
        quantity: 50,
        timestamp: 1000,
      );

      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));

      expect(storage.getItem('item-1')?.quantity, 10); // unchanged
    });

    test('applies valid peer update with delta and marks processed', () async {
      const msg = SyncMessage(
        messageId: 'msg-peer-1',
        deviceId: 'test-device-2', // other device
        itemId: 'item-1',
        delta: 4,
        quantity: 14,
        timestamp: 1000,
      );

      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));

      // 10 + 4 = 14
      expect(storage.getItem('item-1')?.quantity, 14);
      expect(storage.isMessageProcessed('msg-peer-1'), isTrue);
    });

    test('ignores duplicate messages', () async {
      const msg = SyncMessage(
        messageId: 'msg-dup-1',
        deviceId: 'test-device-2',
        itemId: 'item-1',
        delta: 2,
        quantity: 12,
        timestamp: 1000,
      );

      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));
      expect(storage.getItem('item-1')?.quantity, 12);

      // Modify local item directly
      storage.items['item-1'] = storage.items['item-1']!.copyWith(quantity: 33);

      // Resend same message
      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));

      // Should still be 33 because dup was ignored
      expect(storage.getItem('item-1')?.quantity, 33);
    });

    test('queues offline changes and flushes upon connectivity restoration', () async {
      // 1. Simulate turning internet OFF
      mqtt.disconnect();
      connectivity.emit([ConnectivityResult.none]);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(syncManager.currentState, SyncState.offline);

      // 2. Make an offline inventory change: 10 -> 11 (delta +1)
      final item = storage.getItem('item-1')!.copyWith(quantity: 11);
      await syncManager.sendInventoryUpdate(item, delta: 1);

      expect(storage.getItem('item-1')?.quantity, 11);
      expect(storage.getQueuedCount(), 1);
      expect(mqtt.published.length, 0);

      // 3. Simulate turning internet back ON
      connectivity.emit([ConnectivityResult.wifi]);
      await Future.delayed(const Duration(milliseconds: 50));

      // 4. Verify MQTT connected and offline queue flushed
      expect(mqtt.isConnected, isTrue);
      expect(mqtt.published.length, 1);
      expect(storage.getQueuedCount(), 0);
    });

    test('retains queued messages if MQTT publish fails', () async {
      // 1. Simulate turning internet OFF
      mqtt.disconnect();
      connectivity.emit([ConnectivityResult.none]);
      await Future.delayed(const Duration(milliseconds: 30));

      // 2. Make an offline inventory change
      final item = storage.getItem('item-1')!.copyWith(quantity: 15);
      await syncManager.sendInventoryUpdate(item, delta: 5);
      expect(storage.getQueuedCount(), 1);

      // 3. Simulate publish failure on reconnect
      mqtt.shouldFailPublish = true;
      connectivity.emit([ConnectivityResult.wifi]);
      await Future.delayed(const Duration(milliseconds: 50));

      // 4. Verify message was not deleted because publish failed
      expect(storage.getQueuedCount(), 1);
    });

    test('flushes existing queued messages upon startup connection (app restart)', () async {
      // 1. Pre-seed queue with a message (simulating previous offline session)
      const existingMsg = SyncMessage(
        messageId: 'msg-offline-1',
        deviceId: 'test-device-1',
        itemId: 'item-1',
        delta: 2,
        quantity: 12,
        timestamp: 500,
      );
      storage.queue.add(existingMsg);
      expect(storage.getQueuedCount(), 1);

      // 2. Initialize new SyncManager (simulating app start)
      final newSyncManager = SyncManager(
        mqttService: mqtt,
        udpService: udp,
        localStorage: storage,
        connectivity: connectivity,
      );

      await newSyncManager.init();
      await Future.delayed(const Duration(milliseconds: 50));

      // 3. Verify queued message was flushed and removed
      expect(mqtt.published.length, 1);
      expect(storage.getQueuedCount(), 0);

      newSyncManager.dispose();
    });

    test('reconciliation of concurrent offline/online edits converges correctly', () async {
      // Start with item-3: Mouse = 6
      storage.items['item-3'] = const InventoryItem(id: 'item-3', name: 'Mouse', quantity: 6);

      // Device A is offline and increments Mouse: 6 + 1 = 7 (delta: +1)
      mqtt.disconnect();
      connectivity.emit([ConnectivityResult.none]);
      await Future.delayed(const Duration(milliseconds: 30));

      final itemA = storage.getItem('item-3')!.copyWith(quantity: 7);
      await syncManager.sendInventoryUpdate(itemA, delta: 1);
      expect(storage.getItem('item-3')?.quantity, 7);

      // Meanwhile Device B (simulated incoming) performed Mouse +1 (delta: +1)
      // When Device A receives Device B's change:
      const msgFromB = SyncMessage(
        messageId: 'msg-b-1',
        deviceId: 'test-device-2',
        itemId: 'item-3',
        delta: 1,
        quantity: 7,
        timestamp: 1001,
      );
      mqtt.simulateIncoming(msgFromB.toJson());
      await Future.delayed(const Duration(milliseconds: 30));

      // Device A applies Device B's delta (+1): 7 + 1 = 8
      expect(storage.getItem('item-3')?.quantity, 8);

      // Now Device A reconnects and flushes its offline queued update (delta: +1)
      connectivity.emit([ConnectivityResult.wifi]);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(storage.getQueuedCount(), 0);
      expect(mqtt.published.length, 1);
      final publishedMsg = SyncMessage.fromJson(mqtt.published.first);
      expect(publishedMsg.delta, 1);
      expect(publishedMsg.itemId, 'item-3');
    });
  });
}
