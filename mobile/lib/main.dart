import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'db/db_init.dart';
import 'screens/diary_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(details.toString());
  };
  try {
    await initDatabase();
    await initializeDateFormatting('ru', null);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DiaryScreen(),
    );
  }
}
