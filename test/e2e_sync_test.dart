import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorysync/models/inventory_item.dart';
import 'package:inventorysync/models/sync_message.dart';
import 'package:inventorysync/services/local_storage_service.dart';
import 'package:inventorysync/services/mqtt_service.dart';
import 'package:inventorysync/services/sync_manager.dart';
import 'package:inventorysync/services/udp_service.dart';

class MockConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> current = [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  void setConnectivity(List<ConnectivityResult> results) {
    current = results;
    _controller.add(results);
  }

  void dispose() => _controller.close();
}

class MockMqttTransport implements MqttService {
  final _msgController = StreamController<String>.broadcast();
  final _connController = StreamController<bool>.broadcast();
  bool _connected = false;
  final List<String> publishedPayloads = [];

  @override
  Stream<String> get messageStream => _msgController.stream;

  @override
  Stream<bool> get connectionStream => _connController.stream;

  @override
  bool get isConnected => _connected;

  @override
  String get topic => 'inventory-sync/warehouse-main';

  @override
  void configure({required String deviceId, required String roomId}) {}

  bool shouldFailConnect = false;

  @override
  Future<bool> connect({bool force = false}) async {
    if (shouldFailConnect) {
      _connected = false;
      _connController.add(false);
      return false;
    }
    _connected = true;
    _connController.add(true);
    return true;
  }

  @override
  bool publish(String payload, {String? targetTopic}) {
    if (!_connected) return false;
    publishedPayloads.add(payload);
    return true;
  }

  @override
  void updateRoom(String newRoomId) {}

  @override
  void disconnect() {
    _connected = false;
    _connController.add(false);
  }

  @override
  void dispose() {
    _msgController.close();
    _connController.close();
  }

  void receiveFromBroker(String payload) {
    _msgController.add(payload);
  }
}

class MockUdpTransport implements UdpService {
  final _msgController = StreamController<String>.broadcast();
  bool _running = false;
  final List<String> broadcastPayloads = [];

  @override
  int get port => 4040;

  @override
  Stream<String> get messageStream => _msgController.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<bool> start() async {
    _running = true;
    return true;
  }

  @override
  Future<bool> broadcast(String message) async {
    broadcastPayloads.add(message);
    return true;
  }

  @override
  void stop() {
    _running = false;
  }

  @override
  void dispose() {
    _msgController.close();
  }

  void receiveDatagram(String payload) {
    _msgController.add(payload);
  }
}

class InMemoryLocalStorage implements LocalStorageService {
  final String deviceId;
  final Map<String, InventoryItem> inventory = {
    'item-1': const InventoryItem(id: 'item-1', name: 'Laptop', quantity: 10),
    'item-2': const InventoryItem(id: 'item-2', name: 'Keyboard', quantity: 7),
    'item-3': const InventoryItem(id: 'item-3', name: 'Mouse', quantity: 6),
    'item-4': const InventoryItem(id: 'item-4', name: 'Monitor', quantity: 4),
  };
  final Map<String, SyncMessage> queue = {};
  final Set<String> processed = {};

  InMemoryLocalStorage({this.deviceId = 'device-A'});

  @override
  Future<void> init() async {}

  @override
  List<InventoryItem> getInventoryItems() {
    final list = inventory.values.toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  @override
  InventoryItem? getItem(String id) => inventory[id];

  @override
  Future<void> saveItem(InventoryItem item) async {
    inventory[item.id] = item;
  }

  @override
  List<SyncMessage> getQueuedMessages() {
    final list = queue.values.toList();
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  @override
  int getQueuedCount() => queue.length;

  @override
  Future<void> queueMessage(SyncMessage message) async {
    queue[message.messageId] = message;
  }

  @override
  Future<void> removeQueuedMessage(String messageId) async {
    queue.remove(messageId);
  }

  @override
  bool isMessageProcessed(String messageId) => processed.contains(messageId);

  @override
  void markMessageProcessed(String messageId) {
    processed.add(messageId);
  }

  @override
  String getDeviceId() => deviceId;

  @override
  String getRoomId() => 'warehouse-main';

  @override
  Future<void> setRoomId(String roomId) async {}

  @override
  String getThemeMode() => 'system';

  @override
  Future<void> setThemeMode(String themeMode) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End Two-Device Sync Matrix', () {
    test('TEST 1 & 2: Two-way real-time MQTT sync between Device A and Device B', () async {
      // Setup Device A
      final storageA = InMemoryLocalStorage(deviceId: 'device-A');
      final mqttA = MockMqttTransport();
      final udpA = MockUdpTransport();
      final connA = MockConnectivity();
      final syncA = SyncManager(mqttService: mqttA, udpService: udpA, localStorage: storageA, connectivity: connA);
      await syncA.init();

      // Setup Device B
      final storageB = InMemoryLocalStorage(deviceId: 'device-B');
      final mqttB = MockMqttTransport();
      final udpB = MockUdpTransport();
      final connB = MockConnectivity();
      final syncB = SyncManager(mqttService: mqttB, udpService: udpB, localStorage: storageB, connectivity: connB);
      await syncB.init();

      // Initial checks: Mouse = 6 on both
      expect(storageA.getItem('item-3')?.quantity, 6);
      expect(storageB.getItem('item-3')?.quantity, 6);

      // Step 1: Device A increments Mouse: 6 -> 7
      final updatedA = storageA.getItem('item-3')!.copyWith(quantity: 7);
      await syncA.sendInventoryUpdate(updatedA, delta: 1);
      expect(storageA.getItem('item-3')?.quantity, 7);
      expect(mqttA.publishedPayloads.length, 1);

      // Simulate Broker routing payload from A to B (and back to A as MQTT echo)
      final payloadA = mqttA.publishedPayloads.first;
      mqttA.receiveFromBroker(payloadA); // Device A receives its own message -> must ignore
      mqttB.receiveFromBroker(payloadA); // Device B receives message -> must apply
      await Future.delayed(const Duration(milliseconds: 30));

      expect(storageA.getItem('item-3')?.quantity, 7); // Unchanged on A (not double incremented)
      expect(storageB.getItem('item-3')?.quantity, 7); // Updated on B to 7

      // Step 2: Device B increments Mouse: 7 -> 8
      final updatedB = storageB.getItem('item-3')!.copyWith(quantity: 8);
      await syncB.sendInventoryUpdate(updatedB, delta: 1);
      expect(storageB.getItem('item-3')?.quantity, 8);
      expect(mqttB.publishedPayloads.length, 1);

      // Simulate Broker routing payload from B to A
      final payloadB = mqttB.publishedPayloads.first;
      mqttB.receiveFromBroker(payloadB); // Device B receives its own message -> must ignore
      mqttA.receiveFromBroker(payloadB); // Device A receives message -> must apply
      await Future.delayed(const Duration(milliseconds: 30));

      expect(storageA.getItem('item-3')?.quantity, 8); // Updated on A to 8
      expect(storageB.getItem('item-3')?.quantity, 8); // Remains 8 on B

      syncA.dispose();
      syncB.dispose();
      connA.dispose();
      connB.dispose();
    });

    test('TEST 5 & 6: Two-way UDP sync on same Wi-Fi with Internet OFF', () async {
      // Setup Device A with Wi-Fi only (no MQTT)
      final storageA = InMemoryLocalStorage(deviceId: 'device-A');
      final mqttA = MockMqttTransport();
      final udpA = MockUdpTransport();
      final connA = MockConnectivity();
      final syncA = SyncManager(mqttService: mqttA, udpService: udpA, localStorage: storageA, connectivity: connA);
      await syncA.init();
      mqttA.shouldFailConnect = true;
      mqttA.disconnect();
      connA.setConnectivity([ConnectivityResult.wifi]);
      await syncA.reconnect(); // will evaluate to localNetworkOnly

      // Setup Device B with Wi-Fi only (no MQTT)
      final storageB = InMemoryLocalStorage(deviceId: 'device-B');
      final mqttB = MockMqttTransport();
      final udpB = MockUdpTransport();
      final connB = MockConnectivity();
      final syncB = SyncManager(mqttService: mqttB, udpService: udpB, localStorage: storageB, connectivity: connB);
      await syncB.init();
      mqttB.shouldFailConnect = true;
      mqttB.disconnect();
      connB.setConnectivity([ConnectivityResult.wifi]);
      await syncB.reconnect(); // will evaluate to localNetworkOnly

      expect(syncA.currentState, SyncState.localNetworkOnly);
      expect(syncB.currentState, SyncState.localNetworkOnly);

      // Step 1: Device A changes Laptop 10 -> 11
      final itemA = storageA.getItem('item-1')!.copyWith(quantity: 11);
      await syncA.sendInventoryUpdate(itemA, delta: 1);

      expect(storageA.getItem('item-1')?.quantity, 11);
      expect(udpA.broadcastPayloads.length, 1);

      // Simulate UDP broadcast on LAN from A to B
      final broadcastPayloadA = udpA.broadcastPayloads.first;
      udpA.receiveDatagram(broadcastPayloadA); // A ignores own message
      udpB.receiveDatagram(broadcastPayloadA); // B receives
      await Future.delayed(const Duration(milliseconds: 30));

      expect(storageB.getItem('item-1')?.quantity, 11);

      // Step 2: Device B changes Laptop 11 -> 12
      final itemB = storageB.getItem('item-1')!.copyWith(quantity: 12);
      await syncB.sendInventoryUpdate(itemB, delta: 1);

      expect(storageB.getItem('item-1')?.quantity, 12);
      expect(udpB.broadcastPayloads.length, 1);

      // Simulate UDP broadcast on LAN from B to A
      final broadcastPayloadB = udpB.broadcastPayloads.first;
      udpB.receiveDatagram(broadcastPayloadB);
      udpA.receiveDatagram(broadcastPayloadB);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(storageA.getItem('item-1')?.quantity, 12);
      expect(storageB.getItem('item-1')?.quantity, 12);

      syncA.dispose();
      syncB.dispose();
      connA.dispose();
      connB.dispose();
    });

    test('TEST 3 & 4: Offline queueing and automatic sync upon reconnect', () async {
      final storageA = InMemoryLocalStorage(deviceId: 'device-A');
      final mqttA = MockMqttTransport();
      final udpA = MockUdpTransport();
      final connA = MockConnectivity();
      final syncA = SyncManager(mqttService: mqttA, udpService: udpA, localStorage: storageA, connectivity: connA);
      await syncA.init();

      final storageB = InMemoryLocalStorage(deviceId: 'device-B');
      final mqttB = MockMqttTransport();
      final udpB = MockUdpTransport();
      final connB = MockConnectivity();
      final syncB = SyncManager(mqttService: mqttB, udpService: udpB, localStorage: storageB, connectivity: connB);
      await syncB.init();

      // Device A goes completely offline
      mqttA.disconnect();
      connA.setConnectivity([ConnectivityResult.none]);
      await Future.delayed(const Duration(milliseconds: 30));
      expect(syncA.currentState, SyncState.offline);

      // Device A performs offline changes: Keyboard 7 -> 9 (delta: +2)
      final offlineItem = storageA.getItem('item-2')!.copyWith(quantity: 9);
      await syncA.sendInventoryUpdate(offlineItem, delta: 2);

      expect(storageA.getItem('item-2')?.quantity, 9);
      expect(storageA.getQueuedCount(), 1);

      // Device A gets network back
      connA.setConnectivity([ConnectivityResult.wifi]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify queue is flushed to MQTT
      expect(mqttA.publishedPayloads.isNotEmpty, isTrue);
      expect(storageA.getQueuedCount(), 0);

      // Device B receives the flushed queue message
      final flushedMsg = mqttA.publishedPayloads.last;
      mqttB.receiveFromBroker(flushedMsg);
      await Future.delayed(const Duration(milliseconds: 30));

      // Device B updates Keyboard: 7 + 2 = 9
      expect(storageB.getItem('item-2')?.quantity, 9);

      syncA.dispose();
      syncB.dispose();
      connA.dispose();
      connB.dispose();
    });
  });
}
