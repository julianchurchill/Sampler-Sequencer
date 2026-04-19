import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'audio/sample_library.dart';
import 'constants.dart';
import 'models/sequencer_model.dart';
import 'screens/sequencer_screen.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
bool _errorOverlayShowing = false;

void _showErrorOverlay(Object error, StackTrace stack) {
  debugPrint('App error: $error\n$stack');
  if (_errorOverlayShowing) return;
  _errorOverlayShowing = true;
  // addPostFrameCallback defers the dialog until after the current frame so we
  // never call showDialog during a build or layout phase.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final state = _navigatorKey.currentState;
    if (state == null) {
      _errorOverlayShowing = false;
      return;
    }
    final trace = stack.toString();
    final traceSnippet =
        trace.length > 1000 ? '${trace.substring(0, 1000)}…' : trace;
    showDialog<void>(
      context: state.context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Error – please screenshot and share',
          style: TextStyle(color: Colors.red, fontSize: 13),
        ),
        content: SingleChildScrollView(
          child: Text(
            '$error\n\n$traceSnippet',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(state.context).pop(),
            child: const Text('DISMISS'),
          ),
        ],
      ),
    ).whenComplete(() => _errorOverlayShowing = false);
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    _showErrorOverlay(details.exception, details.stack ?? StackTrace.empty);
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
    (error, stack) => _showErrorOverlay(error, stack),
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
        navigatorKey: _navigatorKey,
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
