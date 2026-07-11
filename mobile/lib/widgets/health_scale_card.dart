import 'package:flutter/material.dart';

import '../services/health_scale/health_scale_service.dart';
import '../theme/app_theme.dart';

/// Карточка подключения Health Scale (Futula / LeFu) на экране профиля.
class HealthScaleCard extends StatefulWidget {
  const HealthScaleCard({
    super.key,
    required this.weightController,
    required this.onWeightSynced,
  });

  final TextEditingController weightController;
  final Future<void> Function(double weightKg) onWeightSynced;

  @override
  State<HealthScaleCard> createState() => _HealthScaleCardState();
}

class _HealthScaleCardState extends State<HealthScaleCard> {
  final _service = HealthScaleService.instance;
  bool _busy = false;
  ScannedScaleDevice? _lastPicked;

  Future<void> _scanAndPick() async {
    setState(() => _busy = true);
    try {
      if (!mounted) return;

      final devices = await _service.scanDevices();
      if (!mounted) return;

      if (devices.isEmpty) {
        final raw = _service.status.rawBleCount;
        _showSnack(
          raw > 0
              ? 'Найдено $raw BLE-устройств, но весы не опознаны. '
                  'Повторите поиск, стоя на платформе босиком.'
              : 'Устройства не найдены. Включите Bluetooth и геолокацию (GPS).',
        );
        return;
      }

      final auto = _service.bestMatch(devices, HealthScaleService.defaultMac);
      final picked = (auto != null && auto.fromLeFu)
          ? auto
          : await showModalBottomSheet<ScannedScaleDevice>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => _DevicePickerSheet(devices: devices),
            );
      if (picked == null || !mounted) return;

      _lastPicked = picked;
      await _connectAndWeigh(picked: picked);
    } catch (e) {
      if (mounted) {
        _showSnack('Ошибка поиска: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectAndWeigh({ScannedScaleDevice? picked}) async {
    setState(() => _busy = true);
    try {
      var target = picked ?? _lastPicked;

      if (target == null) {
        if (!mounted) return;
        final devices = await _service.scanDevices();
        if (!mounted) return;
        target = _service.bestMatch(devices, HealthScaleService.defaultMac);

        if (target != null && target.fromLeFu) {
          _lastPicked = target;
        } else if (devices.isNotEmpty && mounted) {
          target = await showModalBottomSheet<ScannedScaleDevice>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => _DevicePickerSheet(devices: devices),
          );
          if (target != null) _lastPicked = target;
        }
      }

      if (target == null) {
        _showSnack(
          'Выберите весы через «Найти весы». Ищите CF:E7 или Health Scale в списке.',
        );
        return;
      }

      await _service.connect(
        macAddress: target.mac.isNotEmpty ? target.mac : HealthScaleService.defaultMac,
        picked: target,
      );
      if (!mounted) return;
      _showSnack('Весы подключены. Встаньте на платформу…');
      final kg = await _service.waitForWeight();
      if (!mounted) return;
      widget.weightController.text = kg.toStringAsFixed(1);
      await widget.onWeightSynced(kg);
      _showSnack('Вес ${kg.toStringAsFixed(1)} кг записан в профиль');
    } catch (e) {
      if (mounted) {
        _showSnack(
          e.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      _service.disconnect();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HealthScaleStatus>(
      stream: _service.statusStream,
      initialData: _service.status,
      builder: (context, snapshot) {
        final s = snapshot.data ?? _service.status;
        final connected = s.state == HealthScaleConnectionState.connected ||
            s.state == HealthScaleConnectionState.measuring;
        final scanning = s.state == HealthScaleConnectionState.scanning ||
            s.state == HealthScaleConnectionState.connecting;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surfaceMuted),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.monitor_weight_outlined, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Health Scale',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          s.message ?? 'Нажмите «Найти весы»',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      connected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                      color: connected ? AppColors.primary : AppColors.textSecondary,
                    ),
                ],
              ),
              if (_busy && (scanning || s.state == HealthScaleConnectionState.measuring)) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                if (s.discoveredDevices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Найдено устройств: ${s.discoveredDevices.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                  ),
                ],
              ],
              if (s.rawBleCount > 0 && !_busy) ...[
                const SizedBox(height: 8),
                Text(
                  'Bluetooth-устройств в эфире: ${s.rawBleCount}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _scanAndPick,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Найти весы'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _connectAndWeigh(),
                      icon: const Icon(Icons.scale, size: 18),
                      label: const Text('Взвеситься'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '1. Закройте Futula Scale\n'
                '2. Встаньте на весы босиком\n'
                '3. Нажмите «Найти весы» → выберите Health Scale\n'
                '4. Разрешите Bluetooth и геолокацию',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DevicePickerSheet extends StatelessWidget {
  const _DevicePickerSheet({required this.devices});

  final List<ScannedScaleDevice> devices;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Выберите весы',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'LeFu-устройства отмечены звёздочкой. '
              'Если Health Scale нет — выберите устройство с MAC CF:E7… '
              'или именем Health / Scale.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, i) {
                final d = devices[i];
                return ListTile(
                  leading: Icon(
                    d.isPreferred ? Icons.star : Icons.bluetooth,
                    color: d.isPreferred ? AppColors.streak : AppColors.textSecondary,
                  ),
                  title: Text(d.label),
                  subtitle: Text(
                    '${d.mac}${d.deviceType != null ? ' · ${d.deviceType}' : ''}'
                    '${d.fromLeFu ? '' : ' · только BLE'}',
                  ),
                  onTap: () => Navigator.pop(context, d),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
