import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class UdpService {
  static const int defaultPort = 4040;
  final int port;

  RawDatagramSocket? _socket;
  bool _isRunning = false;

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  UdpService({this.port = defaultPort});

  Stream<String> get messageStream => _messageController.stream;
  bool get isRunning => _isRunning;

  Future<bool> start() async {
    if (_isRunning && _socket != null) return true;

    try {
      try {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
          reusePort: true,
        );
      } catch (_) {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
        );
      }
      _socket!.broadcastEnabled = true;
      _isRunning = true;

      debugPrint('[UDP] Listening on port $port');

      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket?.receive();
          if (datagram != null) {
            try {
              final text = utf8.decode(datagram.data);
              _messageController.add(text);
            } catch (e) {
              debugPrint('[UDP] Packet decode error: $e');
            }
          }
        }
      }, onError: (e) {
        debugPrint('[UDP] Socket error: $e');
        stop();
      });

      return true;
    } catch (e) {
      debugPrint('[UDP] Bind failed on port $port: $e');
      _isRunning = false;
      return false;
    }
  }

  Future<bool> broadcast(String message) async {
    if (!_isRunning || _socket == null) {
      final started = await start();
      if (!started) return false;
    }

    try {
      final data = utf8.encode(message);
      final targets = <InternetAddress>[
        InternetAddress('255.255.255.255'),
      ];

      // Also try discovering interface broadcast addresses
      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
            }
          }
        }
      } catch (_) {}

      for (final target in targets.toSet()) {
        try {
          _socket!.send(data, target, port);
        } catch (_) {}
      }

      debugPrint('[UDP] Broadcasted message: $message');
      return true;
    } catch (e) {
      debugPrint('[UDP] Broadcast failed: $e');
      return false;
    }
  }

  void stop() {
    _isRunning = false;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    stop();
    _messageController.close();
  }
}
