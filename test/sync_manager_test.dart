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

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  void dispose() {
    _controller.close();
  }
}

class FakeMqttService implements MqttService {
  final _msgController = StreamController<String>.broadcast();
  final _connController = StreamController<bool>.broadcast();
  bool connected = false;
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
  Future<bool> connect() async {
    connected = true;
    _connController.add(true);
    return true;
  }

  @override
  bool publish(String payload) {
    if (!connected) return false;
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
  String getDeviceId() => 'test-device-1';

  @override
  String getRoomId() => 'warehouse-main';

  @override
  Future<void> setRoomId(String roomId) async {}
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
        quantity: 50,
        timestamp: 1000,
      );

      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));

      expect(storage.getItem('item-1')?.quantity, 10); // unchanged
    });

    test('applies valid peer update and marks processed', () async {
      const msg = SyncMessage(
        messageId: 'msg-peer-1',
        deviceId: 'test-device-2', // other device
        itemId: 'item-1',
        quantity: 14,
        timestamp: 1000,
      );

      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));

      expect(storage.getItem('item-1')?.quantity, 14);
      expect(storage.isMessageProcessed('msg-peer-1'), isTrue);
    });

    test('ignores duplicate messages', () async {
      const msg = SyncMessage(
        messageId: 'msg-dup-1',
        deviceId: 'test-device-2',
        itemId: 'item-1',
        quantity: 22,
        timestamp: 1000,
      );

      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));
      expect(storage.getItem('item-1')?.quantity, 22);

      // Modify local item directly
      storage.items['item-1'] = storage.items['item-1']!.copyWith(quantity: 33);

      // Resend same message
      mqtt.simulateIncoming(msg.toJson());
      await Future.delayed(const Duration(milliseconds: 30));

      // Should still be 33 because dup was ignored
      expect(storage.getItem('item-1')?.quantity, 33);
    });
  });
}
