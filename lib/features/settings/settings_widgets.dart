part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Custom settings UI primitives — rows, toggles, sliders, inputs
// ═══════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(border: AppTheme.borderBottom),
      child: Text(
        title,
        style: AppFonts.inter(
          fontSize: AppFonts.md,
          fontWeight: FontWeight.w600,
          color: AppTheme.accent,
        ),
      ),
    );
  }
}

/// Tappable tile for data actions (export, import, QR) — styled to match
/// _SettingsRow but with icon, subtitle, and tap handler.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (hovered) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: hovered ? AppTheme.hover : null,
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.fgDim),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppFonts.inter(
                      fontSize: AppFonts.sm,
                      color: AppTheme.fg,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic settings row: label + control, minHeight 36.
class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.barHeightSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fg,
                ),
              ),
            ),
            const SizedBox(width: 24),
            child,
          ],
        ),
      ),
    );
  }
}

/// Custom toggle pill: 32x18, borderRadius 9, accent/bg4 bg, white 14x14 thumb.
class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          width: 32,
          height: 18,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? AppTheme.accent : AppTheme.bg4,
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 120),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppTheme.onAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom segment control: height 26, accent+white / bg3+fgDim.
class _SegmentControl extends StatelessWidget {
  final List<String> values;
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onChanged;

  const _SegmentControl({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < values.length; i++) {
      if (i > 0) {
        children.add(Container(width: 1, color: AppTheme.borderLight));
      }
      final isSelected = values[i] == selected;
      children.add(
        GestureDetector(
          onTap: () => onChanged(values[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: isSelected ? AppTheme.accent : AppTheme.bg3,
            alignment: Alignment.center,
            child: Text(
              labels[i],
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                color: isSelected ? AppTheme.onAccent : AppTheme.fgDim,
              ),
            ),
          ),
        ),
      );
    }

    return AppBorderedBox(
      height: AppTheme.controlHeightXs,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Custom slider: 3px track, circle thumb bg2 + 2px accent border, width 280.
class _SliderField extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 200,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.bg4,
              thumbColor: AppTheme.bg2,
              thumbShape: const _CircleThumbShape(),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          format(value),
          style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
      ],
    );
  }
}

class _CircleThumbShape extends SliderComponentShape {
  const _CircleThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 12);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    // Accent border
    canvas.drawCircle(center, 6, Paint()..color = AppTheme.accent);
    // Inner circle
    canvas.drawCircle(center, 4, Paint()..color = AppTheme.bg2);
  }
}

/// Custom input field: bg bg3, height 26, borderLight, JetBrains Mono 11px.
class _InputField extends StatelessWidget {
  final String initialValue;
  final TextInputType? keyboardType;
  final double width = 100;
  final ValueChanged<String> onSubmitted;

  const _InputField({
    required this.initialValue,
    this.keyboardType,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: AppTheme.controlHeightXs,
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.bg3,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.accent),
          ),
        ),
        onFieldSubmitted: onSubmitted,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Composed setting tiles using the primitives above
// ═══════════════════════════════════════════════════════════════════

class _ThemeTile extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ThemeTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _SettingsRow(
      label: s.theme,
      child: _SegmentControl(
        values: const ['dark', 'light', 'system'],
        labels: [s.themeDark, s.themeLight, s.themeSystem],
        selected: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _LanguageTile({required this.value, required this.onChanged});

  /// Sentinel used in PopupMenuItem instead of null (which Flutter treats as
  /// "menu dismissed"). Converted back to null in onSelected.
  static const _systemDefault = '\x00';

  static const _localeLabels = <String, (String, String)>{
    _systemDefault: ('', ''),
    'en': ('English', ''),
    'ar': ('العربية', 'Arabic'),
    'zh': ('中文', 'Chinese'),
    'fr': ('Français', 'French'),
    'de': ('Deutsch', 'German'),
    'hi': ('हिन्दी', 'Hindi'),
    'id': ('Bahasa Indonesia', 'Indonesian'),
    'ja': ('日本語', 'Japanese'),
    'ko': ('한국어', 'Korean'),
    'fa': ('فارسی', 'Persian'),
    'pt': ('Português', 'Portuguese'),
    'ru': ('Русский', 'Russian'),
    'es': ('Español', 'Spanish'),
    'tr': ('Türkçe', 'Turkish'),
    'vi': ('Tiếng Việt', 'Vietnamese'),
  };

  @override
  Widget build(BuildContext context) {
    final effectiveValue = value ?? _systemDefault;
    final s = S.of(context);
    final current = _localeLabels[effectiveValue];
    final label = effectiveValue == _systemDefault
        ? s.languageSystemDefault
        : current?.$1 ?? effectiveValue;

    return _SettingsRow(
      label: s.language,
      child: PopupMenuButton<String>(
        onSelected: (v) => onChanged(v == _systemDefault ? null : v),
        tooltip: '',
        offset: const Offset(0, AppTheme.controlHeightSm),
        constraints: const BoxConstraints(
          minWidth: 200,
          maxHeight: AppTheme.popupMaxHeight,
        ),
        color: AppTheme.bg2,
        shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
        itemBuilder: (_) => _localeLabels.entries.map((e) {
          final code = e.key;
          final (native, secondary) = e.value;
          final displayNative = code == _systemDefault
              ? s.languageSystemDefault
              : native;
          return PopupMenuItem<String>(
            value: code,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayNative,
                    style: TextStyle(
                      fontSize: AppFonts.sm,
                      color: code == effectiveValue
                          ? AppTheme.accent
                          : AppTheme.fg,
                    ),
                  ),
                ),
                if (secondary.isNotEmpty)
                  Text(
                    secondary,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
        child: Container(
          height: AppTheme.controlHeightSm,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppTheme.bg3,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.language, size: 16, color: AppTheme.fgDim),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fg,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.fgDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: title,
      child: _SliderField(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        format: format,
        onChanged: onChanged,
      ),
    );
  }
}

class _IntTile extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _IntTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: title,
      child: _InputField(
        initialValue: value.toString(),
        keyboardType: TextInputType.number,
        onSubmitted: (v) {
          final n = int.tryParse(v);
          if (n != null && n >= min && n <= max) {
            onChanged(n);
          }
        },
      ),
    );
  }
}
