# Inventory Sync

## Video Walkthrough

[Video Link](https://youtu.be/your-demo-video)

---

## Overview

**Inventory Sync** is a live distributed inventory application built in Flutter using **Riverpod** for state management. It allows two warehouse workers on different devices to keep their inventory in sync across three operational scenarios:

1. **Internet Available**: Synchronizes in real time via an MQTT broker (`test.mosquitto.org`).
2. **Device Offline**: Updates the UI immediately, persists inventory locally, and stores changes in a persistent offline queue that flushes automatically when MQTT reconnects.
3. **Same Local Wi-Fi (No Internet)**: Falls back to peer-to-peer UDP broadcast (`dart:io` sockets on port `4040`) for instant local sync.

The app uses no backend servers, no Firebase, and no BaaS.

---

## Features

- **State Management with Riverpod**: Simple, decoupled state handling with `Notifier`, `Provider`, and `StreamProvider`.
- **Real-Time MQTT Cloud Sync**: Instant bi-directional sync over `test.mosquitto.org:1883`.
- **Local Network Fallback (UDP)**: Direct peer-to-peer broadcast over local Wi-Fi without internet.
- **Offline-First Persistent Queue**: Offline changes are saved in Hive and automatically flushed sequentially when online.
- **Duplicate Prevention**: In-memory cache of recent message IDs prevents processing duplicate or self-generated updates.
- **Sync Status Indicator**: Prominently displays:
  - 🟢 **Online**: MQTT connected and active.
  - 🟡 **Local Network Only**: UDP broadcast active over local Wi-Fi.
  - 🔴 **Offline**: Offline queue active.
- **Non-Negative Quantity Constraint**: Inventory quantity can never drop below zero.

---

## Project Structure

```text
lib/
├── models/
│   ├── inventory_item.dart       # Item model (id, name, quantity)
│   └── sync_message.dart         # Payload model (messageId, deviceId, itemId, quantity, timestamp)
│
├── providers/
│   └── inventory_provider.dart   # Riverpod providers & InventoryNotifier
│
├── services/
│   ├── mqtt_service.dart         # MQTT client connection, subscribe/publish, auto-reconnect
│   ├── udp_service.dart          # UDP socket binding, broadcasting, listening
│   ├── local_storage_service.dart# Hive storage for inventory items, queue & deduplication
│   └── sync_manager.dart         # Central sync coordinator & transport priority
│
├── screens/
│   └── inventory_screen.dart     # Main single-screen inventory UI (ConsumerWidget)
│
├── widgets/
│   ├── inventory_item_card.dart  # Item card with [ - ] and [ + ] buttons
│   └── sync_status.dart          # Sync status indicator badge
│
└── main.dart                     # App initialization, ProviderScope & service wiring
```

### Dependency Flow

```text
InventoryScreen (ConsumerWidget)
       │ (ref.watch / ref.read)
       ▼
InventoryNotifier (Notifier<List<InventoryItem>>)
       │
       ▼
SyncManager
 ├── MqttService
 ├── UdpService
 └── LocalStorageService
```

---

## Synchronization Strategy

The `SyncManager` centralizes all sync decisions:

```text
               Inventory Changed
                      │
                      ▼
               Is MQTT connected?
                 /          \
               YES           NO
                │             │
                ▼             ▼
              MQTT       Is Wi-Fi available?
                            /       \
                          YES        NO
                           │          │
                           ▼          ▼
                          UDP    Offline Queue
```

- **MQTT (🟢 Online)**: Used when internet/broker is connected.
- **UDP (🟡 Local Network Only)**: Used when MQTT is disconnected but local Wi-Fi is available.
- **Offline Queue (🔴 Offline)**: Used when no connection exists. Changes are saved to Hive and flushed upon MQTT reconnect.

---

## Setup & Running

```bash
# 1. Install dependencies
flutter pub get

# 2. Run static analysis & unit tests
flutter analyze
flutter test

# 3. Launch application
flutter run
```

### Network Permissions

- **Android** (`android/app/src/main/AndroidManifest.xml`): `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- **iOS** (`ios/Runner/Info.plist`): `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_inventorysync._udp`).

---

## Testing with Two Devices

Run two instances simultaneously (e.g., on two emulators/devices):

### 1. MQTT Cloud Sync
1. Open the app on Device A and Device B with internet active.
2. Both show **🟢 Online**.
3. Press `+` on Device A for **Laptop** $\rightarrow$ Device B updates immediately to the new quantity.

### 2. Offline Queue
1. Turn on Airplane Mode on Device A $\rightarrow$ status becomes **🔴 Offline**.
2. Increment **Keyboard** on Device A (shows `1 queued`).
3. Restart the app on Device A to verify persistence of the pending queue.
4. Disable Airplane Mode $\rightarrow$ Device A reconnects to **🟢 Online**, flushes the queue, and Device B receives the update.

### 3. Local Wi-Fi (UDP)
1. Connect both devices to the same Wi-Fi router (without internet/WAN).
2. Status displays **🟡 Local Network Only**.
3. Change quantities on Device A $\rightarrow$ Device B receives the update via local UDP broadcast on port 4040.
