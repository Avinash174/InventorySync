import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static const String broker = 'test.mosquitto.org';
  static const int port = 1883;

  MqttServerClient? _client;
  String _roomId = 'warehouse-main';
  String _deviceId = '';
  Timer? _reconnectTimer;
  bool _manuallyDisconnected = false;

  StreamSubscription? _updatesSub;

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  Stream<String> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionStateController.stream;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  String get topic => 'inventory-sync/$_roomId';

  void configure({required String deviceId, required String roomId}) {
    _deviceId = deviceId;
    _roomId = roomId;
  }

  Future<bool> connect({bool force = false}) async {
    if (isConnected && !force) return true;

    if (force) {
      disconnect();
    }

    _manuallyDisconnected = false;
    final clientId = 'inv_${_deviceId}_${DateTime.now().millisecondsSinceEpoch % 10000}';

    _client = MqttServerClient.withPort(broker, clientId, port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect = true;
    _client!.resubscribeOnAutoReconnect = true;

    _client!.onConnected = () {
      debugPrint('[MQTT] Connected to $broker on topic: $topic');
      _connectionStateController.add(true);
      _subscribe();
      _listenToUpdates();
      _reconnectTimer?.cancel();
    };

    _client!.onDisconnected = () {
      debugPrint('[MQTT] Disconnected');
      _connectionStateController.add(false);
      if (!_manuallyDisconnected) {
        _scheduleReconnect();
      }
    };

    _client!.onAutoReconnected = () {
      debugPrint('[MQTT] Auto-reconnected');
      _connectionStateController.add(true);
      _subscribe();
      _listenToUpdates();
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMessage;

    try {
      final status = await _client!.connect().timeout(const Duration(seconds: 6));
      if (status?.state == MqttConnectionState.connected) {
        _subscribe();
        _listenToUpdates();
        return true;
      }
    } on SocketException catch (e) {
      debugPrint('[MQTT] SocketException: $e');
    } on TimeoutException {
      debugPrint('[MQTT] Connection timed out');
    } catch (e) {
      debugPrint('[MQTT] Connection error: $e');
    }

    _scheduleReconnect();
    return false;
  }

  void _subscribe() {
    if (!isConnected) return;
    _client!.subscribe(topic, MqttQos.atLeastOnce);
  }

  void _listenToUpdates() {
    _updatesSub?.cancel();
    _updatesSub = _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final pubMsg = msg.payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(pubMsg.payload.message);
        debugPrint('[MQTT] Received payload: $payload');
        _messageController.add(payload);
      }
    });
  }

  bool publish(String payload) {
    if (!isConnected) return false;

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(payload);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      debugPrint('[MQTT] Published: $payload');
      return true;
    } catch (e) {
      debugPrint('[MQTT] Publish error: $e');
      return false;
    }
  }

  void updateRoom(String newRoomId) {
    if (_roomId == newRoomId) return;
    if (isConnected) {
      _client?.unsubscribe(topic);
    }
    _roomId = newRoomId;
    _subscribe();
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!isConnected && !_manuallyDisconnected) {
        connect();
      }
    });
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    try {
      _client?.disconnect();
    } catch (_) {}
    _connectionStateController.add(false);
  }

  void dispose() {
    disconnect();
    _updatesSub?.cancel();
    _messageController.close();
    _connectionStateController.close();
  }
}
