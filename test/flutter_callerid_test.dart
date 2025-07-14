import 'package:flutter_callerid/model/usb_device_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_callerid/flutter_callerid.dart';
import 'package:flutter_callerid/flutter_callerid_platform_interface.dart';
import 'package:flutter_callerid/flutter_callerid_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterCalleridPlatform with MockPlatformInterfaceMixin implements FlutterCalleridPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  // TODO: implement callerIdEvents
  Stream<String> get callerIdEvents => throw UnimplementedError();

 
  @override
  Future<bool> connectToHidDevice(String vid, String pid) {
    // TODO: implement connectToHidDevice
    throw UnimplementedError();
  }

  @override
  Future<bool> disconnect(String vid, String pid) {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<void> startUsbScan() {
    // TODO: implement startUsbScan
    throw UnimplementedError();
  }

  @override
  Future<List<UsbDeviceModel>> getPrinters() {
    // TODO: implement getAvailableDevices
    throw UnimplementedError();
  }


  @override   
  Future<bool> startListening(String vid, String pid) {
    // TODO: implement startListening
    throw UnimplementedError();
  }

  @override
  Future<bool> stopListening() {
    // TODO: implement stopListening
    throw UnimplementedError();
  }
}

void main() {
  final FlutterCalleridPlatform initialPlatform = FlutterCalleridPlatform.instance;

  test('$MethodChannelFlutterCallerid is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterCallerid>());
  });
}
