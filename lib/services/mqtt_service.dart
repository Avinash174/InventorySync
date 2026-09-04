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
  Future<bool>? _connectingFuture;

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

    if (_connectingFuture != null && !force) {
      return _connectingFuture!;
    }

    _connectingFuture = _performConnect(force: force);
    try {
      final result = await _connectingFuture!;
      return result;
    } finally {
      _connectingFuture = null;
    }
  }

  Future<bool> _performConnect({bool force = false}) async {
    _reconnectTimer?.cancel();

    if (force || _client != null) {
      _teardownClient();
    }

    _manuallyDisconnected = false;
    final clientId = 'inv_${_deviceId}_${DateTime.now().millisecondsSinceEpoch}';

    final client = MqttServerClient.withPort(broker, clientId, port);
    _client = client;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;

    // Attach updates listener once per client instance
    _updatesSub?.cancel();
    _updatesSub = client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final pubMsg = msg.payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(pubMsg.payload.message);
        _messageController.add(payload);
      }
    });

    client.onConnected = () {
      if (_client != client) return;
      _reconnectTimer?.cancel();
      debugPrint('[MQTT] CONNECTED');
      _subscribe();
      _connectionStateController.add(true);
    };

    client.onDisconnected = () {
      if (_client != client) return;
      _connectionStateController.add(false);
      if (!_manuallyDisconnected) {
        _scheduleReconnect();
      }
    };

    client.onAutoReconnected = () {
      if (_client != client) return;
      _reconnectTimer?.cancel();
      debugPrint('[MQTT] CONNECTED');
      _subscribe();
      _connectionStateController.add(true);
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMessage;

    try {
      final status = await client.connect().timeout(const Duration(seconds: 6));
      if (_client == client && status?.state == MqttConnectionState.connected) {
        debugPrint('[MQTT] CONNECTED');
        _subscribe();
        return true;
      }
    } on SocketException catch (e) {
      debugPrint('[MQTT] SocketException: $e');
    } on TimeoutException {
      debugPrint('[MQTT] Connection timed out');
    } catch (e) {
      debugPrint('[MQTT] Connection error: $e');
    }

    if (_client == client) {
      _scheduleReconnect();
    }
    return false;
  }

  void _subscribe() {
    if (!isConnected || _client == null) return;
    try {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
      debugPrint('[MQTT] SUBSCRIBED: $topic');
    } catch (e) {
      debugPrint('[MQTT] Subscribe error: $e');
    }
  }

  bool publish(String payload, {String? targetTopic}) {
    if (!isConnected || _client == null) return false;

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(payload);
      final pubTopic = targetTopic ?? topic;
      final result = _client!.publishMessage(pubTopic, MqttQos.atLeastOnce, builder.payload!);
      return result >= 0;
    } catch (e) {
      debugPrint('[MQTT] Publish error: $e');
      return false;
    }
  }

  void updateRoom(String newRoomId) {
    if (_roomId == newRoomId) return;
    if (isConnected && _client != null) {
      try {
        _client!.unsubscribe(topic);
      } catch (_) {}
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

  void _teardownClient() {
    _updatesSub?.cancel();
    _updatesSub = null;
    if (_client != null) {
      _client!.onConnected = null;
      _client!.onDisconnected = null;
      _client!.onAutoReconnected = null;
      try {
        _client!.disconnect();
      } catch (_) {}
      _client = null;
    }
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _connectingFuture = null;
    _teardownClient();
    _connectionStateController.add(false);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionStateController.close();
  }
}
