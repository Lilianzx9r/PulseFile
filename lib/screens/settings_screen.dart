// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/settings_service.dart';
import '../theme/pf_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = PfColors.bg(isDark);
    final cardBg  = PfColors.card(isDark);
    final border  = PfColors.border(isDark);
    final textCol = PfColors.text(isDark);
    final subCol  = PfColors.subtext;
    final accent  = PfColors.accent;

    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.notifier,
      builder: (context, settings, _) {
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(backgroundColor: bg,
              title: const Text('Réglages', style: TextStyle(fontWeight: FontWeight.w700))),
          body: ListView(padding: const EdgeInsets.all(12), children: [

            _section(context, 'Mode d\'affichage par défaut', subCol, cardBg, border, [
              _radioRow<DefaultViewMode>(
                value: DefaultViewMode.list, group: settings.defaultViewMode,
                label: 'Liste', icon: Icons.view_list_outlined, textCol: textCol,
                onChanged: (v) => SettingsService.setDefaultViewMode(v),
              ),
              _radioRow<DefaultViewMode>(
                value: DefaultViewMode.grid, group: settings.defaultViewMode,
                label: 'Grille', icon: Icons.grid_view_outlined, textCol: textCol,
                onChanged: (v) => SettingsService.setDefaultViewMode(v),
              ),
            ]),

            const SizedBox(height: 16),
            _section(context, 'Taille des vignettes (vue grille)', subCol, cardBg, border, [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(children: [
                  Icon(Icons.grid_view, size: 16, color: subCol),
                  Expanded(
                    child: Slider(
                      value: settings.gridColumns.toDouble(),
                      min: 3, max: 8, divisions: 5,
                      label: '${settings.gridColumns} colonnes',
                      activeColor: accent,
                      onChanged: (v) => SettingsService.setGridColumns(v.round()),
                    ),
                  ),
                  Icon(Icons.apps, size: 22, color: subCol),
                ]),
              ),
              Center(child: Text('${settings.gridColumns} colonnes — plus il y en a, plus les vignettes sont petites',
                  style: TextStyle(fontSize: 11, color: subCol))),
              const SizedBox(height: 4),
            ]),

            const SizedBox(height: 16),
            _section(context, 'Police de l\'explorateur', subCol, cardBg, border, [
              for (final font in kAvailableFonts)
                _radioRow<String>(
                  value: font, group: settings.fontFamily,
                  label: font, icon: Icons.text_fields, textCol: textCol,
                  onChanged: (v) => SettingsService.setFontFamily(v),
                  customStyle: font == 'Système' ? null : GoogleFonts.getFont(font),
                ),
            ]),

            const SizedBox(height: 16),
            _section(context, 'Thème', subCol, cardBg, border, [
              _radioRow<AppThemeMode>(
                value: AppThemeMode.system, group: settings.themeMode,
                label: 'Système', icon: Icons.brightness_auto, textCol: textCol,
                onChanged: (v) => SettingsService.setThemeMode(v),
              ),
              _radioRow<AppThemeMode>(
                value: AppThemeMode.light, group: settings.themeMode,
                label: 'Clair', icon: Icons.light_mode_outlined, textCol: textCol,
                onChanged: (v) => SettingsService.setThemeMode(v),
              ),
              _radioRow<AppThemeMode>(
                value: AppThemeMode.dark, group: settings.themeMode,
                label: 'Sombre', icon: Icons.dark_mode_outlined, textCol: textCol,
                onChanged: (v) => SettingsService.setThemeMode(v),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Widget _section(BuildContext context, String title, Color subCol, Color cardBg,
      Color border, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subCol)),
      ),
      Container(
        decoration: BoxDecoration(color: cardBg,
            borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _radioRow<T>({
    required T value,
    required T group,
    required String label,
    required IconData icon,
    required Color textCol,
    required ValueChanged<T> onChanged,
    TextStyle? customStyle,
  }) {
    final selected = value == group;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Icon(icon, size: 18, color: selected ? PfColors.accent : textCol.withOpacity(0.6)),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
              style: (customStyle ?? const TextStyle()).copyWith(
                  fontSize: 13, color: textCol,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400))),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18, color: selected ? PfColors.accent : textCol.withOpacity(0.4)),
        ]),
      ),
    );
  }
}
