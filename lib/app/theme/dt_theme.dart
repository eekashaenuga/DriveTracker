import 'package:flutter/material.dart';

import 'dt_brand_colors.dart';
import 'dt_tokens.dart';

class DTTheme {
  const DTTheme._();

  static ThemeData light() => _themeFromScheme(_scheme(Brightness.light));

  static ThemeData dark() => _themeFromScheme(_scheme(Brightness.dark));

  static ColorScheme _scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: DTBrandColors.primarySeed,
      brightness: brightness,
    );
    final mint = ColorScheme.fromSeed(
      seedColor: DTBrandColors.mintSeed,
      brightness: brightness,
    );
    final warning = ColorScheme.fromSeed(
      seedColor: DTBrandColors.warningSeed,
      brightness: brightness,
    );
    // Keep foregrounds and containers paired with their tonal palettes.
    return base.copyWith(
      surface: brightness == Brightness.light
          ? DTBrandColors.lightSurface
          : DTBrandColors.darkSurface,
      secondary: mint.primary,
      onSecondary: mint.onPrimary,
      secondaryContainer: mint.primaryContainer,
      onSecondaryContainer: mint.onPrimaryContainer,
      secondaryFixed: mint.primaryFixed,
      secondaryFixedDim: mint.primaryFixedDim,
      onSecondaryFixed: mint.onPrimaryFixed,
      onSecondaryFixedVariant: mint.onPrimaryFixedVariant,
      tertiary: warning.primary,
      onTertiary: warning.onPrimary,
      tertiaryContainer: warning.primaryContainer,
      onTertiaryContainer: warning.onPrimaryContainer,
      tertiaryFixed: warning.primaryFixed,
      tertiaryFixedDim: warning.primaryFixedDim,
      onTertiaryFixed: warning.onPrimaryFixed,
      onTertiaryFixedVariant: warning.onPrimaryFixedVariant,
    );
  }

  static ThemeData _themeFromScheme(ColorScheme scheme) {
    final textTheme = Typography.material2021().black.apply(
      displayColor: scheme.onSurface,
      bodyColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: DTRadii.cardRadius),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 64,
        shape: RoundedRectangleBorder(borderRadius: DTRadii.cardRadius),
        iconColor: scheme.primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DTSpacing.md,
          vertical: DTSpacing.xs,
        ),
        titleTextStyle: textTheme.titleSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.46),
        border: OutlineInputBorder(
          borderRadius: DTRadii.controlRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: DTRadii.controlRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DTRadii.controlRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: DTRadii.controlRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: DTRadii.controlRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DTSpacing.lg,
          vertical: DTSpacing.md,
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: DTRadii.controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DTRadii.hero),
        ),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: DTRadii.controlRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: DTRadii.controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          shape: RoundedRectangleBorder(borderRadius: DTRadii.controlRadius),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: DTRadii.controlRadius),
        side: BorderSide(color: scheme.outlineVariant),
        selectedColor: scheme.primaryContainer.withValues(alpha: 0.72),
        labelStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: DTRadii.controlRadius),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Icon(Icons.check_rounded, size: 16);
          }
          return null;
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DTRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: DTRadii.heroRadius),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: DTRadii.controlRadius),
        color: scheme.surface,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        space: DTSpacing.lg,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: DTRadii.cardRadius),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
