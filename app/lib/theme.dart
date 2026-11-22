import 'package:material_ui/material_ui.dart';

/// Design tokens from the rev B visual design: an engineering console drawn
/// on blueprint film.
abstract final class QC {
  static const field = Color(0xFF060912);
  static const fieldDeep = Color(0xFF04060D);
  static const film = Color(0xFF0B1224);
  static const grid = Color(0xFF1F2C4A);
  static const ink = Color(0xFFE6ECFF);
  static const muted = Color(0xFF8F9BC0);

  /// The player.
  static const you = Color(0xFF5CF2C8);
  static const youInk = Color(0xFF04140F);

  /// Every enemy.
  static const them = Color(0xFFFF9A4D);

  /// Anything still undecided: superposition and odds.
  static const quantum = Color(0xFFB18CFF);

  /// Bell-lock and weather.
  static const coherence = Color(0xFF6FE3FF);

  static const display = 'ChakraPetch';
  static const body = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';

  static const radius = BorderRadius.all(Radius.circular(2));

  static TextStyle displayStyle(double size, {Color color = ink}) => TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    fontSize: size,
    height: 1.0,
    letterSpacing: 0.4,
    color: color,
  );

  static TextStyle monoStyle(
    double size, {
    Color color = muted,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: mono,
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle label(double size, {Color color = muted}) => TextStyle(
    fontFamily: mono,
    fontSize: size,
    letterSpacing: 1.6,
    color: color,
    fontWeight: FontWeight.w500,
  );

  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: you,
      onPrimary: youInk,
      secondary: coherence,
      onSecondary: field,
      tertiary: quantum,
      surface: film,
      onSurface: ink,
      error: them,
      outline: grid,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: field,
      fontFamily: body,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: ink),
        bodySmall: TextStyle(fontSize: 13, height: 1.35, color: muted),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? youInk : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? you : grid,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: you,
        inactiveTrackColor: grid,
        thumbColor: you,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: film,
        contentTextStyle: TextStyle(color: ink, fontFamily: body),
      ),
    );
  }
}

/// The faint blueprint grid behind every screen.
class BlueprintBackground extends StatelessWidget {
  const BlueprintBackground({
    super.key,
    required this.child,
    this.deep = false,
  });

  final Widget child;
  final bool deep;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GridPainter(deep ? QC.fieldDeep : QC.field),
    child: child,
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.bg);
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final p = Paint()
      ..color = QC.coherence.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.bg != bg;
}
