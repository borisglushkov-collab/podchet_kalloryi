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

class HealthScaleStatus {
  final HealthScaleConnectionState state;
  final String? message;
  final double? lastWeightKg;
  final String? deviceMac;
  final String? deviceName;

  const HealthScaleStatus({
    this.state = HealthScaleConnectionState.idle,
    this.message,
    this.lastWeightKg,
    this.deviceMac,
    this.deviceName,
  });

  HealthScaleStatus copyWith({
    HealthScaleConnectionState? state,
    String? message,
    double? lastWeightKg,
    String? deviceMac,
    String? deviceName,
  }) =>
      HealthScaleStatus(
        state: state ?? this.state,
        message: message ?? this.message,
        lastWeightKg: lastWeightKg ?? this.lastWeightKg,
        deviceMac: deviceMac ?? this.deviceMac,
        deviceName: deviceName ?? this.deviceName,
      );
}

class HealthScaleService {
  HealthScaleService._();
  static final HealthScaleService instance = HealthScaleService._();

  static const defaultMac = 'CF:E7:02:17:03:93';
  static const _macPrefKey = 'health_scale_mac';

  final _statusController = StreamController<HealthScaleStatus>.broadcast();
  Stream<HealthScaleStatus> get statusStream => _statusController.stream;

  HealthScaleStatus _status = const HealthScaleStatus();
  bool _sdkReady = false;
  bool _listenerRegistered = false;
  Completer<double>? _weightCompleter;

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
        message: 'SDK готов. MAC: $mac',
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

  String _normalizeMac(String mac) {
    return mac.trim().toUpperCase().replaceAll('-', ':');
  }

  Future<bool> _ensurePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final location = await Permission.locationWhenInUse.request();
    return scan.isGranted && connect.isGranted && location.isGranted;
  }

  Future<PPDeviceModel?> _scanForDevice(String targetMac, {Duration timeout = const Duration(seconds: 15)}) async {
    final normalized = _normalizeMac(targetMac);
    PPDeviceModel? found;
    final completer = Completer<PPDeviceModel?>();

    _emit(_status.copyWith(
      state: HealthScaleConnectionState.scanning,
      message: 'Поиск Health Scale ($normalized)...',
    ));

    PPBluetoothKitManager.startScan((device) {
      final mac = _normalizeMac(device.deviceMac ?? '');
      if (mac == normalized) {
        found = device;
        PPBluetoothKitManager.stopScan();
        if (!completer.isCompleted) completer.complete(found);
      }
    });

    Timer(timeout, () {
      PPBluetoothKitManager.stopScan();
      if (!completer.isCompleted) completer.complete(found);
    });

    return completer.future;
  }

  Future<void> connect({String? macAddress}) async {
    await initialize();
    if (!_sdkReady) return;

    if (!await _ensurePermissions()) {
      throw StateError('Нужны разрешения Bluetooth и геолокации');
    }

    final mac = _normalizeMac(macAddress ?? await getSavedMac());
    await saveMac(mac);

    final device = await _scanForDevice(mac);
    if (device == null) {
      throw StateError(
        'Health Scale не найдены. Включите весы, закройте Futula Scale и повторите.',
      );
    }

    _emit(_status.copyWith(
      state: HealthScaleConnectionState.connecting,
      deviceMac: mac,
      deviceName: device.deviceName,
      message: 'Подключение к ${device.deviceName ?? "Health Scale"}...',
    ));

    final connected = Completer<void>();
    PPBluetoothKitManager.connectDevice(device, callBack: (state) {
      if (state == PPDeviceConnectionState.connected) {
        _emit(_status.copyWith(
          state: HealthScaleConnectionState.connected,
          deviceMac: mac,
          deviceName: device.deviceName,
          message: 'Подключено. Встаньте на весы.',
        ));
        if (!connected.isCompleted) connected.complete();
      } else if (state == PPDeviceConnectionState.disconnected) {
        _emit(_status.copyWith(
          state: HealthScaleConnectionState.idle,
          message: 'Отключено',
        ));
      }
    });

    await connected.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('Таймаут подключения к весам'),
    );
  }

  Future<double> waitForWeight({Duration timeout = const Duration(seconds: 60)}) async {
    _weightCompleter = Completer<double>();
    _emit(_status.copyWith(
      state: HealthScaleConnectionState.measuring,
      message: 'Встаньте на весы босиком...',
    ));

    try {
      return await _weightCompleter!.future.timeout(timeout);
    } on TimeoutException {
      throw StateError('Не удалось получить вес за ${timeout.inSeconds} с');
    } finally {
      _weightCompleter = null;
    }
  }

  Future<double> syncWeightToProfile({String? macAddress}) async {
    await connect(macAddress: macAddress);
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
