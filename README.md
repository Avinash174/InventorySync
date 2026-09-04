# Inventory Sync

## APK Download

[Download Signed APK](https://drive.google.com/drive/folders/1OMDB0lLsTZJv5qP2i2_AUfsncMIT7Wba?usp=sharing)

## Demo Video

[Watch 5-Minute Walkthrough](YOUR_VIDEO_LINK)

---

## Project Overview

**Inventory Sync** is a robust Flutter application designed for distributed, two-way real-time inventory synchronization across multiple physical devices under diverse network environments:

1. **MQTT Cloud Sync (🟢 Online)**: Real-time synchronization when Internet is available (cellular data or Wi-Fi).
2. **UDP Local Broadcast (🟡 Local Network Only)**: Local Wi-Fi peer-to-peer synchronization on port 4040 when Internet is unavailable.
3. **Hive Local Persistence & Offline Queue (🔴 Offline)**: Instant local state updates and durable offline queuing when completely disconnected. Automatically flushes and synchronizes upon reconnect.

> **Zero Backend Dependency**: No custom backend, Firebase, or external BaaS is required.

---

## Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Material 3)
- **Language**: [Dart](https://dart.dev/)
- **State Management**: [Riverpod](https://riverpod.dev/) (`Notifier`, `Provider`, `StreamProvider`)
- **Internet Sync**: [mqtt_client](https://pub.dev/packages/mqtt_client) (`test.mosquitto.org:1883`)
- **Local Network Sync**: `dart:io` Raw UDP Datagram Sockets (Port `4040`)
- **Local Storage**: [Hive](https://pub.dev/packages/hive) & [hive_flutter](https://pub.dev/packages/hive_flutter)
- **Connectivity Detection**: [connectivity_plus](https://pub.dev/packages/connectivity_plus)
- **UUID & Serialization**: [uuid](https://pub.dev/packages/uuid) & [equatable](https://pub.dev/packages/equatable)

---

## Architecture & Data Flow

```text
               +---------------------------+
               |        Flutter UI         |
               +---------------------------+
                             |
                   User Tap (+/- Buttons)
                             v
               +---------------------------+
               |     InventoryNotifier     |
               +---------------------------+
                             |
                1. Local Memory Update
                2. Persist to Hive DB
                3. Create SyncMessage
                             v
               +---------------------------+
               |        SyncManager        |
               +---------------------------+
                             |
         +-------------------+-------------------+
         | (Internet ON)     | (LAN Only)        | (No Network)
         v                   v                   v
+-----------------+ +-----------------+ +-----------------+
|   MqttService   | |   UdpService    | |  Offline Queue  |
|  (Port 1883)    | |  (UDP Port 4040)| |   (Hive Box)    |
+-----------------+ +-----------------+ +-----------------+
         |                   |                   |
         +--------+----------+                   |
                  |                              |
            Remote Device                        | (On Reconnect)
                  v                              v
   +------------------------------+     +-----------------+
   |    Incoming Message Parser   | <-- |   Flush Queue   |
   | - Filter own deviceId        |     +-----------------+
   | - Message Deduplication Cache|
   | - Apply Operation / Delta    |
   | - Save to Hive DB            |
   | - Emit to Riverpod UI Stream |
   +------------------------------+
```

---

## Sync Modes Explained

### 1. MQTT Cloud Mode (Internet Available)
- Connects to `test.mosquitto.org:1883`.
- Both devices subscribe to the topic: `inventory-sync/<roomId>`.
- Any local modification publishes a JSON `SyncMessage` with `operation` (`increment`/`decrement`), `delta`, `messageId`, `deviceId`, and `timestamp`.
- Receiving devices parse the payload, ignore self-messages and duplicates, apply the delta, update Hive, and notify Riverpod listeners to refresh the UI immediately.

### 2. UDP Local P2P Mode (Same Wi-Fi, No Internet)
- When Internet is disconnected but devices share the same Wi-Fi or Mobile Hotspot, `SyncManager` selects `localNetworkOnly`.
- Binds to `0.0.0.0:4040` with broadcast enabled.
- Discovers local network interfaces and broadcasts to subnet addresses (e.g. `192.168.1.255`, `192.168.43.255`) and `255.255.255.255`.
- Peer devices receive datagrams, apply delta updates locally, and persist to Hive.

### 3. Offline Mode & Queue Reconciliation
- When completely offline (Airplane mode / No network), quantity changes are applied to local Hive state and appended to the `offline_queue` Hive box.
- The queue is persistent and survives app restarts.
- As soon as network connectivity is restored and MQTT reconnects, the offline queue is flushed sequentially. Messages are safely removed from the queue only after successful dispatch.

---

## Project Structure

```text
lib/
├── models/
│   ├── inventory_item.dart        # Item model (id, name, quantity)
│   └── sync_message.dart          # Sync message payload model & serialization
│
├── providers/
│   ├── inventory_provider.dart    # Riverpod inventory state, stream subscriptions
│   └── theme_provider.dart        # Theme mode notifier (Light / Dark / System)
│
├── services/
│   ├── local_storage_service.dart # Hive storage for inventory, queue & deduplication
│   ├── mqtt_service.dart          # MQTT connection, subscription & publication
│   ├── udp_service.dart           # UDP socket listener & broadcast transport
│   └── sync_manager.dart          # Central sync coordinator & network state router
│
├── screens/
│   └── inventory_screen.dart      # Main inventory UI & manual refresh
│
├── widgets/
│   ├── inventory_item_card.dart   # Interactive item card with +/- buttons
│   └── sync_status.dart           # Dynamic sync badge (Online, Local, Offline)
│
└── main.dart                      # App initialization & ProviderScope overrides
```

---

## Getting Started

### Prerequisites

- Flutter SDK (3.13+)
- Android device/emulator or iOS simulator

### Installation & Run

```bash
# 1. Install dependencies
flutter pub get

# 2. Run code analyzer & tests
flutter analyze
flutter test

# 3. Launch application
flutter run
```

### Required Permissions

- **Android** (`android/app/src/main/AndroidManifest.xml`):
  - `INTERNET`
  - `ACCESS_NETWORK_STATE`
  - `ACCESS_WIFI_STATE`
  - `CHANGE_WIFI_MULTICAST_STATE`
  - `android:usesCleartextTraffic="true"` (Allows unencrypted TCP port 1883 and UDP port 4040 communication)

---

## Step-by-Step Testing Guide

### Scenario 1: MQTT Internet Sync (Cellular / Different Networks)
1. Open the app on **Device A** and **Device B** (both connected to Internet).
2. Verify both devices show **🟢 Online**.
3. On **Device A**, tap `+` on **Laptop** ($10 \rightarrow 11$).
4. Check **Device B**: **Laptop** immediately updates to $11$.
5. On **Device B**, tap `+` on **Laptop** ($11 \rightarrow 12$).
6. Check **Device A**: **Laptop** immediately updates to $12$.

### Scenario 2: Same Wi-Fi without Internet (UDP Peer-to-Peer)
1. Connect both devices to the **same Wi-Fi router** with no Internet (or one device on Mobile Hotspot with data disabled).
2. Both devices show **🟡 Local Network Only**.
3. On **Device A**, tap `+` on **Mouse** ($6 \rightarrow 7$).
4. Check **Device B**: **Mouse** updates to $7$ via UDP port 4040.

### Scenario 3: Completely Offline Queue & Recovery
1. Turn on **Airplane Mode** on **Device A** (status changes to **🔴 Offline**).
2. On **Device A**, tap `+` on **Keyboard** twice ($7 \rightarrow 9$, shows `2 queued`).
3. Kill and restart the app on **Device A** $\rightarrow$ verify **Keyboard = 9** and `2 queued` persists.
4. Turn off Airplane Mode on **Device A** $\rightarrow$ status switches to **🟢 Online**, queue flushes to $0$, and **Device B** receives the update to $9$.
