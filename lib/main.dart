import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'audio/sample_library.dart';
import 'constants.dart';
import 'models/sequencer_model.dart';
import 'screens/sequencer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Drum machines are landscape — lock orientation.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const SamplerApp());
}

class SamplerApp extends StatelessWidget {
  const SamplerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SequencerModel()),
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
