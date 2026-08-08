import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_settings.dart';
import 'app_strings.dart';
import 'home_screen.dart';

class LangbaiApp extends StatelessWidget {
  const LangbaiApp({super.key, this.platformOverride});

  final TargetPlatform? platformOverride;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final strings = AppStrings(settings.language);
    return MaterialApp(
      title: strings['appName'],
      debugShowCheckedModeBanner: false,
      locale: settings.language == AppLanguage.traditional
          ? const Locale('zh', 'TW')
          : const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('zh', 'TW')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: switch (settings.theme) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      theme: _theme(Brightness.light, settings.language, platformOverride),
      darkTheme: _theme(Brightness.dark, settings.language, platformOverride),
      home: const HomeScreen(),
    );
  }

  ThemeData _theme(
    Brightness brightness,
    AppLanguage language,
    TargetPlatform? platformOverride,
  ) {
    final dark = brightness == Brightness.dark;
    final appFontFamily = language == AppLanguage.traditional
        ? 'NotoSansCJKTC'
        : 'NotoSansCJKSC';
    const primary = Color(0xff5277ff);
    const accent = Color(0xff22c55e);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: const Color(0xff052e16),
      error: dark ? const Color(0xffff7b86) : const Color(0xffc6283e),
      onError: Colors.white,
      surface: dark ? const Color(0xff111a2b) : const Color(0xffffffff),
      onSurface: dark ? const Color(0xfff6f7fb) : const Color(0xff172033),
      surfaceContainerHighest: dark
          ? const Color(0xff1a263b)
          : const Color(0xffedf1f8),
      outline: dark ? const Color(0xff31405a) : const Color(0xffcfd7e6),
      outlineVariant: dark ? const Color(0xff243149) : const Color(0xffe2e7f0),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? const Color(0xfff6f7fb) : const Color(0xff111a2b),
      onInverseSurface: dark
          ? const Color(0xff172033)
          : const Color(0xfff6f7fb),
      inversePrimary: const Color(0xffaebfff),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff0b1220)
          : const Color(0xfff5f7fb),
      fontFamily: appFontFamily,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'Noto Sans CJK TC',
        'sans-serif',
      ],
      visualDensity: VisualDensity.standard,
      platform: platformOverride,
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff0e1728) : const Color(0xfff7f9fc),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: appFontFamily,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outline),
          textStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: appFontFamily,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : scheme.onSurface.withValues(alpha: 0.72),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : scheme.surfaceContainerHighest,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface),
      ),
    );
  }
}
