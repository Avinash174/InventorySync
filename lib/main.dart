import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'providers/inventory_provider.dart';
import 'screens/inventory_screen.dart';
import 'services/local_storage_service.dart';
import 'services/mqtt_service.dart';
import 'services/sync_manager.dart';
import 'services/udp_service.dart';

import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive local storage
  await Hive.initFlutter();
  final localStorage = LocalStorageService();
  await localStorage.init();

  // 2. Initialize networking & synchronization services
  final mqttService = MqttService();
  final udpService = UdpService();
  final syncManager = SyncManager(
    mqttService: mqttService,
    udpService: udpService,
    localStorage: localStorage,
  );
  await syncManager.init();

  runApp(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(localStorage),
        syncManagerProvider.overrideWithValue(syncManager),
      ],
      child: const InventorySyncApp(),
    ),
  );
}

class InventorySyncApp extends ConsumerWidget {
  const InventorySyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Inventory Sync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      themeMode: themeMode,
      home: const InventoryScreen(),
    );
  }
}
