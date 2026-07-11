import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pp_bluetooth_kit_flutter/ble/pp_bluetooth_kit_manager.dart';
import 'package:pp_bluetooth_kit_flutter/enums/pp_scale_enums.dart';
import 'package:pp_bluetooth_kit_flutter/model/pp_device_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HealthScaleConnectionState {
  idle,
  initializing,
  scanning,
  connecting,
  connected,
  measuring,
  error,
}

class ScannedScaleDevice {
  final PPDeviceModel model;
  final int matchScore;

  const ScannedScaleDevice(this.model, this.matchScore);

  String get label =>
      '${model.deviceName ?? "Без имени"} · ${model.deviceMac ?? "?"} · RSSI ${model.rssi ?? 0}';

  String get mac => model.deviceMac ?? '';

  String? get deviceType => model.deviceType?.name;

  bool get isPreferred => matchScore >= 80;
}

class HealthScaleStatus {
  final HealthScaleConnectionState state;
  final String? message;
  final double? lastWeightKg;
  final String? deviceMac;
  final String? deviceName;
  final List<ScannedScaleDevice> discoveredDevices;

  const HealthScaleStatus({
    this.state = HealthScaleConnectionState.idle,
    this.message,
    this.lastWeightKg,
    this.deviceMac,
    this.deviceName,
    this.discoveredDevices = const [],
  });

  HealthScaleStatus copyWith({
    HealthScaleConnectionState? state,
    String? message,
    double? lastWeightKg,
    String? deviceMac,
    String? deviceName,
    List<ScannedScaleDevice>? discoveredDevices,
  }) =>
      HealthScaleStatus(
        state: state ?? this.state,
        message: message ?? this.message,
        lastWeightKg: lastWeightKg ?? this.lastWeightKg,
        deviceMac: deviceMac ?? this.deviceMac,
        deviceName: deviceName ?? this.deviceName,
        discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      );
}

class HealthScaleService {
  HealthScaleService._();
  static final HealthScaleService instance = HealthScaleService._();

  static const defaultMac = 'CF:E7:02:17:03:93';
  static const _macPrefKey = 'health_scale_mac';
  static const _namePrefKey = 'health_scale_name';

  final _statusController = StreamController<HealthScaleStatus>.broadcast();
  Stream<HealthScaleStatus> get statusStream => _statusController.stream;
  HealthScaleStatus get status => _status;

  HealthScaleStatus _status = const HealthScaleStatus();
  bool _sdkReady = false;
  bool _listenerRegistered = false;
  Completer<double>? _weightCompleter;
  final Map<String, PPDeviceModel> _lastScan = {};

  Future<void> initialize() async {
    if (_sdkReady) return;
    _emit(_status.copyWith(state: HealthScaleConnectionState.initializing));

    try {
      final credsJson = await rootBundle.loadString('assets/lefu_credentials.json');
      final creds = jsonDecode(credsJson) as Map<String, dynamic>;
      final appKey = creds['appKey'] as String? ?? '';
      final appSecret = creds['appSecret'] as String? ?? '';
      if (appKey.isEmpty ||
          appSecret.isEmpty ||
          appKey.startsWith('YOUR_')) {
        throw StateError(
          'Укажите AppKey и AppSecret в mobile/assets/lefu_credentials.json',
        );
      }

      final config = await rootBundle.loadString('assets/lefu.config');
      PPBluetoothKitManager.initSDK(appKey, appSecret, config);
      _registerMeasurementListener();
      _sdkReady = true;

      final mac = await getSavedMac();
      _emit(_status.copyWith(
        state: HealthScaleConnectionState.idle,
        deviceMac: mac,
        message: 'SDK готов. Нажмите «Найти весы».',
      ));
    } catch (e) {
      _emit(_status.copyWith(
        state: HealthScaleConnectionState.error,
        message: e.toString(),
      ));
      rethrow;
    }
  }

  void _registerMeasurementListener() {
    if (_listenerRegistered) return;
    _listenerRegistered = true;

    PPBluetoothKitManager.addMeasurementListener(
      callBack: (measurementState, dataModel, device) {
        final weightKg = dataModel.weight / 100.0;
        if (weightKg <= 0) return;

        _emit(_status.copyWith(
          state: measurementState == PPMeasurementDataState.completed
              ? HealthScaleConnectionState.connected
              : HealthScaleConnectionState.measuring,
          lastWeightKg: weightKg,
          deviceMac: device.deviceMac ?? _status.deviceMac,
          deviceName: device.deviceName ?? _status.deviceName,
          message: measurementState == PPMeasurementDataState.completed
              ? 'Вес получен: ${weightKg.toStringAsFixed(1)} кг'
              : 'Измерение...',
        ));

        if (measurementState == PPMeasurementDataState.completed &&
            _weightCompleter != null &&
            !_weightCompleter!.isCompleted) {
          _weightCompleter!.complete(weightKg);
        }
      },
    );
  }

  Future<String> getSavedMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_macPrefKey) ?? defaultMac;
  }

  Future<void> saveMac(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_macPrefKey, _normalizeMac(mac));
    _emit(_status.copyWith(deviceMac: _normalizeMac(mac)));
  }

  Future<void> _saveDevice(PPDeviceModel device) async {
    final prefs = await SharedPreferences.getInstance();
    if (device.deviceMac != null && device.deviceMac!.isNotEmpty) {
      await prefs.setString(_macPrefKey, _normalizeMac(device.deviceMac!));
    }
    if (device.deviceName != null && device.deviceName!.isNotEmpty) {
      await prefs.setString(_namePrefKey, device.deviceName!);
    }
  }

  String _normalizeMac(String mac) {
    return mac.trim().toUpperCase().replaceAll('-', ':');
  }

  String _macKey(String mac) {
    return _normalizeMac(mac).replaceAll(':', '');
  }

  int _matchScore(PPDeviceModel device, String targetMac) {
    final name = (device.deviceName ?? '').toLowerCase();
    final mac = _macKey(device.deviceMac ?? '');
    final target = _macKey(targetMac);
    var score = 0;

    if (mac.isNotEmpty && target.isNotEmpty) {
      if (mac == target) score += 100;
      if (mac.endsWith(target.substring(target.length > 6 ? target.length - 6 : 0))) {
        score += 40;
      }
    }
    if (name.contains('health')) score += 80;
    if (name.contains('scale')) score += 30;
    if (name.contains('futula') || name.contains('lefu')) score += 20;
    if (device.deviceType == PPDeviceType.cf || device.deviceType == PPDeviceType.ce) {
      score += 25;
    }
    score += ((device.rssi ?? -100) + 100).clamp(0, 30);
    return score;
  }

  bool _looksLikeScale(PPDeviceModel device) {
    final name = (device.deviceName ?? '').toLowerCase();
    return name.contains('health') ||
        name.contains('scale') ||
        name.contains('futula') ||
        name.contains('lefu') ||
        device.deviceType == PPDeviceType.cf ||
        device.deviceType == PPDeviceType.ce;
  }

  Future<bool> _ensurePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    var locationOk = true;
    if (await Permission.locationWhenInUse.isDenied ||
        await Permission.locationWhenInUse.isPermanentlyDenied) {
      locationOk = (await Permission.locationWhenInUse.request()).isGranted;
    }
    if (!scan.isGranted || !connect.isGranted) {
      throw StateError(
        'Разрешите Bluetooth в настройках Android для «Подсчёт калорий».',
      );
    }
    return locationOk || scan.isGranted;
  }

  Future<List<ScannedScaleDevice>> scanDevices({
    String? preferredMac,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    await initialize();
    if (!_sdkReady) return [];

    await _ensurePermissions();
    PPBluetoothKitManager.disconnect();
    await PPBluetoothKitManager.stopScan();

    final targetMac = _normalizeMac(preferredMac ?? await getSavedMac());
    _lastScan.clear();

    _emit(_status.copyWith(
      state: HealthScaleConnectionState.scanning,
      message: 'Ищем весы 25 с… Закройте Futula Scale.',
      discoveredDevices: const [],
    ));

    final completer = Completer<void>();
    Timer? timer;

    await PPBluetoothKitManager.startScan((device) {
      final mac = device.deviceMac ?? '';
      if (mac.isEmpty) return;
      final key = _macKey(mac);
      final prev = _lastScan[key];
      if (prev == null || (device.rssi ?? -999) > (prev.rssi ?? -999)) {
        _lastScan[key] = device;
      }

      final ranked = _rankDevices(targetMac);
      _emit(_status.copyWith(
        discoveredDevices: ranked,
        message: ranked.isEmpty
            ? 'Поиск… найдено устройств: ${_lastScan.length}'
            : 'Найдено: ${ranked.first.label}',
      ));
    });

    timer = Timer(timeout, () async {
      await PPBluetoothKitManager.stopScan();
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
    timer.cancel();
    await PPBluetoothKitManager.stopScan();

    return _rankDevices(targetMac);
  }

  List<ScannedScaleDevice> _rankDevices(String targetMac) {
    final items = _lastScan.values
        .where(_looksLikeScale)
        .map((d) => ScannedScaleDevice(d, _matchScore(d, targetMac)))
        .toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));

    if (items.isEmpty) {
      return _lastScan.values
          .map((d) => ScannedScaleDevice(d, _matchScore(d, targetMac)))
          .toList()
        ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
    }
    return items;
  }

  Future<PPDeviceModel?> _pickDevice(String targetMac) async {
    final ranked = await scanDevices(preferredMac: targetMac);
    if (ranked.isEmpty) return null;
    return ranked.first.model;
  }

  Future<void> connect({String? macAddress, PPDeviceModel? device}) async {
    await initialize();
    if (!_sdkReady) return;

    await _ensurePermissions();

    PPDeviceModel? target = device;
    final mac = _normalizeMac(macAddress ?? await getSavedMac());

    if (target == null) {
      final existing = await PPBluetoothKitManager.fetchConnectedDevice();
      if (existing != null &&
          (_macKey(existing.deviceMac ?? '') == _macKey(mac) ||
              (existing.deviceName ?? '').toLowerCase().contains('health'))) {
        target = existing;
      }
    }

    if (target == null) {
      final key = _macKey(mac);
      target = _lastScan[key];
      if (target == null) {
        for (final candidate in _lastScan.values) {
          if (_macKey(candidate.deviceMac ?? '') == key) {
            target = candidate;
            break;
          }
        }
      }
    }

    target ??= await _pickDevice(mac);

    if (target == null) {
      final found = _lastScan.values.map((d) => d.deviceName ?? d.deviceMac).join(', ');
      throw StateError(
        found.isEmpty
            ? 'Весы не найдены. Включите их, встаньте на платформу, закройте Futula Scale и нажмите «Найти весы».'
            : 'Health Scale не найдены. Найдены: $found. Выберите устройство из списка.',
      );
    }

    await _saveDevice(target);
    final deviceMac = _normalizeMac(target.deviceMac ?? mac);

    _emit(_status.copyWith(
      state: HealthScaleConnectionState.connecting,
      deviceMac: deviceMac,
      deviceName: target.deviceName,
      message: 'Подключение к ${target.deviceName ?? "Health Scale"}...',
    ));

    final connected = Completer<void>();
    var sawConnected = false;

    PPBluetoothKitManager.connectDevice(target, callBack: (state) {
      if (state == PPDeviceConnectionState.connected) {
        sawConnected = true;
        _emit(_status.copyWith(
          state: HealthScaleConnectionState.connected,
          deviceMac: deviceMac,
          deviceName: target!.deviceName,
          message: 'Подключено. Встаньте на весы босиком.',
        ));
        if (!connected.isCompleted) connected.complete();
      } else if (state == PPDeviceConnectionState.disconnected && sawConnected) {
        _emit(_status.copyWith(
          state: HealthScaleConnectionState.idle,
          message: 'Отключено',
        ));
      } else if (state == PPDeviceConnectionState.error) {
        if (!connected.isCompleted) {
          connected.completeError(StateError('Ошибка подключения к весам'));
        }
      }
    });

    await connected.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw StateError(
        'Таймаут подключения. Закройте Futula Scale и попробуйте «Найти весы».',
      ),
    );
  }

  Future<double> waitForWeight({Duration timeout = const Duration(seconds: 90)}) async {
    _weightCompleter = Completer<double>();
    _emit(_status.copyWith(
      state: HealthScaleConnectionState.measuring,
      message: 'Встаньте на весы босиком и дождитесь стабильного веса…',
    ));

    try {
      return await _weightCompleter!.future.timeout(timeout);
    } on TimeoutException {
      throw StateError(
        'Вес не получен за ${timeout.inSeconds} с. Встаньте на весы босиком и повторите.',
      );
    } finally {
      _weightCompleter = null;
    }
  }

  Future<double> syncWeightToProfile({String? macAddress, PPDeviceModel? device}) async {
    await connect(macAddress: macAddress, device: device);
    return waitForWeight();
  }

  void disconnect() {
    PPBluetoothKitManager.disconnect();
    _emit(_status.copyWith(
      state: HealthScaleConnectionState.idle,
      message: 'Отключено',
    ));
  }

  void dispose() {
    disconnect();
    _statusController.close();
  }

  void _emit(HealthScaleStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}
