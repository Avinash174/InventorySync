import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/inventory_item.dart';
import '../services/local_storage_service.dart';
import '../services/mqtt_service.dart';
import '../services/sync_manager.dart';
import '../services/udp_service.dart';

// --- Service Providers ---

final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError('LocalStorageService must be initialized in main()');
});

final mqttServiceProvider = Provider<MqttService>((ref) {
  final service = MqttService();
  ref.onDispose(() => service.dispose());
  return service;
});

final udpServiceProvider = Provider<UdpService>((ref) {
  final service = UdpService();
  ref.onDispose(() => service.dispose());
  return service;
});

final syncManagerProvider = Provider<SyncManager>((ref) {
  throw UnimplementedError('SyncManager must be initialized in main()');
});

// --- State Providers ---

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return syncManager.stateStream;
});

final queuedCountProvider = StateProvider<int>((ref) {
  final localStorage = ref.watch(localStorageServiceProvider);
  return localStorage.getQueuedCount();
});

// --- Inventory Notifier ---

final inventoryProvider =
    NotifierProvider<InventoryNotifier, List<InventoryItem>>(
  InventoryNotifier.new,
);

class InventoryNotifier extends Notifier<List<InventoryItem>> {
  StreamSubscription? _remoteUpdatesSub;
  StreamSubscription? _queueCountSub;

  @override
  List<InventoryItem> build() {
    final localStorage = ref.watch(localStorageServiceProvider);
    final syncManager = ref.watch(syncManagerProvider);

    // Listen to remote changes coming from MQTT or UDP
    _remoteUpdatesSub?.cancel();
    _remoteUpdatesSub = syncManager.incomingUpdates.listen((message) {
      state = localStorage.getInventoryItems();
      ref.read(queuedCountProvider.notifier).state = localStorage.getQueuedCount();
    });

    // Listen to real-time queue count changes from SyncManager
    _queueCountSub?.cancel();
    _queueCountSub = syncManager.queueCountStream.listen((count) {
      ref.read(queuedCountProvider.notifier).state = count;
    });

    ref.onDispose(() {
      _remoteUpdatesSub?.cancel();
      _queueCountSub?.cancel();
    });

    return localStorage.getInventoryItems();
  }

  Future<void> increment(String itemId) async {
    final localStorage = ref.read(localStorageServiceProvider);
    final syncManager = ref.read(syncManagerProvider);

    final item = state.firstWhere(
      (e) => e.id == itemId,
      orElse: () => InventoryItem(id: itemId, name: itemId, quantity: 0),
    );

    final updated = item.copyWith(quantity: item.quantity + 1);
    state = state.map((e) => e.id == itemId ? updated : e).toList();

    await syncManager.sendInventoryUpdate(updated);
    ref.read(queuedCountProvider.notifier).state = localStorage.getQueuedCount();
  }

  Future<void> decrement(String itemId) async {
    final localStorage = ref.read(localStorageServiceProvider);
    final syncManager = ref.read(syncManagerProvider);

    final item = state.firstWhere(
      (e) => e.id == itemId,
      orElse: () => InventoryItem(id: itemId, name: itemId, quantity: 0),
    );

    // Rule: Quantity must never become negative
    if (item.quantity <= 0) return;

    final updated = item.copyWith(quantity: item.quantity - 1);
    state = state.map((e) => e.id == itemId ? updated : e).toList();

    await syncManager.sendInventoryUpdate(updated);
    ref.read(queuedCountProvider.notifier).state = localStorage.getQueuedCount();
  }

  Future<SyncState> refresh() async {
    final localStorage = ref.read(localStorageServiceProvider);
    final syncManager = ref.read(syncManagerProvider);

    final syncState = await syncManager.reconnect();
    state = localStorage.getInventoryItems();
    ref.read(queuedCountProvider.notifier).state = localStorage.getQueuedCount();
    return syncState;
  }
}
