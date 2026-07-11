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
  const ScannedScaleDevice({
    required this.label,
    required this.mac,
    this.deviceType,
    this.isPreferred = false,
  });

  final String label;
  final String mac;
  final String? deviceType;
  final bool isPreferred;
}

class HealthScaleStatus {
  const HealthScaleStatus({
    this.state = HealthScaleConnectionState.idle,
    this.message = 'Health Scale доступны только на Android и iOS.',
    this.discoveredDevices = const [],
  });

  final HealthScaleConnectionState state;
  final String message;
  final List<ScannedScaleDevice> discoveredDevices;
}

class HealthScaleService {
  HealthScaleService._();
  static final HealthScaleService instance = HealthScaleService._();

  static const String defaultMac = 'CF:E7:02:17:03:93';

  HealthScaleStatus get status => const HealthScaleStatus();

  Stream<HealthScaleStatus> get statusStream =>
      Stream.value(const HealthScaleStatus());

  Future<void> initialize() async {}

  Future<List<ScannedScaleDevice>> scanDevices({Duration? timeout}) async => [];

  Future<void> connect({String? macAddress}) async {
    throw UnsupportedError('Health Scale недоступны на этой платформе.');
  }

  void disconnect() {}

  Future<double> waitForWeight({Duration? timeout}) async {
    throw UnsupportedError('Health Scale недоступны на этой платформе.');
  }
}
