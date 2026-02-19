import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'providers/display_provider.dart';
import 'providers/nearpay_provider.dart';
import 'services/socket_service.dart';
import 'screens/device_setup_wizard.dart'; // Changed from connection_screen.dart
import 'screens/cds_wrapper.dart';
import 'screens/kds_wrapper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WakelockPlus.enable();

  runApp(const POSDisplayApp());
}

class POSDisplayApp extends StatelessWidget {
  const POSDisplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DisplayProvider()),
        ChangeNotifierProvider(create: (_) => NearPayProvider()),
        Provider<SocketService>(
          create: (context) =>
              SocketService(context.read<DisplayProvider>(), navigatorKey)
                ..initialize(),
          lazy: false,
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'HERMOSA POS Display',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
        initialRoute: '/',
        routes: {
          '/': (context) => DeviceSetupWizard(
            onClose: () {
              // Handle close action if needed, for now just log
              debugPrint('Wizard closed');
            },
          ),
          '/cds': (context) => const CdsPageWrapper(),
          '/kds': (context) => const KdsPageWrapper(),
        },
      ),
    );
  }
}
