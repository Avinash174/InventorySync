import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_item.dart';
import '../models/sync_message.dart';

class LocalStorageService {
  static const String _inventoryBoxName = 'inventory_items';
  static const String _queueBoxName = 'offline_queue';
  static const String _settingsBoxName = 'app_settings';

  Box? _inventoryBox;
  Box? _queueBox;
  Box? _settingsBox;

  // In-memory cache of recent message IDs to prevent duplicates
  final Set<String> _processedMessageIds = {};

  Future<void> init() async {
    _inventoryBox = await Hive.openBox(_inventoryBoxName);
    _queueBox = await Hive.openBox(_queueBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);

    await _seedInitialItems();
  }

  Future<void> _seedInitialItems() async {
    if (_inventoryBox != null && _inventoryBox!.isEmpty) {
      final defaultItems = [
        const InventoryItem(id: 'item-1', name: 'Laptop', quantity: 10),
        const InventoryItem(id: 'item-2', name: 'Keyboard', quantity: 20),
        const InventoryItem(id: 'item-3', name: 'Mouse', quantity: 15),
        const InventoryItem(id: 'item-4', name: 'Monitor', quantity: 8),
      ];
      for (final item in defaultItems) {
        await _inventoryBox!.put(item.id, item.toMap());
      }
    }
  }

  // --- Inventory Items ---

  List<InventoryItem> getInventoryItems() {
    if (_inventoryBox == null) return [];
    return _inventoryBox!.values
        .map((e) => InventoryItem.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  InventoryItem? getItem(String id) {
    if (_inventoryBox == null) return null;
    final map = _inventoryBox!.get(id);
    if (map == null) return null;
    return InventoryItem.fromMap(Map<dynamic, dynamic>.from(map as Map));
  }

  Future<void> saveItem(InventoryItem item) async {
    if (_inventoryBox == null) return;
    await _inventoryBox!.put(item.id, item.toMap());
  }

  // --- Offline Queue ---

  List<SyncMessage> getQueuedMessages() {
    if (_queueBox == null) return [];
    final list = <SyncMessage>[];
    for (final raw in _queueBox!.values) {
      try {
        list.add(SyncMessage.fromMap(Map<dynamic, dynamic>.from(raw as Map)));
      } catch (_) {}
    }
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  int getQueuedCount() => _queueBox?.length ?? 0;

  Future<void> queueMessage(SyncMessage message) async {
    if (_queueBox == null) return;
    await _queueBox!.put(message.messageId, message.toMap());
  }

  Future<void> removeQueuedMessage(String messageId) async {
    if (_queueBox == null) return;
    await _queueBox!.delete(messageId);
  }

  // --- Deduplication Cache ---

  bool isMessageProcessed(String messageId) {
    return _processedMessageIds.contains(messageId);
  }

  void markMessageProcessed(String messageId) {
    _processedMessageIds.add(messageId);
    if (_processedMessageIds.length > 500) {
      _processedMessageIds.remove(_processedMessageIds.first);
    }
  }

  // --- Device ID & Room ID ---

  String getDeviceId() {
    if (_settingsBox == null) return 'dev-${const Uuid().v4().substring(0, 6)}';
    var id = _settingsBox!.get('device_id') as String?;
    if (id == null || id.isEmpty) {
      id = 'dev-${const Uuid().v4().substring(0, 6)}';
      _settingsBox!.put('device_id', id);
    }
    return id;
  }

  String getRoomId() {
    return _settingsBox?.get('room_id', defaultValue: 'warehouse-main') as String? ?? 'warehouse-main';
  }

  Future<void> setRoomId(String roomId) async {
    await _settingsBox?.put('room_id', roomId.trim());
  }

  // --- Theme Mode ---

  String getThemeMode() {
    return _settingsBox?.get('theme_mode', defaultValue: 'system') as String? ?? 'system';
  }

  Future<void> setThemeMode(String themeMode) async {
    await _settingsBox?.put('theme_mode', themeMode);
  }
}
