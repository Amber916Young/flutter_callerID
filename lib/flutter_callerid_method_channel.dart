import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_callerid_platform_interface.dart';

/// An implementation of [FlutterCalleridPlatform] that uses method channels.
class MethodChannelFlutterCallerid extends FlutterCalleridPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_callerid');

  /// The event channel used to receive caller ID events from the native platform.
  @visibleForTesting
  final eventChannel = const EventChannel('flutter_callerid/events');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<dynamic> startUsbScan() async {
    return await methodChannel.invokeMethod('getAvailableDevices');
  }

  @override
  Future<bool> connectToHidDevice(String vid, String pid) async {
    return await methodChannel.invokeMethod('connectToHidDevice', {'vendorId': vid, 'productId': pid});
  }

  @override
  Future<bool> disconnect(String vid, String pid) async {
    return await methodChannel.invokeMethod('disconnect', {'vendorId': vid, 'productId': pid});
  }

  @override
  Future<bool> startListening(String vid, String pid) async {
    return await methodChannel.invokeMethod('startListening', {'vendorId': vid, 'productId': pid});
  }

  @override
  Future<bool> stopListening() async {
    return await methodChannel.invokeMethod('stopListening');
  }

  @override
  Stream<String> get callerIdEvents {
    return eventChannel.receiveBroadcastStream().map((event) => event.toString());
  }
}
