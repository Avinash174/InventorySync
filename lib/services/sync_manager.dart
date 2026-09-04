import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_item.dart';
import '../models/sync_message.dart';
import 'local_storage_service.dart';
import 'mqtt_service.dart';
import 'udp_service.dart';

enum SyncState {
  online('🟢 Online', 'Connected to MQTT Cloud Broker'),
  localNetworkOnly('🟡 Local Network Only', 'P2P Local Wi-Fi UDP Broadcast'),
  offline('🔴 Offline', 'Changes saved to Offline Queue');

  final String label;
  final String description;
  const SyncState(this.label, this.description);
}

class SyncManager {
  final MqttService mqttService;
  final UdpService udpService;
  final LocalStorageService localStorage;
  final Connectivity connectivity;

  StreamSubscription? _connectivitySub;
  StreamSubscription? _mqttStateSub;
  StreamSubscription? _mqttMsgSub;
  StreamSubscription? _udpMsgSub;

  SyncState _currentState = SyncState.offline;
  bool _isFlushingQueue = false;

  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  final StreamController<SyncMessage> _incomingUpdatesController =
      StreamController<SyncMessage>.broadcast();
  final StreamController<int> _queueCountController =
      StreamController<int>.broadcast();

  SyncManager({
    required this.mqttService,
    required this.udpService,
    required this.localStorage,
    Connectivity? connectivity,
  }) : connectivity = connectivity ?? Connectivity();

  SyncState get currentState => _currentState;
  Stream<SyncState> get stateStream => _stateController.stream;
  Stream<SyncMessage> get incomingUpdates => _incomingUpdatesController.stream;
  Stream<int> get queueCountStream => _queueCountController.stream;

  String get deviceId => localStorage.getDeviceId();
  String get roomId => localStorage.getRoomId();

  Future<void> init() async {
    mqttService.configure(deviceId: deviceId, roomId: roomId);

    debugPrint('[SYNC] deviceId: $deviceId');
    debugPrint('[SYNC] roomId: $roomId');
    debugPrint('[SYNC] mqttTopic: ${mqttService.topic}');

    // 1. Listen to MQTT connection state
    _mqttStateSub = mqttService.connectionStream.listen((connected) async {
      await _evaluateSyncState();
      if (connected) {
        debugPrint('[SYNC] MQTT connected');
        debugPrint('[SYNC] Subscribed: inventory-sync/$roomId');
        await _flushOfflineQueue();
      }
    });

    // 2. Listen to MQTT incoming messages
    _mqttMsgSub = mqttService.messageStream.listen((raw) {
      _handleIncomingPayload(raw, source: 'MQTT');
    });

    // 3. Listen to UDP incoming messages
    _udpMsgSub = udpService.messageStream.listen((raw) {
      _handleIncomingPayload(raw, source: 'UDP');
    });

    // 4. Listen to network connectivity
    _connectivitySub = connectivity.onConnectivityChanged.listen((results) async {
      final isOnline = _hasInternetConnection(results);
      if (isOnline) {
        debugPrint('[SYNC] Connectivity: ONLINE');
        await _evaluateSyncState();
        if (!mqttService.isConnected) {
          debugPrint('[SYNC] Reconnecting MQTT...');
          final connected = await mqttService.connect();
          if (connected) {
            debugPrint('[SYNC] MQTT connected');
            debugPrint('[SYNC] Subscribed: inventory-sync/$roomId');
            await _evaluateSyncState();
            await _flushOfflineQueue();
          }
        }
      } else {
        debugPrint('[SYNC] Connectivity: OFFLINE');
        await _evaluateSyncState();
      }
    });

    // Initial state evaluation and connection
    await _evaluateSyncState();
    _queueCountController.add(localStorage.getQueuedCount());
    final initialConnected = await mqttService.connect();
    if (initialConnected) {
      debugPrint('[SYNC] MQTT connected');
      debugPrint('[SYNC] Subscribed: inventory-sync/$roomId');
      await _evaluateSyncState();
      await _flushOfflineQueue();
    }
  }

  Future<void> _evaluateSyncState() async {
    try {
      final results = await connectivity.checkConnectivity();
      final hasWifi = results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);

      SyncState newState;
      if (mqttService.isConnected) {
        newState = SyncState.online;
        udpService.stop();
      } else if (hasWifi) {
        newState = SyncState.localNetworkOnly;
        udpService.start();
      } else {
        newState = SyncState.offline;
        udpService.stop();
      }

      if (newState != _currentState) {
        _currentState = newState;
        _stateController.add(_currentState);
        debugPrint('[SyncManager] Status changed -> ${_currentState.label}');
      }
    } catch (_) {
      if (mqttService.isConnected && _currentState != SyncState.online) {
        _currentState = SyncState.online;
        _stateController.add(_currentState);
      }
    }
  }

  bool _hasInternetConnection(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }

  Future<void> sendInventoryUpdate(InventoryItem item, {int delta = 0}) async {
    // 1. Persist locally
    await localStorage.saveItem(item);

    final prevQty = item.quantity - delta;
    final itemName = item.name.isNotEmpty ? item.name : item.id;
    debugPrint('[SYNC][LOCAL] $itemName: $prevQty → ${item.quantity}');

    // 2. Create sync payload
    final message = SyncMessage(
      messageId: const Uuid().v4(),
      deviceId: deviceId,
      itemId: item.id,
      delta: delta,
      quantity: item.quantity,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      roomId: roomId,
    );

    // Prevent echoing own message
    localStorage.markMessageProcessed(message.messageId);

    final opStr = delta >= 0 ? '+$delta' : '$delta';

    // 3. Route according to sync priority
    switch (_currentState) {
      case SyncState.online:
        debugPrint('[SYNC][MQTT OUT] messageId: ${message.messageId} itemId: ${message.itemId} operation: $opStr');
        final published = mqttService.publish(message.toJson());
        if (!published) {
          await localStorage.queueMessage(message);
          debugPrint('[SYNC][QUEUE] Added message: ${message.messageId}');
          _queueCountController.add(localStorage.getQueuedCount());
        }
        break;

      case SyncState.localNetworkOnly:
        // Broadcast over local UDP
        await udpService.broadcast(message.toJson());
        // Also queue for cloud reconciliation when internet returns
        await localStorage.queueMessage(message);
        debugPrint('[SYNC][QUEUE] Added message: ${message.messageId}');
        _queueCountController.add(localStorage.getQueuedCount());
        break;

      case SyncState.offline:
        await localStorage.queueMessage(message);
        debugPrint('[SYNC][QUEUE] Added message: ${message.messageId}');
        _queueCountController.add(localStorage.getQueuedCount());
        break;
    }
  }

  void _handleIncomingPayload(String payload, {required String source}) {
    try {
      final message = SyncMessage.fromJson(payload);
      if (!message.isValid) return;

      // Ignore if message is from this device
      if (message.deviceId == deviceId) return;

      // Ignore duplicates
      if (localStorage.isMessageProcessed(message.messageId)) return;
      localStorage.markMessageProcessed(message.messageId);

      final opStr = message.delta >= 0 ? '+${message.delta}' : '${message.delta}';
      debugPrint('[SYNC][MQTT IN] messageId: ${message.messageId} deviceId: ${message.deviceId} itemId: ${message.itemId} operation: $opStr');

      // Apply update locally using delta or fallback quantity
      final existing = localStorage.getItem(message.itemId);
      final int newQuantity;
      if (existing != null) {
        if (message.delta != 0) {
          final computed = existing.quantity + message.delta;
          newQuantity = computed < 0 ? 0 : computed;
        } else {
          newQuantity = message.quantity;
        }
      } else {
        newQuantity = message.quantity;
      }

      final updated = existing != null
          ? existing.copyWith(quantity: newQuantity)
          : InventoryItem(id: message.itemId, name: message.itemId, quantity: newQuantity);

      localStorage.saveItem(updated);
      final itemName = updated.name.isNotEmpty ? updated.name : updated.id;
      debugPrint('[SYNC][APPLY] $itemName: ${existing?.quantity ?? 0} → $newQuantity (via $source)');

      // Notify BLoC / Notifier
      _incomingUpdatesController.add(message);
    } catch (e) {
      debugPrint('[SYNC][ERROR] Error handling payload: $e');
    }
  }

  Future<void> _flushOfflineQueue() async {
    if (_isFlushingQueue || !mqttService.isConnected) return;
    _isFlushingQueue = true;

    try {
      final queued = localStorage.getQueuedMessages();
      debugPrint('[SYNC] Queue size: ${queued.length}');
      if (queued.isEmpty) {
        return;
      }

      debugPrint('[SyncManager] Flushing ${queued.length} queued update(s)...');
      for (final msg in queued) {
        if (!mqttService.isConnected) {
          debugPrint('[SYNC][ERROR] MQTT disconnected during flush');
          break;
        }

        final opStr = msg.delta >= 0 ? '+${msg.delta}' : '${msg.delta}';
        debugPrint('[SYNC][MQTT OUT] messageId: ${msg.messageId} itemId: ${msg.itemId} operation: $opStr');
        final sent = mqttService.publish(msg.toJson());
        if (sent) {
          await localStorage.removeQueuedMessage(msg.messageId);
          debugPrint('[SYNC][QUEUE] Removed: ${msg.messageId}');
          _queueCountController.add(localStorage.getQueuedCount());
        } else {
          debugPrint('[SYNC][ERROR] Failed to publish message: ${msg.messageId}');
          break;
        }
      }
      final remaining = localStorage.getQueuedCount();
      debugPrint('[SYNC] Queue size: $remaining');
      _queueCountController.add(remaining);
      debugPrint('[SyncManager] Offline queue flush complete');
    } catch (e) {
      debugPrint('[SYNC][ERROR] Queue flush error: $e');
    } finally {
      _isFlushingQueue = false;
    }
  }

  Future<SyncState> reconnect() async {
    await _evaluateSyncState();
    debugPrint('[SYNC] Reconnecting MQTT...');
    final connected = await mqttService.connect(force: true);
    if (connected) {
      debugPrint('[SYNC] MQTT connected');
      debugPrint('[SYNC] Subscribed: inventory-sync/$roomId');
    }
    await _evaluateSyncState();
    if (mqttService.isConnected) {
      await _flushOfflineQueue();
    }
    return _currentState;
  }

  Future<void> updateRoom(String newRoomId) async {
    final clean = newRoomId.trim();
    if (clean.isEmpty) return;
    await localStorage.setRoomId(clean);
    mqttService.updateRoom(clean);
  }

  void dispose() {
    _connectivitySub?.cancel();
    _mqttStateSub?.cancel();
    _mqttMsgSub?.cancel();
    _udpMsgSub?.cancel();
    _stateController.close();
    _incomingUpdatesController.close();
    _queueCountController.close();
    mqttService.dispose();
    udpService.dispose();
  }
}
