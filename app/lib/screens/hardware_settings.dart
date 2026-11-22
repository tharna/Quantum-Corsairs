import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../hardware/iqm_resonance.dart';
import '../theme.dart';
import '../widgets/console.dart';

/// Settings for measuring rounds on a real quantum computer through
/// IQM Resonance.
class HardwareSettings extends StatefulWidget {
  const HardwareSettings({super.key});

  @override
  State<HardwareSettings> createState() => _HardwareSettingsState();
}

class _HardwareSettingsState extends State<HardwareSettings> {
  late final TextEditingController _server;
  late final TextEditingController _computer;
  final _token = TextEditingController();
  bool _showToken = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  static const shotOptions = [1, 10, 100, 1000];

  @override
  void initState() {
    super.initState();
    final s = _controller.settings;
    _server = TextEditingController(text: s.iqmServer);
    _computer = TextEditingController(text: s.iqmComputer);
  }

  GameController get _controller => GameScope.read(context);

  @override
  void dispose() {
    _server.dispose();
    _computer.dispose();
    _token.dispose();
    super.dispose();
  }

  void _saveFields() {
    final c = _controller;
    final server = _server.text.trim().isEmpty
        ? IqmConfig.defaultServer
        : _server.text.trim();
    final computer = _computer.text.trim().isEmpty
        ? IqmConfig.defaultComputer
        : _computer.text.trim();
    if (server != c.settings.iqmServer || computer != c.settings.iqmComputer) {
      c.updateSettings(
        c.settings.copyWith(iqmServer: server, iqmComputer: computer),
      );
    }
  }

  Future<void> _saveToken() async {
    final t = _token.text.trim();
    if (t.isEmpty) return;
    await _controller.setIqmToken(t);
    _token.clear();
    if (mounted) setState(() => _testResult = null);
  }

  Future<void> _test() async {
    _saveFields();
    await _saveToken();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final msg = await _controller.testIqmConnection();
      if (mounted) {
        setState(() {
          _testResult = msg;
          _testOk = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResult = '$e';
          _testOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  InputDecoration _field(String label, {String? hint, Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        labelStyle: const TextStyle(color: QC.muted),
        hintStyle: const TextStyle(color: QC.muted),
        enabledBorder: const OutlineInputBorder(
          borderRadius: QC.radius,
          borderSide: BorderSide(color: QC.grid),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: QC.radius,
          borderSide: BorderSide(color: QC.quantum),
        ),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final s = c.settings;
    return Panel(
      borderColor: s.hardware ? QC.quantum : QC.grid,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Quantum hardware · IQM Resonance'),
          const SizedBox(height: 8),
          const Text(
            'Measure each round on a real quantum computer. The round is '
            'compiled to the processor\'s native prx and cz gates and run '
            'through your IQM Resonance account. The first shot decides the '
            'round; the report shows every shot against the ideal odds.',
            style: TextStyle(fontSize: 13, height: 1.4, color: QC.ink),
          ),
          const SizedBox(height: 6),
          const Text(
            'Jobs use your Resonance credits and can queue for minutes. If '
            'anything fails, or you leave the queue, the round is simulated.',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: QC.muted),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Measure on real hardware',
              style: TextStyle(color: QC.ink),
            ),
            subtitle: Text(
              c.hasIqmToken
                  ? 'API token saved on this device'
                  : 'Add an API token first',
              style: const TextStyle(fontSize: 12.5, color: QC.muted),
            ),
            value: s.hardware && c.hasIqmToken,
            onChanged: c.hasIqmToken
                ? (v) => c.updateSettings(s.copyWith(hardware: v))
                : null,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _token,
            obscureText: !_showToken,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: QC.ink),
            decoration: _field(
              c.hasIqmToken ? 'Replace API token' : 'API token',
              hint: 'From your IQM Resonance account',
              suffix: IconButton(
                tooltip: _showToken ? 'Hide token' : 'Show token',
                icon: Icon(
                  _showToken ? Icons.visibility_off : Icons.visibility,
                  color: QC.muted,
                ),
                onPressed: () => setState(() => _showToken = !_showToken),
              ),
            ),
            onSubmitted: (_) => _saveToken(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _computer,
            autocorrect: false,
            style: const TextStyle(color: QC.ink),
            decoration: _field(
              'Quantum computer',
              hint: IqmConfig.defaultComputer,
            ),
            onSubmitted: (_) => _saveFields(),
            onTapOutside: (_) => _saveFields(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _server,
            autocorrect: false,
            keyboardType: TextInputType.url,
            style: const TextStyle(color: QC.ink),
            decoration: _field('Server', hint: IqmConfig.defaultServer),
            onSubmitted: (_) => _saveFields(),
            onTapOutside: (_) => _saveFields(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Shots per round', style: TextStyle(color: QC.ink)),
              ),
              DropdownButton<int>(
                value: shotOptions.contains(s.iqmShots) ? s.iqmShots : 100,
                dropdownColor: QC.film,
                style: QC.monoStyle(13, color: QC.ink),
                items: [
                  for (final n in shotOptions)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (n) => c.updateSettings(s.copyWith(iqmShots: n)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GhostButton(
            label: _testing ? 'Testing…' : 'Save and test connection',
            color: QC.quantum,
            display: false,
            onPressed: _testing ? null : _test,
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _testOk ? QC.you : QC.them,
                  ),
                ),
              ),
            ),
          if (c.hasIqmToken)
            TextButton(
              onPressed: () async {
                await c.setIqmToken('');
                if (mounted) setState(() => _testResult = null);
              },
              child: const Text(
                'Remove saved token',
                style: TextStyle(color: QC.them),
              ),
            ),
        ],
      ),
    );
  }
}
