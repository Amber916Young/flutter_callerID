import 'package:flutter_callerid/service/devices_service.dart';

import 'flutter_callerid_platform_interface.dart';
import 'model/usb_device_model.dart';

class FlutterCallerid {
  Stream<List<DeviceModel>> get devicesStream {
    return DevicesService().devicesStream;
  }

  Stream<Map<String, dynamic>> get callerIdStream {
    return DevicesService().callerIdStream;
  }

  Stream<ScanningEvent> get scanningStream {
    return DevicesService().scanningStream;
  }

  bool get isBleScanning => DevicesService().isBleScanning;
  bool get isNetworkScanning => DevicesService().isNetworkScanning;
  bool get isUsbScanning => DevicesService().isUsbScanning;
  bool get isAnyScanning => DevicesService().isAnyScanning;

  /// Get all available USB  devices
  Future<void> getDevices({
    List<ConnectionType> connectionTypes = const [ConnectionType.USB],
    bool androidUsesFineLocation = false,
    int cloudPrinterNum = 1,
  }) async {
    DevicesService().getDevices(
      connectionTypes: connectionTypes,
      androidUsesFineLocation: androidUsesFineLocation,
      cloudPrinterNum: cloudPrinterNum,
    );
  }

  Future<void> stopScan() async {
    DevicesService().stopScan();
  }

  /// Connect to a specific HID device by device ID
  Future<bool> connectToHidDevice(DeviceModel device) async {
    return await DevicesService().connect(device);
  }

  /// Disconnect from the current USB device
  Future<void> disconnect(DeviceModel device) async {
    await DevicesService().disconnect(device);
  }

  Future<bool> isConnected(DeviceModel device) async {
    return await DevicesService().isConnected(device);
  }

  /// Start listening for caller ID data from the connected device
  Future<bool> startListening(DeviceModel device) async {
    return await DevicesService().startListening(device);
  }

  /// Stop listening for caller ID data
  Future<bool> stopListening() async {
    return await DevicesService().stopListening();
  }

  /// Get stream of caller ID events (phone numbers, connection status, etc.)
  Stream<String> get callerIdEvents {
    return FlutterCalleridPlatform.instance.callerIdEvents;
  }
}
