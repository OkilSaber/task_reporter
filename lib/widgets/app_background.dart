import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass_container.dart';

/// A soft colored light, drawn as a radial gradient fading to transparent.
class _Glow {
  final Alignment center;
  final double radius;
  final Color color;
  final double alpha;

  const _Glow(this.center, this.radius, this.color, this.alpha);
}

class _BackgroundSpec {
  final String label;
  final List<Color> base;
  final List<_Glow> glows;

  const _BackgroundSpec(this.label, this.base, this.glows);
}

enum AppBackgroundStyle { aurore, prune, graphite, braise, ocean, pastel }

const _specs = {
  AppBackgroundStyle.aurore: _BackgroundSpec(
    'Aurore',
    [Color(0xFF070B18), Color(0xFF0D1326)],
    [
      _Glow(Alignment(-0.7, -1.1), 1.0, Color(0xFF1DE9B6), 0.22),
      _Glow(Alignment(0.9, -0.6), 0.9, Color(0xFF7C4DFF), 0.28),
      _Glow(Alignment(0.0, 1.3), 1.0, Color(0xFF2979FF), 0.14),
    ],
  ),
  AppBackgroundStyle.prune: _BackgroundSpec(
    'Nuit prune',
    [Color(0xFF14070F), Color(0xFF2A0F22), Color(0xFF3A1428)],
    [
      _Glow(Alignment(-1.0, -1.0), 1.0, Color(0xFFE040FB), 0.16),
      _Glow(Alignment(1.0, 1.0), 1.0, Color(0xFFFF6E40), 0.12),
    ],
  ),
  AppBackgroundStyle.graphite: _BackgroundSpec(
    'Graphite',
    [Color(0xFF0F0F12), Color(0xFF18181D)],
    [
      _Glow(Alignment(0.0, -1.4), 1.3, Color(0xFFFFFFFF), 0.07),
      _Glow(Alignment(1.0, 1.0), 0.9, Color(0xFF7C4DFF), 0.10),
    ],
  ),
  AppBackgroundStyle.braise: _BackgroundSpec(
    'Braise',
    [Color(0xFF0B0B14), Color(0xFF1A0F1A)],
    [
      _Glow(Alignment(0.2, 1.5), 1.2, Color(0xFFFF7043), 0.30),
      _Glow(Alignment(-1.0, 1.0), 0.9, Color(0xFFF50057), 0.16),
    ],
  ),
  AppBackgroundStyle.ocean: _BackgroundSpec(
    'Océan',
    [Color(0xFF031A2B), Color(0xFF06263D)],
    [
      _Glow(Alignment(-0.8, -1.0), 1.0, Color(0xFF00E5FF), 0.16),
      _Glow(Alignment(1.0, 0.8), 1.0, Color(0xFF3D5AFE), 0.22),
    ],
  ),
  AppBackgroundStyle.pastel: _BackgroundSpec(
    'Mesh pastel',
    [Color(0xFF2B2350), Color(0xFF2B2350)],
    [
      _Glow(Alignment(-1.0, -1.0), 1.1, Color(0xFFFF8A80), 0.40),
      _Glow(Alignment(1.0, -0.8), 1.1, Color(0xFF8C9EFF), 0.45),
      _Glow(Alignment(0.6, 1.2), 1.0, Color(0xFFA7FFEB), 0.25),
      _Glow(Alignment(-0.8, 1.0), 1.0, Color(0xFFEA80FC), 0.30),
    ],
  ),
};

/// Full-screen app background: a dark base with a few soft glows.
///
/// Follows the user's choice ([AppBackground.selected]) unless [style] is given.
class AppBackground extends StatelessWidget {
  final AppBackgroundStyle? style;

  const AppBackground({super.key, this.style});

  static const _prefsKey = 'backgroundStyle';

  /// The style picked in the settings, shared by every screen.
  static final selected = ValueNotifier(AppBackgroundStyle.aurore);

  static String labelOf(AppBackgroundStyle style) => _specs[style]!.label;

  /// Restores the saved choice; call once at startup.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefsKey);
    selected.value = AppBackgroundStyle.values.firstWhere(
      (s) => s.name == name,
      orElse: () => AppBackgroundStyle.aurore,
    );
  }

  static Future<void> select(AppBackgroundStyle style) async {
    selected.value = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }

  @override
  Widget build(BuildContext context) {
    final fixed = style;
    if (fixed != null) return _buildStyle(fixed);
    return ValueListenableBuilder(
      valueListenable: selected,
      builder: (context, current, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        child: KeyedSubtree(
          key: ValueKey(current),
          child: _buildStyle(current),
        ),
      ),
    );
  }

  Widget _buildStyle(AppBackgroundStyle style) {
    final spec = _specs[style]!;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: spec.base,
            ),
          ),
        ),
        for (final glow in spec.glows)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: glow.center,
                radius: glow.radius,
                colors: [
                  glow.color.withValues(alpha: glow.alpha),
                  glow.color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Settings dialog: pick the background, applied live.
Future<void> showBackgroundPicker(BuildContext context) {
  return showDialog(
    context: context,
    // Light barrier: the background behind is the live preview.
    barrierColor: Colors.black12,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 600,
          child: ValueListenableBuilder(
            valueListenable: AppBackground.selected,
            builder: (context, current, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Fond d'écran",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.25,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final style in AppBackgroundStyle.values)
                      _BackgroundTile(
                        style: style,
                        selected: style == current,
                        onTap: () => AppBackground.select(style),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Fermer',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _BackgroundTile extends StatelessWidget {
  final AppBackgroundStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _BackgroundTile({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.15),
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AppBackground(style: style),
                      // Hint of the glass UI on top, to judge the contrast.
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                      if (selected)
                        const Center(
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppBackground.labelOf(style),
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
