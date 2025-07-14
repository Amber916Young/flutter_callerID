import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_callerid_method_channel.dart';

abstract class FlutterCalleridPlatform extends PlatformInterface {
  /// Constructs a FlutterCalleridPlatform.
  FlutterCalleridPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterCalleridPlatform _instance = MethodChannelFlutterCallerid();

  /// The default instance of [FlutterCalleridPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterCallerid].
  static FlutterCalleridPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterCalleridPlatform] when
  /// they register themselves.
  static set instance(FlutterCalleridPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<dynamic> startUsbScan() {
    throw UnimplementedError('startUsbScan() has not been implemented.');
  }

  Future<bool> isConnected(String vid, String pid) {
    throw UnimplementedError('isConnected(vid: $vid, pid: $pid) has not been implemented.');
  }

  Future<void> getPrinters() {
    throw UnimplementedError("getPrinters() has not been implemented.");
  }

  Future<bool> connectToHidDevice(String vid, String pid) {
    throw UnimplementedError('connectToHidDevice() has not been implemented.');
  }

  Future<bool> disconnect(String vid, String pid) {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  Future<bool> startListening(String vid, String pid) {
    throw UnimplementedError('startListening() has not been implemented.');
  }

  Future<bool> stopListening() {
    throw UnimplementedError('stopListening() has not been implemented.');
  }

  Stream<String> get callerIdEvents {
    throw UnimplementedError('callerIdEvents has not been implemented.');
  }
}
