import 'package:flutter_callerid/service/usb_devices_service.dart';

import 'flutter_callerid_platform_interface.dart';
import 'model/usb_device_model.dart';

class FlutterCallerid {
  Stream<List<UsbDeviceModel>> get devicesStream {
    return UsbDevicesService().devicesStream;
  }

  Stream<Map<String, dynamic>> get callerIdStream {
    return UsbDevicesService().callerIdStream;
  }

  /// Get all available USB  devices
  Future<void> getUSBDevices() async {
    UsbDevicesService().getUSBDevices();
  }

  Future<void> stopScan() async {
    UsbDevicesService().stopScan();
  }

  /// Connect to a specific HID device by device ID
  Future<bool> connectToHidDevice(UsbDeviceModel device) async {
    return await UsbDevicesService().connect(device);
  }

  /// Disconnect from the current USB device
  Future<void> disconnect(UsbDeviceModel device) async {
    await UsbDevicesService().disconnect(device);
  }

  /// Start listening for caller ID data from the connected device
  Future<bool> startListening(UsbDeviceModel device) async {
    return await UsbDevicesService().startListening(device);
  }

  /// Stop listening for caller ID data
  Future<bool> stopListening() async {
    return await UsbDevicesService().stopListening();
  }

  /// Get stream of caller ID events (phone numbers, connection status, etc.)
  Stream<String> get callerIdEvents {
    return FlutterCalleridPlatform.instance.callerIdEvents;
  }
}
