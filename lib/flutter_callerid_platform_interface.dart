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
}
