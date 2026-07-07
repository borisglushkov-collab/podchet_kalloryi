import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/api_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();
  final _cityController = TextEditingController();
  bool? _serverOk;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _urlController.text = await SettingsService.getBackendUrl();
    _cityController.text = await SettingsService.getCity();
    await _checkServer();
  }

  Future<void> _checkServer() async {
    setState(() => _checking = true);
    final ok = await ref
        .read(apiServiceProvider)
        .checkHealth(baseUrl: _urlController.text);
    if (mounted) {
      setState(() {
        _serverOk = ok;
        _checking = false;
      });
    }
  }

  Future<void> _save() async {
    await SettingsService.setBackendUrl(_urlController.text);
    await SettingsService.setCity(_cityController.text);
    ref.invalidate(backendHealthProvider);
    await _checkServer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки сохранены')),
      );
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Адрес сервера',
              hintText: 'http://5.42.111.122',
              helperText: 'VPS (nginx, порт 80) или локально: http://127.0.0.1:8000',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityController,
            decoration: const InputDecoration(
              labelText: 'Город (для Перекрёстка)',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_checking)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_serverOk == true)
                const Icon(Icons.check_circle, color: Colors.green)
              else if (_serverOk == false)
                const Icon(Icons.error, color: Colors.red)
              else
                const SizedBox.shrink(),
              const SizedBox(width: 8),
              Text(
                _serverOk == true
                    ? 'Сервер доступен'
                    : _serverOk == false
                        ? 'Сервер недоступен'
                        : 'Проверка...',
              ),
              const Spacer(),
              TextButton(onPressed: _checkServer, child: const Text('Проверить')),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
          const SizedBox(height: 24),
          const Text(
            'Для отладки по USB: adb reverse tcp:8000 tcp:8000\n'
            'Тогда используйте http://127.0.0.1:8000',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
