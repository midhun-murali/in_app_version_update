import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart' as in_app_update;
import 'package:in_app_version_update/in_app_version_update.dart';

void main() {
  group('mapInstallStatus', () {
    test('maps all plugin InstallStatus values to wrapper InstallStatus', () {
      final mapping = <in_app_update.InstallStatus, InstallStatus>{
        in_app_update.InstallStatus.unknown: InstallStatus.unknown,
        in_app_update.InstallStatus.pending: InstallStatus.pending,
        in_app_update.InstallStatus.downloading: InstallStatus.downloading,
        in_app_update.InstallStatus.downloaded: InstallStatus.downloaded,
        in_app_update.InstallStatus.installing: InstallStatus.installing,
        in_app_update.InstallStatus.installed: InstallStatus.installed,
        in_app_update.InstallStatus.failed: InstallStatus.failed,
        in_app_update.InstallStatus.canceled: InstallStatus.canceled,
      };

      for (final entry in mapping.entries) {
        final pluginVal = entry.key;
        final expected = entry.value;
        final got = mapInstallStatus(pluginVal);
        expect(got, expected, reason: 'Mapping for $pluginVal should be $expected');
      }
    });
  });

  group('isStoreVersionNewer', () {
    test('identifies a higher patch version', () {
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2.3', '1.2.2'), isTrue);
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2.3', '1.2.3'), isFalse);
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2.3', '1.2.4'), isFalse);
    });

    test('handles different lengths and padding', () {
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2', '1.1.9'), isTrue);
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2', '1.2.0'), isFalse);
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2.0', '1.2'), isFalse);
    });

    test('handles multi-digit segments', () {
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2.10', '1.2.3'), isTrue);
      expect(InAppVersionUpdate.isStoreVersionNewer('2.0', '1.9.9'), isTrue);
    });

    test('ignores non-digit characters in segments', () {
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2-beta', '1.1.9'), isTrue);
      expect(InAppVersionUpdate.isStoreVersionNewer('1.2.3+build', '1.2.3'), isFalse);
    });

    test('edge cases: empty or malformed strings', () {
      // If parsing fails, function treats missing numbers as 0.
      expect(InAppVersionUpdate.isStoreVersionNewer('', ''), isFalse);
      expect(InAppVersionUpdate.isStoreVersionNewer('1', ''), isTrue);
      expect(InAppVersionUpdate.isStoreVersionNewer('', '1'), isFalse);
      expect(InAppVersionUpdate.isStoreVersionNewer('a.b.c', '0.0.1'), isFalse);
      expect(InAppVersionUpdate.isStoreVersionNewer('0.0.2-alpha', '0.0.1'), isTrue);
    });
  });
}
