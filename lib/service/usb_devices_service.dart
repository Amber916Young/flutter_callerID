import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_callerid/flutter_callerid_platform_interface.dart';
import 'package:flutter_callerid/model/usb_device_model.dart';

class UsbDevicesService {
  static final UsbDevicesService _instance = UsbDevicesService._internal();

  factory UsbDevicesService() => _instance;

  UsbDevicesService._internal();

  final StreamController<List<UsbDeviceModel>> _devicesstream = StreamController<List<UsbDeviceModel>>.broadcast();
  final StreamController<Map<String, dynamic>> _callerIdStream = StreamController<Map<String, dynamic>>.broadcast();

  Stream<List<UsbDeviceModel>> get devicesStream => _devicesstream.stream;
  Stream<Map<String, dynamic>> get callerIdStream => _callerIdStream.stream;

  StreamSubscription? subscription;
  StreamSubscription? refresher;
  StreamSubscription? _usbSubscription;
  StreamSubscription? _callerIdSubscription;

  static const String _deviceChannelName = 'flutter_callerid/device_events';
  static const String _callerIdChannelName = 'flutter_callerid/callerid_events';

  final EventChannel _deviceEventChannel = EventChannel(_deviceChannelName);
  final EventChannel _callerIdEventChannel = EventChannel(_callerIdChannelName);

  final List<UsbDeviceModel> _devices = [];

  Future<void> stopScan({bool stopBle = true, bool stopUsb = true}) async {
    try {
      if (stopBle) {
        await subscription?.cancel();
        await FlutterBluePlus.stopScan();
      }
      if (stopUsb) {
        await _usbSubscription?.cancel();
      }
    } catch (e) {
      log('Failed to stop scanning for devices $e');
    }
  }

  Future<void> getUSBDevices() async {
    try {
      final devices = await FlutterCalleridPlatform.instance.startUsbScan();

      List<UsbDeviceModel> usbPrinters = [];
      for (var map in devices) {
        final device = UsbDeviceModel(
          vendorId: map['vendorId'].toString(),
          productId: map['productId'].toString(),
          name: map['name'],
          connectionType: ConnectionType.USB,
          address: map['vendorId'].toString(),
          isConnected: map['connected'] ?? false,
        );
        device.isConnected = await FlutterCalleridPlatform.instance.isConnected(device.vendorId!, device.productId!);
        usbPrinters.add(device);
      }

      _devices.addAll(usbPrinters);

      // Start listening to USB events
      _usbSubscription?.cancel();
      _usbSubscription = _deviceEventChannel.receiveBroadcastStream().listen((event) {
        final map = Map<String, dynamic>.from(event);
        _updateOrAddPrinter(
          UsbDeviceModel(
            vendorId: map['vendorId'].toString(),
            productId: map['productId'].toString(),
            name: map['name'],
            connectionType: ConnectionType.USB,
            address: map['vendorId'].toString(),
            isConnected: map['connected'] ?? false,
          ),
        );
      });

      _sortDevices();
    } catch (e) {
      log("$e [USB Connection]");
    }
  }

  Future<bool> connect(UsbDeviceModel device) async {
    if (device.connectionType == ConnectionType.USB) {
      return await FlutterCalleridPlatform.instance.connectToHidDevice(device.vendorId!, device.productId!);
    } else {
      try {
        bool isConnected = false;
        final bt = BluetoothDevice.fromId(device.address!);
        await bt.connect();
        final stream = bt.connectionState.listen((event) {
          if (event == BluetoothConnectionState.connected) {
            isConnected = true;
          }
        });
        await Future.delayed(const Duration(seconds: 3));
        await stream.cancel();
        return isConnected;
      } catch (e) {
        return false;
      }
    }
  }

  Future<void> disconnect(UsbDeviceModel device) async {
    if (device.connectionType == ConnectionType.BLE) {
      try {
        final bt = BluetoothDevice.fromId(device.address!);
        await bt.disconnect();
      } catch (e) {
        log('Failed to disconnect device');
      }
    }
  }

  Future<bool> startListening(UsbDeviceModel device) async {
    _callerIdSubscription?.cancel();
    _callerIdSubscription = _callerIdEventChannel.receiveBroadcastStream().listen((event) {
      final map = Map<String, dynamic>.from(event);
      log("Received Caller ID: ${map['caller']} at ${map['datetime']}");
      _callerIdStream.add(map);
    });

    return FlutterCalleridPlatform.instance.startListening(device.vendorId!, device.productId!);
  }

  Future<bool> stopListening() async {
    await _callerIdSubscription?.cancel();
    _callerIdSubscription = null;
    return FlutterCalleridPlatform.instance.stopListening();
  }

  void _updateOrAddPrinter(UsbDeviceModel printer) {
    final index = _devices.indexWhere((device) => device.address == printer.address);
    if (index == -1) {
      _devices.add(printer);
    } else {
      _devices[index] = printer;
    }
    _sortDevices();
  }

  void _sortDevices() {
    _devices.removeWhere((element) => element.name == null || element.name == '');
    // remove items having same vendorId
    Set<String> seen = {};
    _devices.retainWhere((element) {
      String uniqueKey = '${element.vendorId}_${element.address}';
      if (seen.contains(uniqueKey)) {
        return false; // Remove duplicate
      } else {
        seen.add(uniqueKey); // Mark as seen
        return true; // Keep
      }
    });
    _devicesstream.add(_devices);
  }
}
