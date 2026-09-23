/// A debug build must never share the release's application id.
///
/// The owner's installed release is signed with a key this machine does not hold.
/// A same-id debug build can only reach the phone by uninstalling the release,
/// which deletes its unsent measurements and stored keys. The suffix makes the
/// debug build a separate app that installs beside it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('the release keeps its id and label', () {
    expect(gradle, contains('applicationId = "codes.afk.healthee"'));
    expect(gradle, contains('manifestPlaceholders["appLabel"] = "healthee"'));
  });

  test('THE DEBUG BUILD IS A SEPARATE APP, visibly named', () {
    final debug = RegExp(
      r'debug \{[^}]*applicationIdSuffix = "\.debug"[^}]*"healthee debug"[^}]*\}',
    );
    expect(debug.hasMatch(gradle), isTrue);
    expect(manifest, contains(r'android:label="${appLabel}"'));
  });
}
