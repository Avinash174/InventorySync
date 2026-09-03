# Inventory Sync

## Video Walkthrough

[Video Walkthrough Link](https://youtu.be/your-demo-video)

---

## What is this?

This is a Flutter take-home assignment demonstrating a live distributed inventory system. 

The goal is to allow two warehouse workers on separate devices to keep their item counts in sync across three real-world network situations:

1. **Internet is available**: Both devices sync in real time over MQTT (`test.mosquitto.org`).
2. **Device goes offline**: Quantity changes update the UI immediately and are saved to a persistent offline queue in Hive. When the internet comes back, the queue automatically syncs to the cloud.
3. **No internet, but on the same Wi-Fi**: The app automatically switches to local peer-to-peer UDP broadcast on port 4040 so devices can still sync with zero internet.

No custom backend, Firebase, or external database servers are used.

---

## Tech Stack

- **Flutter & Dart**
- **flutter_riverpod**: State management (`Notifier`, `Provider`, `StreamProvider`)
- **mqtt_client**: MQTT broker connection (`test.mosquitto.org:1883`)
- **dart:io UDP Sockets**: Local subnet peer-to-peer broadcast
- **hive & hive_flutter**: Local persistence for items, offline queue, and deduplication
- **connectivity_plus**: Network interface state detection
- **uuid**: Unique message ID generation

---

## Project Structure

```text
lib/
├── models/
│   ├── inventory_item.dart       # Item data model (id, name, quantity)
│   └── sync_message.dart         # Sync payload (messageId, deviceId, itemId, quantity, timestamp)
│
├── providers/
│   └── inventory_provider.dart   # Riverpod providers & InventoryNotifier
│
├── services/
│   ├── mqtt_service.dart         # Connects, subscribes, publishes to MQTT broker
│   ├── udp_service.dart          # Binds UDP socket, broadcasts and listens on port 4040
│   ├── local_storage_service.dart# Hive storage for inventory, queue, and message IDs
│   └── sync_manager.dart         # Central coordinator deciding between MQTT, UDP, and queue
│
├── screens/
│   └── inventory_screen.dart     # Single-screen UI
│
├── widgets/
│   ├── inventory_item_card.dart  # Item card with [-] and [+] buttons
│   └── sync_status.dart          # Connection status badge (Online, Local, Offline)
│
└── main.dart                     # Hive init, ProviderScope setup, app entry point
```

---

## How Sync Works

All synchronization routing decisions are centralized inside `SyncManager`:

1. **Online (🟢 Online)**: 
   If MQTT is connected, changes are published directly to topic `inventory-sync/<room-id>`. Any accumulated offline queue messages are flushed right away.
2. **Local Wi-Fi Only (🟡 Local Network Only)**: 
   If MQTT is down but Wi-Fi is connected, changes are broadcast via UDP to the local subnet. The change is also saved in the offline queue so the cloud catches up when internet returns.
3. **Offline (🔴 Offline)**: 
   If there is no network, changes are saved locally in Hive and queued.

### Duplicate Prevention

Every sync message contains a unique `messageId` and sender `deviceId`. 
- Messages from the same device are ignored.
- Messages that have already been processed are discarded using an in-memory cache.

---

## Getting Started

### Prerequisites

- Flutter SDK (3.13+)
- Android device/emulator or iOS simulator

### Run the App

```bash
# 1. Install packages
flutter pub get

# 2. Run tests and analyzer
flutter analyze
flutter test

# 3. Start the app
flutter run
```

### Required Permissions

- **Android** (`android/app/src/main/AndroidManifest.xml`): `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`
- **iOS** (`ios/Runner/Info.plist`): `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_inventorysync._udp`)

---

## Testing with Two Devices

Run two app instances side-by-side:

### 1. Testing MQTT Cloud Sync
- Open the app on Device A and Device B with an active internet connection.
- Both devices show **🟢 Online**.
- Tap `+` on Device A for **Laptop** $\rightarrow$ Device B updates immediately.

### 2. Testing Offline Queue
- Turn on Airplane mode on Device A $\rightarrow$ status changes to **🔴 Offline**.
- Tap `+` a few times on Device A (shows `X queued`).
- Close and restart the app on Device A to verify the queue persists across restarts.
- Turn Airplane mode off $\rightarrow$ Device A reconnects to **🟢 Online**, flushes the queue, and Device B receives the updates.

### 3. Testing Local Wi-Fi (UDP)
- Connect both devices to the same Wi-Fi router with the WAN/internet cable disconnected.
- Both devices show **🟡 Local Network Only**.
- Change quantities on Device A $\rightarrow$ Device B receives the update instantly over UDP broadcast on port 4040.
