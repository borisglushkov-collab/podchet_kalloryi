import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'db/db_init.dart';
import 'services/health_scale/health_scale_service.dart';
import 'theme/app_theme.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  // Не рисуем контент под системной панелью навигации.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(details.toString());
  };
  try {
    await initDatabase();
    await initializeDateFormatting('ru', null);
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await HealthScaleService.instance.initialize();
    }
    runApp(const ProviderScope(child: PodchetKalloriyApp()));
  } catch (e, st) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Ошибка запуска: $e\n\n$st', textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}

class PodchetKalloriyApp extends StatelessWidget {
  const PodchetKalloriyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Подсчёт калорий',
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      home: const MainShell(),
    );
  }
}
