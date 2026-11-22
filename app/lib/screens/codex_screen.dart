import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../controller.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/blueprint.dart';
import '../widgets/console.dart';

/// Faction habits and the real physics behind each mechanic. Optional
/// reading: nothing here is needed to play.
class CodexScreen extends StatelessWidget {
  const CodexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = GameScope.of(context).game.profile;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: QC.field,
        foregroundColor: QC.ink,
        title: Text('CODEX', style: QC.displayStyle(20)),
      ),
      body: BlueprintBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                const SectionLabel('[01] What the technobabble really is'),
                const SizedBox(height: 8),
                for (final (term, meaning) in glossary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            term,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: QC.coherence,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meaning,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: QC.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const SectionLabel('[02] The four tunings'),
                const SizedBox(height: 8),
                for (final p in TuningPreset.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            child: Text(
                              p.ket,
                              style: QC.monoStyle(14, color: QC.you),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${p.label} · ${p.gate}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: QC.ink,
                                  ),
                                ),
                                Text(
                                  p.description,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: QC.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const SectionLabel('[03] Factions'),
                const SizedBox(height: 8),
                for (final f in factions.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShipBlueprint(faction: f.id, width: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.name.toUpperCase(),
                                  style: QC.displayStyle(16, color: QC.them),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${f.shipClass} ${f.shipName} · hull ${f.hull} · systems ${f.systems} · beam ${f.beam} · barrier ${f.barrier}',
                                  style: QC.monoStyle(11),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  f.habit,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: QC.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const SectionLabel('[04] Training'),
                const SizedBox(height: 8),
                for (final u in Unlock.values)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      profile.has(u) ? Icons.check : Icons.lock_outline,
                      color: profile.has(u) ? QC.you : QC.muted,
                      size: 18,
                    ),
                    title: Text(
                      u.label,
                      style: TextStyle(
                        color: profile.has(u) ? QC.ink : QC.muted,
                      ),
                    ),
                    subtitle: u.level == 0
                        ? null
                        : Text(
                            'After ${u.level} ${u.level == 1 ? 'prize' : 'prizes'} taken',
                            style: QC.monoStyle(11),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
