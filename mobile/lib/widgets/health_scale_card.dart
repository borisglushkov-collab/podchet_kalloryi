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

  @override
  void initState() {
    super.initState();
    _service.initialize();
  }

  Future<void> _scanAndPick() async {
    setState(() => _busy = true);
    try {
      final devices = await _service.scanDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        _showSnack(
          'Весы не найдены. Включите их, закройте Futula Scale, '
          'разрешите Bluetooth и геолокацию.',
        );
        return;
      }

      final picked = await showModalBottomSheet<ScannedScaleDevice>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _DevicePickerSheet(devices: devices),
      );
      if (picked == null || !mounted) return;

      await _connectAndWeigh(mac: picked.mac);
    } catch (e) {
      if (mounted) _showSnack('Ошибка поиска: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectAndWeigh({String? mac}) async {
    setState(() => _busy = true);
    try {
      await _service.connect(macAddress: mac);
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
              if (s.discoveredDevices.isNotEmpty && !_busy) ...[
                const SizedBox(height: 10),
                Text(
                  'Найдено: ${s.discoveredDevices.map((d) => d.label).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
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
                'Перед подключением закройте Futula Scale. '
                'Если не находит — нажмите «Найти весы» и выберите Health Scale из списка.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
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
              'Health Scale обычно отображается с именем «Health Scale» или MAC CF:E7:…',
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
                  subtitle: Text('${d.mac}${d.deviceType != null ? ' · ${d.deviceType}' : ''}'),
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
