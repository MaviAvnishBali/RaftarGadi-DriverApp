import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:storage/storage.dart';

Future<void> bootstrapAndRun(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();

  final environment = AppEnvironment.development();
  final storage = await StorageService.initialize();

  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(environment),
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: app,
    ),
  );
}
