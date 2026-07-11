import 'package:flutter/material.dart';

import '../services/health_scale/health_scale_service.dart';
import '../theme/app_theme.dart';

class HealthScaleCard extends StatefulWidget {
  final TextEditingController weightController;
  final Future<void> Function(double weightKg) onWeightSynced;

  const HealthScaleCard({
    super.key,
    required this.weightController,
    required this.onWeightSynced,
  });

  @override
  State<HealthScaleCard> createState() => _HealthScaleCardState();
}

class _HealthScaleCardState extends State<HealthScaleCard> {
  final _macController = TextEditingController();
  final _service = HealthScaleService.instance;
  bool _busy = false;
  HealthScaleStatus _status = const HealthScaleStatus();

  @override
  void initState() {
    super.initState();
    _loadMac();
    _service.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _loadMac() async {
    try {
      await _service.initialize();
      final mac = await _service.getSavedMac();
      if (mounted) _macController.text = mac;
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = HealthScaleStatus(
            state: HealthScaleConnectionState.error,
            message: e.toString(),
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.textPrimary,
            content: Text('$e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    await _run(() async {
      await _service.saveMac(_macController.text);
      await _service.connect(macAddress: _macController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Весы подключены. Встаньте на платформу.')),
        );
      }
    });
  }

  Future<void> _syncWeight() async {
    await _run(() async {
      await _service.saveMac(_macController.text);
      final weightKg = await _service.syncWeightToProfile(macAddress: _macController.text);
      widget.weightController.text = weightKg.toStringAsFixed(1);
      await widget.onWeightSynced(weightKg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Вес обновлён: ${weightKg.toStringAsFixed(1)} кг')),
        );
      }
    });
  }

  Color _statusColor(HealthScaleConnectionState state) {
    switch (state) {
      case HealthScaleConnectionState.connected:
      case HealthScaleConnectionState.measuring:
        return AppColors.primary;
      case HealthScaleConnectionState.error:
        return AppColors.streak;
      default:
        return AppColors.textSecondary;
    }
  }

  String _stateLabel(HealthScaleConnectionState state) {
    switch (state) {
      case HealthScaleConnectionState.idle:
        return 'Не подключено';
      case HealthScaleConnectionState.initializing:
        return 'Инициализация SDK...';
      case HealthScaleConnectionState.scanning:
        return 'Поиск весов...';
      case HealthScaleConnectionState.connecting:
        return 'Подключение...';
      case HealthScaleConnectionState.connected:
        return 'Подключено';
      case HealthScaleConnectionState.measuring:
        return 'Измерение...';
      case HealthScaleConnectionState.error:
        return 'Ошибка';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceMuted),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.monitor_weight_outlined, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Futula Health Scale',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      _stateLabel(_status.state),
                      style: TextStyle(
                        color: _statusColor(_status.state),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_status.message != null) ...[
            const SizedBox(height: 8),
            Text(
              _status.message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
          if (_status.lastWeightKg != null) ...[
            const SizedBox(height: 6),
            Text(
              'Последний замер: ${_status.lastWeightKg!.toStringAsFixed(1)} кг',
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _macController,
            decoration: InputDecoration(
              labelText: 'MAC-адрес весов',
              hintText: 'CF:E7:02:17:03:93',
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _connect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth),
                  label: const Text('Подключить'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _syncWeight,
                  icon: const Icon(Icons.sync),
                  label: const Text('Синхр. вес'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Закройте Futula Scale перед подключением. Встаньте на весы босиком для замера.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
