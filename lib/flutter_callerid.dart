
import 'flutter_callerid_platform_interface.dart';

class FlutterCallerid {
  Future<String?> getPlatformVersion() {
    return FlutterCalleridPlatform.instance.getPlatformVersion();
  }
}
