/// In-app version update helper for Flutter
///
/// This library provides a small, opinionated wrapper around platform
/// update mechanisms:
/// - Android: Uses the `in_app_update` plugin to perform immediate or flexible
///   updates via the Play Core API.
/// - iOS: Performs a lookup against the App Store to detect newer versions and
///   optionally presents a dialog that links the user to the App Store page.
///
/// The goal is to expose a compact, testable API so host apps only need to
/// depend on this package (they won't have to import `in_app_update` directly).
///
/// Example (basic usage):
///
/// ```dart
/// final updater = InAppVersionUpdate(iosAppId: '123456789');
/// await updater.checkForUpdate(context);
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart' as in_app_update;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Which in-app update flow to request on Android devices.
///
/// - `immediate`: Forces the user to update before using the app (blocking).
/// - `flexible`: Downloads in background and allows the app to prompt for
///   installation when convenient.
enum AndroidUpdateType { immediate, flexible }

/// Public install status enum exposed by this package.
///
/// Mirrors the values in the underlying `in_app_update` plugin so consumers
/// don't need to import that package directly. These values represent the
/// lifecycle of a flexible update download/installation on Android.
///
/// Typical sequence: `pending` -> `downloading` -> `downloaded` -> `installed`.
enum InstallStatus {
  /// Status is unknown or cannot be determined.
  unknown,

  /// Update request queued and waiting (not yet downloading).
  pending,

  /// Update package is downloading.
  downloading,

  /// Update package has completed download (ready to be installed).
  downloaded,

  /// Update package installation is in progress.
  installing,

  /// Update package has been installed.
  installed,

  /// Update encountered an error and failed.
  failed,

  /// Update was cancelled by the user or system.
  canceled,
}

/// Map the plugin's `InstallStatus` to the package's public `InstallStatus`.
///
/// This helper keeps the internal dependency (`in_app_update`) encapsulated
/// so callers of this package only work with a single enum.
InstallStatus mapInstallStatus(in_app_update.InstallStatus s) {
  switch (s) {
    case in_app_update.InstallStatus.unknown:
      return InstallStatus.unknown;
    case in_app_update.InstallStatus.pending:
      return InstallStatus.pending;
    case in_app_update.InstallStatus.downloading:
      return InstallStatus.downloading;
    case in_app_update.InstallStatus.downloaded:
      return InstallStatus.downloaded;
    case in_app_update.InstallStatus.installing:
      return InstallStatus.installing;
    case in_app_update.InstallStatus.installed:
      return InstallStatus.installed;
    case in_app_update.InstallStatus.failed:
      return InstallStatus.failed;
    case in_app_update.InstallStatus.canceled:
      return InstallStatus.canceled;
  }
}

/// Helper that centralizes cross-platform update checks and flows.
///
/// Responsibilities:
/// - Check for available updates on Android and iOS.
/// - Perform or initiate in-app updates on Android (immediate or flexible).
/// - Present an App Store link or dialog on iOS.
///
/// Usage notes:
/// - Create one instance (per app or per screen) and call `checkForUpdate()`
///   from a widget's build cycle or UI event. Provide a `BuildContext` for
///   dialogs on iOS.
/// - For flexible Android updates you can either let this helper automatically
///   complete the update when the package is downloaded (`autoCompleteFlexible`)
///   or the host app can control completion by listening to
///   `installUpdateStream` or providing an `onInstallStatus` callback.
class InAppVersionUpdate {
  // iOS App Store app id used to open the App Store page directly
  // Optional: if your package is only used for Android updates you may omit
  // this value. When iOS flows are used the id must be provided.
  final String? iosAppId;

  // Timeout used for the HTTP App Store lookup.
  final Duration httpTimeout;

  // Internal subscription used when the host provides a callback to receive
  // install status updates. Call `stopInstallStatusCallback()` to cancel it.
  StreamSubscription<in_app_update.InstallStatus>? _installStatusCallbackSub;

  /// Create a new helper.
  ///
  /// Parameters:
  /// - [iosAppId]: the numeric App Store app id (required for iOS lookups).
  /// - [httpTimeout]: optional lookup timeout for network requests to the
  ///   App Store lookup API. Defaults to 10 seconds.
  InAppVersionUpdate({this.iosAppId, this.httpTimeout = const Duration(seconds: 10)});

  /// Stream of install/update statuses for flexible Android updates.
  ///
  /// Emits this package's public [InstallStatus] values. Host apps can listen
  /// to this stream to update UI (download progress, completion, etc.).
  Stream<InstallStatus> get installUpdateStream => in_app_update.InAppUpdate.installUpdateListener.map(mapInstallStatus);

  /// Stop and cancel any internal install status callback subscription that was
  /// created by passing an `onInstallStatus` callback to `checkForUpdate()`.
  ///
  /// This is a convenience around cancelling the subscription created by the
  /// helper when `onInstallStatus` was used. It is safe to call multiple
  /// times.
  Future<void> stopInstallStatusCallback() async {
    try {
      await _installStatusCallbackSub?.cancel();
    } catch (e) {
      if (kDebugMode) debugPrint('Error cancelling install status callback subscription: $e');
    } finally {
      _installStatusCallbackSub = null;
    }
  }

  /// Compares two semantic-style version strings and returns true if [store]
  /// represents a newer release than [current].
  ///
  /// This comparison tolerates non-numeric characters and differing lengths
  /// (e.g., `1.2.3` vs `1.2`). It returns `false` when versions are equal.
  ///
  /// Examples:
  /// - `isStoreVersionNewer('1.2.3', '1.2.2')` -> `true`
  /// - `isStoreVersionNewer('1.2', '1.2.0')` -> `false`
  static bool isStoreVersionNewer(String store, String current) {
    List<int> parse(String v) => v
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final sParts = parse(store);
    final cParts = parse(current);
    final maxLen = sParts.length > cParts.length ? sParts.length : cParts.length;
    for (var i = 0; i < maxLen; i++) {
      final s = i < sParts.length ? sParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (s > c) return true;
      if (s < c) return false;
    }
    return false; // same version
  }

  /// Check for updates and perform the platform-specific flow.
  ///
  /// On Android, [androidUpdateType] controls whether an immediate or
  /// flexible update is attempted (defaults to [AndroidUpdateType.immediate]).
  /// - [autoCompleteFlexible]: when true and a flexible update downloads, the
  ///   helper will automatically call `completeFlexibleUpdate()` to install it.
  /// - [onInstallStatus]: optional callback to receive install status updates
  ///   as the flexible update progresses. If provided the helper will keep a
  ///   persistent subscription until `stopInstallStatusCallback()` is called.
  ///
  /// On iOS this method performs an App Store lookup and (if an update is
  /// available) presents a blocking Cupertino-style dialog. Texts used in the
  /// dialog are configurable via the `iosDialog*` parameters.
  Future<void> checkForUpdate(
    BuildContext context, {
    AndroidUpdateType androidUpdateType = AndroidUpdateType.immediate,
    bool autoCompleteFlexible = true,
    void Function(InstallStatus)? onInstallStatus,
    // Optional iOS dialog text overrides (defaults match previous strings)
    String iosDialogTitle = 'Update available',
    String iosDialogContent = 'A newer version of this app is available on the App Store.',
    String iosLaterButtonText = 'Later',
    String iosUpdateNowButtonText = 'Update now',
    // New optional flags to let the host app restrict checks to only one
    // platform. By default both are true to preserve current behavior.
    bool checkAndroid = true,
    bool checkIos = true,
  }) async {
    if (Platform.isAndroid) {
      if (!checkAndroid) {
        if (kDebugMode) debugPrint('Skipping Android update check (disabled by parameter)');
        return;
      }
      await _handleAndroidUpdate(androidUpdateType, autoCompleteFlexible: autoCompleteFlexible, onInstallStatus: onInstallStatus);
    } else if (Platform.isIOS) {
      if (!checkIos) {
        if (kDebugMode) debugPrint('Skipping iOS update check (disabled by parameter)');
        return;
      }
      await _handleIosUpdate(
        context,
        title: iosDialogTitle,
        content: iosDialogContent,
        laterText: iosLaterButtonText,
        updateNowText: iosUpdateNowButtonText,
      );
    }
  }

  /// Complete a previously started flexible update.
  ///
  /// Hosts should call this when they want Play to install the already
  /// downloaded flexible update. This method wraps
  /// `in_app_update.InAppUpdate.completeFlexibleUpdate()` and handles errors
  /// silently in debug mode.
  Future<void> completeFlexibleUpdate() async {
    try {
      await in_app_update.InAppUpdate.completeFlexibleUpdate();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error completing flexible update: $e');
        debugPrint('$st');
      }
    }
  }

  // ANDROID: Use in_app_update (Play in-app update immediate flow)
  Future<void> _handleAndroidUpdate(
    AndroidUpdateType type, {
    bool autoCompleteFlexible = true,
    void Function(InstallStatus)? onInstallStatus,
  }) async {
    try {
      final updateInfo = await in_app_update.InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability == in_app_update.UpdateAvailability.updateAvailable) {
        if (type == AndroidUpdateType.immediate) {
          // Only perform immediate update if allowed by Play
          if (updateInfo.immediateUpdateAllowed) {
            await in_app_update.InAppUpdate.performImmediateUpdate();
          } else {
            if (kDebugMode) debugPrint('Immediate update not allowed; available flags: $updateInfo');
          }
        } else {
          // Flexible update flow
          if (updateInfo.flexibleUpdateAllowed) {
            // Start the flexible update. If autoCompleteFlexible is true, we'll
            // listen and call completeFlexibleUpdate() when the update is
            // downloaded. If false, we return early and let the host app use
            // `installUpdateStream` + `completeFlexibleUpdate()` to control
            // completion. If the host passed an `onInstallStatus` callback we
            // forward the values to it.
            final result = await in_app_update.InAppUpdate.startFlexibleUpdate();
            if (result == in_app_update.AppUpdateResult.success) {
              if (onInstallStatus != null) {
                // Cancel any previous callback subscription
                await stopInstallStatusCallback();
                // Keep a persistent subscription that the host can stop via
                // `stopInstallStatusCallback()`.
                _installStatusCallbackSub = in_app_update.InAppUpdate.installUpdateListener.listen((status) async {
                  final mapped = mapInstallStatus(status);
                  try {
                    onInstallStatus(mapped);
                  } catch (e) {
                    if (kDebugMode) debugPrint('onInstallStatus callback threw: $e');
                  }

                  if (autoCompleteFlexible && mapped == InstallStatus.downloaded) {
                    if (kDebugMode) debugPrint('Flexible update downloaded — auto-completing via callback flow');
                    try {
                      await in_app_update.InAppUpdate.completeFlexibleUpdate();
                    } catch (e, st) {
                      if (kDebugMode) {
                        debugPrint('Error completing flexible update: $e');
                        debugPrint('$st');
                      }
                    } finally {
                      await stopInstallStatusCallback();
                    }
                  }
                });
              } else if (autoCompleteFlexible) {
                // No callback provided but auto-complete requested: use a
                // temporary subscription which cancels itself after completion.
                late StreamSubscription sub;
                sub = in_app_update.InAppUpdate.installUpdateListener.listen((status) async {
                  final mapped = mapInstallStatus(status);
                  if (mapped == InstallStatus.downloaded) {
                    if (kDebugMode) debugPrint('Flexible update downloaded — completing update');
                    try {
                      await in_app_update.InAppUpdate.completeFlexibleUpdate();
                    } catch (e, st) {
                      if (kDebugMode) {
                        debugPrint('Error completing flexible update: $e');
                        debugPrint('$st');
                      }
                    } finally {
                      await sub.cancel();
                    }
                  }
                });
              } else {
                if (kDebugMode) debugPrint('Flexible update started; autoCompleteFlexible is false — host should call completeFlexibleUpdate() when ready');
              }
            } else {
              if (kDebugMode) debugPrint('Flexible update start failed or was denied: $result');
            }
          } else {
            if (kDebugMode) debugPrint('Flexible update not allowed; available flags: $updateInfo');
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('In-app update (Android) error: $e');
        debugPrint('$st');
      }
    }
  }

  // IOS: Manual version check against App Store Lookup API
  Future<void> _handleIosUpdate(
    BuildContext context, {
    String title = 'Update available',
    String content = 'A newer version of this app is available on the App Store.',
    String laterText = 'Later',
    String updateNowText = 'Update now',
  }) async {
    bool updateAvailable = false;
    try {
      updateAvailable = await _isIosUpdateAvailable();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('iOS version check failed: $e');
        debugPrint('$st');
      }
    }

    if (!updateAvailable) return;
    if (!context.mounted) return;

    await showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(content),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(laterText),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              await _openAppStorePage();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(updateNowText),
          ),
        ],
      ),
    );
  }

  Future<bool> _isIosUpdateAvailable() async {
    if (iosAppId == null || iosAppId!.isEmpty) {
      if (kDebugMode) debugPrint('iOS App ID not provided; skipping iOS update availability check');
      return false;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    final lookupUrl = Uri.parse('https://itunes.apple.com/lookup?id=$iosAppId');
    final client = HttpClient();
    client.connectionTimeout = httpTimeout;

    try {
      final request = await client.getUrl(lookupUrl);
      final response = await request.close();
      if (response.statusCode != 200) return false;
      final body = await response.transform(utf8.decoder).join();
      final jsonMap = json.decode(body) as Map<String, dynamic>;
      final results = jsonMap['results'];
      if (results is List && results.isNotEmpty) {
        final storeVersion = (results.first as Map<String, dynamic>)['version'] as String?;
        if (storeVersion == null || storeVersion.isEmpty) return false;
        return InAppVersionUpdate.isStoreVersionNewer(storeVersion, currentVersion);
      }
      return false;
    } finally {
      client.close();
    }
  }

  // Attempts to launch the App Store page for this app.
  Future<void> _openAppStorePage() async {
    if (iosAppId == null || iosAppId!.isEmpty) {
      if (kDebugMode) debugPrint('Cannot open App Store page: iosAppId not provided');
      return;
    }

    final Uri itmsUri = Uri.parse('itms-apps://itunes.apple.com/app/id$iosAppId');
    final Uri httpsUri = Uri.parse('https://apps.apple.com/app/id$iosAppId');

    try {
      if (await canLaunchUrl(itmsUri)) {
        await launchUrl(itmsUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // fall through to https
    }

    if (await canLaunchUrl(httpsUri)) {
      await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Public helper to present the iOS update dialog directly.
  ///
  /// This skips the App Store lookup and immediately shows the dialog with
  /// the provided texts. Useful for widget tests or host apps that want to
  /// present the dialog UI without performing the network check.
  Future<void> presentIosUpdateDialog(
    BuildContext context, {
    String title = 'Update available',
    String content = 'A newer version of this app is available on the App Store.',
    String laterText = 'Later',
    String updateNowText = 'Update now',
    VoidCallback? onUpdatePressed,
  }) async {
    // If no iosAppId is present and the host didn't provide an onUpdatePressed
    // callback there's nothing sensible to do when the user taps Update. Log
    // and return instead of attempting to open a malformed URL.
    if (iosAppId == null || iosAppId!.isEmpty) {
      if (onUpdatePressed == null) {
        if (kDebugMode) debugPrint('presentIosUpdateDialog called but iosAppId is not set and no onUpdatePressed callback was provided');
        return;
      }
    }

    await showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(content),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(laterText),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              if (onUpdatePressed != null) {
                onUpdatePressed();
              } else {
                await _openAppStorePage();
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(updateNowText),
          ),
        ],
      ),
    );
  }
}
