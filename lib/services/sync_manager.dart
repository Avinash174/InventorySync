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

  SyncManager({
    required this.mqttService,
    required this.udpService,
    required this.localStorage,
    Connectivity? connectivity,
  }) : connectivity = connectivity ?? Connectivity();

  SyncState get currentState => _currentState;
  Stream<SyncState> get stateStream => _stateController.stream;
  Stream<SyncMessage> get incomingUpdates => _incomingUpdatesController.stream;

  String get deviceId => localStorage.getDeviceId();
  String get roomId => localStorage.getRoomId();

  Future<void> init() async {
    mqttService.configure(deviceId: deviceId, roomId: roomId);

    // 1. Listen to MQTT connection state
    _mqttStateSub = mqttService.connectionStream.listen((connected) {
      _evaluateSyncState();
      if (connected) {
        _flushOfflineQueue();
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
    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      _evaluateSyncState();
      if (_hasInternetConnection(results) && !mqttService.isConnected) {
        mqttService.connect();
      }
    });

    // Initial connection attempt
    _evaluateSyncState();
    mqttService.connect();
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
      // Fallback if connectivity check fails
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

  Future<void> sendInventoryUpdate(InventoryItem item) async {
    // 1. Persist locally
    await localStorage.saveItem(item);

    // 2. Create sync payload
    final message = SyncMessage(
      messageId: const Uuid().v4(),
      deviceId: deviceId,
      itemId: item.id,
      quantity: item.quantity,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      roomId: roomId,
    );

    // Prevent echoing own message
    localStorage.markMessageProcessed(message.messageId);

    // 3. Route according to sync priority
    switch (_currentState) {
      case SyncState.online:
        final published = mqttService.publish(message.toJson());
        if (!published) {
          await localStorage.queueMessage(message);
        }
        break;

      case SyncState.localNetworkOnly:
        // Broadcast over local UDP
        await udpService.broadcast(message.toJson());
        // Also queue for cloud reconciliation when internet returns
        await localStorage.queueMessage(message);
        break;

      case SyncState.offline:
        await localStorage.queueMessage(message);
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

      // Apply update locally
      final existing = localStorage.getItem(message.itemId);
      final updated = existing != null
          ? existing.copyWith(quantity: message.quantity)
          : InventoryItem(id: message.itemId, name: message.itemId, quantity: message.quantity);

      localStorage.saveItem(updated);
      debugPrint('[SyncManager] Processed update from $source: ${message.itemId} = ${message.quantity}');

      // Notify BLoC
      _incomingUpdatesController.add(message);
    } catch (e) {
      debugPrint('[SyncManager] Error handling payload: $e');
    }
  }

  Future<void> _flushOfflineQueue() async {
    if (_isFlushingQueue || !mqttService.isConnected) return;
    _isFlushingQueue = true;

    try {
      final queued = localStorage.getQueuedMessages();
      if (queued.isEmpty) {
        _isFlushingQueue = false;
        return;
      }

      debugPrint('[SyncManager] Flushing ${queued.length} queued update(s)...');
      for (final msg in queued) {
        if (!mqttService.isConnected) break;

        final sent = mqttService.publish(msg.toJson());
        if (sent) {
          await localStorage.removeQueuedMessage(msg.messageId);
        } else {
          break;
        }
      }
      debugPrint('[SyncManager] Offline queue flush complete');
    } catch (e) {
      debugPrint('[SyncManager] Queue flush error: $e');
    } finally {
      _isFlushingQueue = false;
    }
  }

  Future<void> reconnect() async {
    await _evaluateSyncState();
    await mqttService.connect();
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
    mqttService.dispose();
    udpService.dispose();
  }
}
