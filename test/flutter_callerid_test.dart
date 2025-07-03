import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_callerid/flutter_callerid.dart';
import 'package:flutter_callerid/flutter_callerid_platform_interface.dart';
import 'package:flutter_callerid/flutter_callerid_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterCalleridPlatform
    with MockPlatformInterfaceMixin
    implements FlutterCalleridPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterCalleridPlatform initialPlatform = FlutterCalleridPlatform.instance;

  test('$MethodChannelFlutterCallerid is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterCallerid>());
  });

  test('getPlatformVersion', () async {
    FlutterCallerid flutterCalleridPlugin = FlutterCallerid();
    MockFlutterCalleridPlatform fakePlatform = MockFlutterCalleridPlatform();
    FlutterCalleridPlatform.instance = fakePlatform;

    expect(await flutterCalleridPlugin.getPlatformVersion(), '42');
  });
}
