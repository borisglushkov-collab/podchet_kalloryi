import 'dart:async';

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

  final _statusController = StreamController<HealthScaleStatus>.broadcast();
  Stream<HealthScaleStatus> get statusStream => _statusController.stream;

  Future<void> initialize() async {}

  Future<String> getSavedMac() async => defaultMac;

  Future<void> saveMac(String mac) async {}

  Future<void> connect({String? macAddress}) async {
    throw UnsupportedError('Bluetooth-весы доступны только в Android-приложении');
  }

  Future<double> waitForWeight({Duration timeout = const Duration(seconds: 60)}) async {
    throw UnsupportedError('Bluetooth-весы доступны только в Android-приложении');
  }

  Future<double> syncWeightToProfile({String? macAddress}) async {
    throw UnsupportedError('Bluetooth-весы доступны только в Android-приложении');
  }

  void disconnect() {}

  void dispose() {
    _statusController.close();
  }
}
