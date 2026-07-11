import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  final PPDeviceModel? model;
  final int matchScore;
  final String label;
  final String mac;
  final String? deviceType;
  final bool isPreferred;
  final bool fromLeFu;

  const ScannedScaleDevice({
    this.model,
    required this.matchScore,
    required this.label,
    required this.mac,
    this.deviceType,
    this.isPreferred = false,
    this.fromLeFu = true,
  });

  factory ScannedScaleDevice.fromLeFu(PPDeviceModel device, int score) {
    return ScannedScaleDevice(
      model: device,
      matchScore: score,
      label:
          '${device.deviceName ?? "Без имени"} · ${device.deviceMac ?? "?"} · RSSI ${device.rssi ?? 0}',
      mac: device.deviceMac ?? '',
      deviceType: device.deviceType?.name,
      isPreferred: score >= 80,
      fromLeFu: true,
    );
  }

  factory ScannedScaleDevice.fromBle(String name, String mac, int rssi, int score) {
    return ScannedScaleDevice(
      model: null,
      matchScore: score,
      label: '$name · $mac · RSSI $rssi',
      mac: mac,
      isPreferred: score >= 80,
      fromLeFu: false,
    );
  }
}

class HealthScaleStatus {
  final HealthScaleConnectionState state;
  final String? message;
  final double? lastWeightKg;
  final String? deviceMac;
  final String? deviceName;
  final List<ScannedScaleDevice> discoveredDevices;
  final int rawBleCount;

  const HealthScaleStatus({
    this.state = HealthScaleConnectionState.idle,
    this.message,
    this.lastWeightKg,
    this.deviceMac,
    this.deviceName,
    this.discoveredDevices = const [],
    this.rawBleCount = 0,
  });

  HealthScaleStatus copyWith({
    HealthScaleConnectionState? state,
    String? message,
    double? lastWeightKg,
    String? deviceMac,
    String? deviceName,
    List<ScannedScaleDevice>? discoveredDevices,
    int? rawBleCount,
  }) =>
      HealthScaleStatus(
        state: state ?? this.state,
        message: message ?? this.message,
        lastWeightKg: lastWeightKg ?? this.lastWeightKg,
        deviceMac: deviceMac ?? this.deviceMac,
        deviceName: deviceName ?? this.deviceName,
        discoveredDevices: discoveredDevices ?? this.discoveredDevices,
        rawBleCount: rawBleCount ?? this.rawBleCount,
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
  int _rawBleCount = 0;

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

      try {
        final deviceJson = await rootBundle.loadString('assets/lefu_device.json');
        PPBluetoothKitManager.setDeviceSetting(deviceJson);
      } catch (_) {
        // Не критично — lefu.config уже содержит базовые профили
      }

      _registerSdkListeners();
      _registerMeasurementListener();
      _sdkReady = true;

      final mac = await getSavedMac();
      _emit(_status.copyWith(
        state: HealthScaleConnectionState.idle,
        deviceMac: mac,
        message: 'SDK готов. Встаньте на весы и нажмите «Найти весы».',
      ));
    } catch (e) {
      _emit(_status.copyWith(
        state: HealthScaleConnectionState.error,
        message: e.toString(),
      ));
      rethrow;
    }
  }

  void _registerSdkListeners() {
    if (_listenerRegistered) return;
    _listenerRegistered = true;

    PPBluetoothKitManager.addBlePermissionListener(callBack: (state) {
      _emit(_status.copyWith(message: 'Bluetooth: $state'));
    });

    PPBluetoothKitManager.addScanStateListener(callBack: (scanning) {
      if (scanning) {
        _emit(_status.copyWith(state: HealthScaleConnectionState.scanning));
      }
    });
  }

  void _registerMeasurementListener() {
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
              : 'Измерение…',
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

  String _deviceKey(PPDeviceModel device) {
    final mac = _macKey(device.deviceMac ?? '');
    if (mac.isNotEmpty) return mac;
    return '${device.deviceName ?? "unknown"}-${device.rssi ?? 0}';
  }

  int _matchScore(String name, String mac, int? rssi, String? deviceTypeName, String targetMac) {
    final lowerName = name.toLowerCase();
    final key = _macKey(mac);
    final target = _macKey(targetMac);
    var score = 0;

    if (key.isNotEmpty && target.isNotEmpty) {
      if (key == target) score += 100;
      if (key.endsWith(target.substring(target.length > 6 ? target.length - 6 : 0))) {
        score += 40;
      }
    }
    if (key.startsWith('CFE7') || mac.toUpperCase().startsWith('CF:E7')) score += 90;
    if (lowerName.contains('health')) score += 80;
    if (lowerName.contains('scale')) score += 30;
    if (lowerName.contains('futula') || lowerName.contains('lefu')) score += 20;
    if (deviceTypeName == 'cf' || deviceTypeName == 'ce') score += 25;
    score += ((rssi ?? -100) + 100).clamp(0, 30);
    return score;
  }

  bool _isTargetScale(String name, String mac, String targetMac) {
    if (_macKey(mac) == _macKey(targetMac)) return true;
    if (mac.toUpperCase().startsWith('CF:E7') || _macKey(mac).startsWith('CFE7')) return true;
    return _looksLikeScaleName(name);
  }

  String _bleDisplayName(ScanResult result) {
    final adv = result.advertisementData;
    if (adv.advName.isNotEmpty) return adv.advName;
    if (result.device.platformName.isNotEmpty) return result.device.platformName;
    if (adv.manufacturerData.isNotEmpty) {
      for (final entry in adv.manufacturerData.entries) {
        final bytes = entry.value;
        if (bytes.length >= 6) {
          final hex = bytes
              .take(6)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(':')
              .toUpperCase();
          if (hex.startsWith('CF:E7') || hex.contains('E7')) {
            return 'Health Scale? ($hex)';
          }
        }
      }
    }
    return 'BLE ${result.device.remoteId.str}';
  }

  int _matchScoreDevice(PPDeviceModel device, String targetMac) {
    return _matchScore(
      device.deviceName ?? '',
      device.deviceMac ?? '',
      device.rssi,
      device.deviceType?.name,
      targetMac,
    );
  }

  bool _looksLikeScaleName(String name) {
    final lower = name.toLowerCase();
    return lower.contains('health') ||
        lower.contains('scale') ||
        lower.contains('futula') ||
        lower.contains('lefu');
  }

  Future<void> _ensureBluetoothReady() async {
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('Bluetooth не поддерживается на этом устройстве.');
    }

    var adapterState = FlutterBluePlus.adapterStateNow;
    if (adapterState != BluetoothAdapterState.on) {
      adapterState = await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => adapterState,
          );
    }
    if (adapterState != BluetoothAdapterState.on) {
      throw StateError('Включите Bluetooth в настройках телефона.');
    }
  }

  Future<void> _ensurePermissions() async {
    await _ensureBluetoothReady();

    if (Platform.isAndroid) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      final location = await Permission.locationWhenInUse.request();

      if (!scan.isGranted || !connect.isGranted) {
        throw StateError(
          'Разрешите Bluetooth в настройках Android для «Подсчёт калорий».',
        );
      }
      if (!location.isGranted) {
        throw StateError(
          'Разрешите геолокацию — Android требует её для поиска Bluetooth-устройств.',
        );
      }
    }
  }

  Future<List<ScannedScaleDevice>> scanDevices({
    String? preferredMac,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await initialize();
    if (!_sdkReady) return [];

    await _ensurePermissions();

    final targetMac = _normalizeMac(preferredMac ?? await getSavedMac());
    _lastScan.clear();
    _rawBleCount = 0;

    _emit(_status.copyWith(
      state: HealthScaleConnectionState.scanning,
      message: 'Ищем весы ${timeout.inSeconds} с… Встаньте на платформу. Закройте Futula Scale.',
      discoveredDevices: const [],
      rawBleCount: 0,
    ));

    final lefuFound = <String, ScannedScaleDevice>{};
    final bleFound = <String, ScannedScaleDevice>{};
    StreamSubscription<List<ScanResult>>? bleSub;

    try {
      bleSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          final mac = result.device.remoteId.str;
          if (!bleFound.containsKey(mac)) _rawBleCount++;
          final name = _bleDisplayName(result);
          final score = _matchScore(name, mac, result.rssi, null, targetMac);
          bleFound[mac] = ScannedScaleDevice.fromBle(name, mac, result.rssi, score);
        }
        _emitScanProgress(lefuFound, bleFound, targetMac);
      });

      await PPBluetoothKitManager.startScan((device) {
        final key = _deviceKey(device);
        final prev = _lastScan[key];
        if (prev == null || (device.rssi ?? -999) > (prev.rssi ?? -999)) {
          _lastScan[key] = device;
        }

        final mac = device.deviceMac ?? '';
        if (mac.isNotEmpty) {
          lefuFound[mac] = ScannedScaleDevice.fromLeFu(device, _matchScoreDevice(device, targetMac));
        }
        _emitScanProgress(lefuFound, bleFound, targetMac);
      });

      // Параллельный системный BLE-скан (не await — иначе LeFu ждёт 30 с)
      // ignore: unawaited_futures
      FlutterBluePlus.startScan(timeout: timeout);

      await Future<void>.delayed(timeout);
    } finally {
      await FlutterBluePlus.stopScan();
      await bleSub?.cancel();
      await PPBluetoothKitManager.stopScan();
    }

    return _mergeScanResults(lefuFound, bleFound, targetMac);
  }

  void _emitScanProgress(
    Map<String, ScannedScaleDevice> lefuFound,
    Map<String, ScannedScaleDevice> bleFound,
    String targetMac,
  ) {
    final merged = _mergeScanResults(lefuFound, bleFound, targetMac);
    _emit(_status.copyWith(
      discoveredDevices: merged,
      rawBleCount: _rawBleCount,
      message: merged.isEmpty
          ? 'Поиск… BLE-устройств: $_rawBleCount, LeFu: ${lefuFound.length}. Встаньте на весы.'
          : 'Найдено: ${merged.first.label}',
    ));
  }

  List<ScannedScaleDevice> _mergeScanResults(
    Map<String, ScannedScaleDevice> lefuFound,
    Map<String, ScannedScaleDevice> bleFound,
    String targetMac,
  ) {
    final merged = <String, ScannedScaleDevice>{...lefuFound};

    for (final entry in bleFound.entries) {
      merged.putIfAbsent(entry.key, () => entry.value);
    }

    final items = merged.values.toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));

    final preferred = items.where((d) => _isTargetScale(
          d.label.split(' · ').first,
          d.mac,
          targetMac,
        ));
    if (preferred.isNotEmpty) {
      final rest = items.where((d) => !preferred.contains(d));
      return [...preferred, ...rest];
    }
    return items;
  }

  ScannedScaleDevice? bestMatch(List<ScannedScaleDevice> devices, String targetMac) {
    if (devices.isEmpty) return null;
    for (final d in devices) {
      if (d.fromLeFu && d.isPreferred) return d;
    }
    for (final d in devices) {
      if (_macKey(d.mac) == _macKey(targetMac)) return d;
    }
    for (final d in devices) {
      if (_macKey(d.mac).startsWith('CFE7') || d.mac.toUpperCase().startsWith('CF:E7')) {
        return d;
      }
    }
    for (final d in devices) {
      if (_looksLikeScaleName(d.label)) return d;
    }
    return devices.first;
  }

  List<ScannedScaleDevice> _rankDevices(String targetMac) {
    return _lastScan.values
        .map((d) => ScannedScaleDevice.fromLeFu(d, _matchScoreDevice(d, targetMac)))
        .toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
  }

  Future<PPDeviceModel?> _waitForLeFuDevice(
    String targetMac, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    PPDeviceModel? found;
    final completer = Completer<PPDeviceModel?>();
    StreamSubscription<List<ScanResult>>? bleSub;

    _emit(_status.copyWith(
      state: HealthScaleConnectionState.scanning,
      message: 'Ждём сигнал весов ${timeout.inSeconds} с… Встаньте на платформу босиком.',
    ));

    bleSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final mac = result.device.remoteId.str;
        if (_macKey(mac) == _macKey(targetMac) ||
            _macKey(mac).startsWith('CFE7') ||
            _looksLikeScaleName(_bleDisplayName(result))) {
          _emit(_status.copyWith(
            message: 'Bluetooth видит весы: ${_bleDisplayName(result)} ($mac)',
          ));
        }
      }
    });

    await PPBluetoothKitManager.startScan((device) {
      final mac = device.deviceMac ?? '';
      if (mac.isEmpty) return;

      _lastScan[_deviceKey(device)] = device;

      final matches = _macKey(mac) == _macKey(targetMac) ||
          _macKey(mac).startsWith('CFE7') ||
          (device.deviceName ?? '').toLowerCase().contains('health');

      if (matches && !completer.isCompleted) {
        found = device;
        completer.complete(device);
      }

      _emit(_status.copyWith(
        discoveredDevices: _rankDevices(targetMac),
        message: 'LeFu: ${device.deviceName ?? mac}',
      ));
    });

    // ignore: unawaited_futures
    FlutterBluePlus.startScan(timeout: timeout);

    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await FlutterBluePlus.stopScan();
      await bleSub?.cancel();
      if (found == null) {
        await PPBluetoothKitManager.stopScan();
      }
    }
  }

  Future<void> connect({
    String? macAddress,
    PPDeviceModel? device,
    ScannedScaleDevice? picked,
  }) async {
    await initialize();
    if (!_sdkReady) return;

    await _ensurePermissions();

    PPDeviceModel? target = device ?? picked?.model;
    final mac = _normalizeMac(macAddress ?? picked?.mac ?? await getSavedMac());

    if (target == null) {
      final key = _macKey(mac);
      for (final candidate in _lastScan.values) {
        if (_macKey(candidate.deviceMac ?? '') == key) {
          target = candidate;
          break;
        }
      }
    }

    if (target == null) {
      final existing = await PPBluetoothKitManager.fetchConnectedDevice();
      if (existing != null &&
          (_macKey(existing.deviceMac ?? '') == _macKey(mac) ||
              (existing.deviceName ?? '').toLowerCase().contains('health'))) {
        target = existing;
      }
    }

    target ??= await _waitForLeFuDevice(mac);

    if (target == null) {
      final hint = _rawBleCount > 0
          ? 'LeFu SDK не распознал весы среди $_rawBleCount BLE-устройств. '
              'Нажмите «Найти весы», выберите устройство с CF:E7 или Health Scale в списке.'
          : 'Bluetooth не видит устройств. Включите геолокацию (GPS), Bluetooth и разрешения.';
      throw StateError(hint);
    }

    await _saveDevice(target);
    final deviceMac = _normalizeMac(target.deviceMac ?? mac);

    _emit(_status.copyWith(
      state: HealthScaleConnectionState.connecting,
      deviceMac: deviceMac,
      deviceName: target.deviceName,
      message: 'Подключение к ${target.deviceName ?? "Health Scale"}…',
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
      const Duration(seconds: 35),
      onTimeout: () => throw StateError(
        'Таймаут подключения. Закройте Futula Scale и повторите «Найти весы».',
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

  Future<double> syncWeightToProfile({
    String? macAddress,
    PPDeviceModel? device,
    ScannedScaleDevice? picked,
  }) async {
    await connect(macAddress: macAddress, device: device, picked: picked);
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
