import 'dart:typed_data';
import 'dart:io';

import 'package:drivetracker/app/theme/dt_brand_colors.dart';
import 'package:drivetracker/app/theme/dt_theme.dart';
import 'package:drivetracker/core/database/database_migrations.dart';
import 'package:drivetracker/core/product_identity.dart';
import 'package:drivetracker/features/data_safety/domain/backup_manifest.dart';
import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical public identity is Vehnora', () {
    expect(ProductIdentity.name, 'Vehnora');
    expect(ProductIdentity.tagline, 'Your vehicle, organised.');
    expect(ProductIdentity.displayDescription, 'Vehnora — Vehicle Manager');
    expect(ProductIdentity.notificationChannelName, 'Vehnora reminders');
    expect(ProductIdentity.csvExportTitle, 'Vehnora CSV export');
  });

  test('rebranding retains persistent V1 identity and backup contract', () {
    expect(DatabaseMigrations.schemaVersion, 5);
    expect(DataSafetyService.backupFormatVersion, 1);
    expect(
      DataSafetyService.backupMimeType,
      'application/vnd.drivetracker.backup',
    );
    final manifest = BackupManifest(
      backupFormatVersion: 1,
      schemaVersion: 4,
      createdAtUtc: DateTime.utc(2026),
      databasePath: 'database.sqlite',
      databaseBytes: 1,
      tableCounts: const {},
      attachments: const [],
    );
    expect(manifest.toJson()['app'], 'DriveTracker');
    expect(BackupManifest.fromJson(manifest.toJson()).backupFormatVersion, 1);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      matches(RegExp(r'^name: drivetracker$', multiLine: true)),
    );
    expect(
      File('lib/core/database/app_database.dart').readAsStringSync(),
      contains("'drive_tracker.db'"),
    );
    final safety = File(
      'lib/features/data_safety/domain/data_safety_service.dart',
    ).readAsStringSync();
    expect(safety, contains("'dtbackup'"));
    expect(safety, contains("'drivetracker/data_safety'"));
    expect(
      File('lib/features/attachments/domain/attachment_io.dart')
          .readAsStringSync(),
      contains("'drivetracker/attachments'"),
    );
    expect(
      File('lib/core/notifications/local_notification_service.dart')
          .readAsStringSync(),
      contains("'drive_tracker_reminders'"),
    );
  });

  for (final theme in [DTTheme.light(), DTTheme.dark()]) {
    test('brand roles have readable contrast in ${theme.brightness}', () {
      expect(theme.useMaterial3, isTrue);
      final c = theme.colorScheme;
      for (final pair in <(Color, Color)>[
        (c.primary, c.onPrimary),
        (c.primaryContainer, c.onPrimaryContainer),
        (c.secondary, c.onSecondary),
        (c.secondaryContainer, c.onSecondaryContainer),
        (c.tertiary, c.onTertiary),
        (c.tertiaryContainer, c.onTertiaryContainer),
        (c.error, c.onError),
        (c.surface, c.onSurface),
        (c.surfaceContainerHighest, c.onSurfaceVariant),
        (c.inverseSurface, c.onInverseSurface),
        (c.surface, c.primary),
        (c.surface, c.secondary),
        (c.surface, c.tertiary),
      ]) {
        expect(
          _contrast(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${pair.$1} / ${pair.$2}',
        );
      }
    });
  }

  test('native startup surfaces match the centralized brand palette', () {
    for (final entry in <(String, Color)>[
      ('values', DTBrandColors.lightSurface),
      ('values-night', DTBrandColors.darkSurface),
    ]) {
      final xml = File('android/app/src/main/res/${entry.$1}/colors.xml')
          .readAsStringSync();
      final rgb = entry.$2
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toUpperCase();
      expect(xml, contains('name="brand_splash_background">#$rgb</color>'));
    }
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('<adaptive-icon'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('@color/brand_launcher_background'));
    expect(adaptive, isNot(contains('<monochrome')));
    final themed = File(
      'android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml',
    ).readAsStringSync();
    expect(themed, contains('@drawable/ic_launcher_monochrome'));
    expect(
      File('android/app/src/main/res/drawable-nodpi/brand_mark_temporary.png')
          .existsSync(),
      isFalse,
    );
    for (final density in <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      _expectPngSize(
        'android/app/src/main/res/mipmap-${density.key}/ic_launcher.png',
        density.value,
      );
    }
    _expectPngSize(
      'android/app/src/main/res/drawable-xxxhdpi/vehnora_launcher_foreground.png',
      432,
    );
    _expectPngSize(
      'android/app/src/main/res/drawable-xxxhdpi/vehnora_launcher_monochrome.png',
      432,
    );
    _expectPngSize(
      'android/app/src/main/res/drawable-xxxhdpi/vehnora_splash.png',
      1152,
    );
    for (final variant in <String, int>{
      '': 64,
      '2.0x/': 128,
      '3.0x/': 192,
    }.entries) {
      _expectPngSize(
        'assets/branding/flutter/${variant.key}vehnora_mark.png',
        variant.value,
      );
    }
    for (final qualifier in ['values-v31', 'values-night-v31']) {
      expect(
        File('android/app/src/main/res/$qualifier/styles.xml')
            .readAsStringSync(),
        contains('@drawable/vehnora_splash'),
      );
    }
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}

void _expectPngSize(String path, int dimension) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  final header = ByteData.sublistView(bytes);
  expect(header.getUint32(16), dimension, reason: path);
  expect(header.getUint32(20), dimension, reason: path);
}
