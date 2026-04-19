import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'audio/sample_library.dart';
import 'constants.dart';
import 'models/sequencer_model.dart';
import 'screens/sequencer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint(
        'FlutterError: ${details.exception}\n${details.stack}');
    FlutterError.presentError(details);
  };

  runZonedGuarded(
    () {
      // Drum machines are landscape — lock orientation.
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      runApp(const SamplerApp());
    },
    (error, stack) {
      debugPrint('Unhandled async error: $error\n$stack');
    },
  );
}

class SamplerApp extends StatelessWidget {
  const SamplerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SequencerModel()..init()),
        ChangeNotifierProvider(create: (_) => SampleLibrary()..init()),
      ],
      child: MaterialApp(
        title: 'Sampler Sequencer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: kBgColor,
          colorScheme: const ColorScheme.dark(
            surface: kPanelColor,
            primary: Color(0xFFFF5722),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: kPanelColor,
            elevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
        ),
        home: const SequencerScreen(),
      ),
    );
  }
}
