import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/ble/bluetooth_strap_scanner.dart';
import 'package:healthee/ble/strap_scanner.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/provider_logger.dart';
import 'package:healthee/data/api/provider_retry.dart';
import 'package:healthee/data/background/background_store.dart';
import 'package:healthee/data/background/background_task_names.dart';
import 'package:healthee/data/push/push_service.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != BackgroundTaskNames.pull && task != BackgroundTaskNames.push) {
      AppLog.info('background', 'Ignoring unrecognized task');
      return true;
    }
    final database = LocalStore();
    final container = ProviderContainer(
      retry: apiProviderRetry,
      observers: [const ProviderLogger()],
      overrides: [
        localStoreProvider.overrideWithValue(database),
        strapScannerProvider.overrideWithValue(
          const BluetoothStrapScanner(requestPermissions: false),
        ),
      ],
    );
    final store = container.read(localStoreProvider);
    final preferences = BackgroundStore(store);
    try {
      final settings = await preferences.preferences();
      if (!settings.enabled) return true;
      await preferences.report(
        'Running ${task == BackgroundTaskNames.pull ? 'strap collection' : 'server upload'}',
      );
      final result = task == BackgroundTaskNames.pull
          ? (await container
                    .read(syncEngineProvider)
                    .run(today: isoDay(DateTime.now()), onState: (_) {}))
                .summary
          : (await container.read(pushServiceProvider).run()).summary;
      await preferences.report(result);
      // A refused connection is recorded; the next periodic run retries without a retry storm.
      return true;
    } on Exception catch (error, stack) {
      AppLog.failure('background', 'running scheduled sync', error, stack);
      await preferences.report(
        'Background sync failed. Open Diagnostics and try Sync now.',
      );
      return false;
    } finally {
      container.dispose();
      await database.close();
    }
  });
}
