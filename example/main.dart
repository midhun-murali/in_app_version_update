import 'dart:async';

import 'package:flutter/material.dart';

// Import the library directly from the package's lib folder. Using a
// relative import here avoids package-name mismatch in local development.
import '../lib/in_app_version_update.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'In-App Version Update Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const UpdateDemoPage(),
    );
  }
}

class UpdateDemoPage extends StatefulWidget {
  const UpdateDemoPage({super.key});

  @override
  State<UpdateDemoPage> createState() => _UpdateDemoPageState();
}

class _UpdateDemoPageState extends State<UpdateDemoPage> {
  late final InAppVersionUpdate _updater;
  StreamSubscription<InstallStatus>? _installSub;
  String _statusText = 'Idle';

  @override
  void initState() {
    super.initState();
    // Example iOS App ID (replace with your real app id)
    _updater = InAppVersionUpdate(iosAppId: '284815942');
  }

  @override
  void dispose() {
    _installSub?.cancel();
    // Ensure helper's internal callback subscription (if any) is stopped
    _updater.stopInstallStatusCallback();
    super.dispose();
  }

  Future<void> _checkImmediate() async {
    setState(() => _statusText = 'Checking (immediate)...');
    await _updater.checkForUpdate(context, androidUpdateType: AndroidUpdateType.immediate);
    setState(() => _statusText = 'Done (immediate)');
  }

  Future<void> _checkFlexibleAuto() async {
    setState(() => _statusText = 'Checking (flexible, auto-complete)...');
    // This will start a flexible update and automatically complete when downloaded
    await _updater.checkForUpdate(context, androidUpdateType: AndroidUpdateType.flexible, autoCompleteFlexible: true);
    setState(() => _statusText = 'Flexible update started (auto-complete)');
  }

  Future<void> _checkFlexibleManualStream() async {
    setState(() => _statusText = 'Checking (flexible, manual / stream)...');
    // Start flexible update but don't auto-complete — host will control completion.
    await _updater.checkForUpdate(context, androidUpdateType: AndroidUpdateType.flexible, autoCompleteFlexible: false);

    // Listen for download completion and show a dialog to let the user trigger completion.
    _installSub?.cancel();
    _installSub = _updater.installUpdateStream.listen((status) {
      setState(() => _statusText = 'InstallStatus: $status');
      if (status == InstallStatus.downloaded) {
        // Show a dialog prompting the user to restart/apply update
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Update ready'),
              content: const Text('An update has been downloaded. Install now?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Later')),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _updater.completeFlexibleUpdate();
                  },
                  child: const Text('Install'),
                ),
              ],
            ),
          );
        }
      }
    });
  }

  Future<void> _checkFlexibleCallback() async {
    setState(() => _statusText = 'Checking (flexible, callback)...');
    // Use the helper's onInstallStatus callback; helper keeps the subscription
    await _updater.checkForUpdate(
      context,
      androidUpdateType: AndroidUpdateType.flexible,
      autoCompleteFlexible: false, // host will call completeFlexibleUpdate()
      onInstallStatus: (status) async {
        // Update UI
        if (mounted) setState(() => _statusText = 'Callback status: $status');

        if (status == InstallStatus.downloaded) {
          // Prompt the user and then complete
          if (mounted) {
            final doInstall = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Update ready (callback)'),
                content: const Text('An update has been downloaded. Install now?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Later')),
                  TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Install')),
                ],
              ),
            );
            if (doInstall == true) {
              await _updater.completeFlexibleUpdate();
              // stop internal callback subscription
              await _updater.stopInstallStatusCallback();
            }
          }
        }
      },
    );
  }

  Future<void> _checkIos() async {
    setState(() => _statusText = 'Checking (iOS)...');
    await _updater.checkForUpdate(context);
    setState(() => _statusText = 'Done (iOS)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('In-App Update Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Android flows use the Play In-App Update API. On iOS this will open the App Store.'),
            const SizedBox(height: 12),
            Text('Status: $_statusText'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkImmediate,
              child: const Text('Check & Run Immediate Update (Android)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _checkFlexibleAuto,
              child: const Text('Check Flexible Update (auto-complete)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _checkFlexibleManualStream,
              child: const Text('Check Flexible Update (manual completion via stream)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _checkFlexibleCallback,
              child: const Text('Check Flexible Update (callback + manual completion)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _checkIos,
              child: const Text('Check Update (iOS behavior)'),
            ),
            const SizedBox(height: 12),
            const Text('Tips:\n- Run on a real Android device with Play Store for Android flows.\n- On iOS this will open the App Store lookup dialog.'),
          ],
        ),
      ),
    );
  }
}
