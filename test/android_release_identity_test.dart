import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release metadata preserves the v1.0.0 upgrade path', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      pubspec,
      matches(RegExp(r'^version:\s+1\.1\.0\+2$', multiLine: true)),
    );
    expect(
      gradle,
      contains('val publishedApplicationId = "com.eekashaenuga.drivetracker"'),
    );
    expect(gradle, contains('applicationId = publishedApplicationId'));
    expect(gradle, contains('val v1_0_0VersionCode = 1'));
    expect(gradle, contains('versionCode = flutter.versionCode'));
    expect(gradle, contains('flutter.versionCode <= v1_0_0VersionCode'));
    expect(
      manifest,
      contains(r'android:authorities="${applicationId}.attachments"'),
    );
  });
}
