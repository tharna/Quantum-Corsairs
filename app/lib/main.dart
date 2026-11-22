import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'controller.dart';
import 'screens/title_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(_fontLicences);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final controller = GameController();
  runApp(QuantumCorsairsApp(controller: controller));
  controller.load();
}

Stream<LicenseEntry> _fontLicences() async* {
  for (final (pkg, file) in [
    ('Chakra Petch', 'OFL-chakra-petch.txt'),
    ('IBM Plex Mono', 'OFL-ibm-plex-mono.txt'),
    ('IBM Plex Sans', 'OFL-ibm-plex-sans.txt'),
  ]) {
    try {
      final text = await rootBundle.loadString('assets/fonts/$file');
      yield LicenseEntryWithLineBreaks([pkg], text);
    } catch (_) {}
  }
}

class QuantumCorsairsApp extends StatelessWidget {
  const QuantumCorsairsApp({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) => GameScope(
    controller: controller,
    child: MaterialApp(
      title: 'Quantum Corsairs',
      debugShowCheckedModeBanner: false,
      theme: QC.theme(),
      builder: (context, child) {
        // Honour the player's reduced-motion setting as well as the OS one.
        final mq = MediaQuery.of(context);
        final reduce = GameScope.of(context).settings.reducedMotion;
        return MediaQuery(
          data: mq.copyWith(disableAnimations: mq.disableAnimations || reduce),
          child: child!,
        );
      },
      home: const TitleScreen(),
    ),
  );
}
