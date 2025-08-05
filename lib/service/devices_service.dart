import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_callerid/flutter_callerid_platform_interface.dart';
import 'package:flutter_callerid/model/usb_device_model.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DevicesService {
  static final DevicesService _instance = DevicesService._internal();

  factory DevicesService() => _instance;

  DevicesService._internal();

  final StreamController<List<DeviceModel>> _devicesstream =
      StreamController<List<DeviceModel>>.broadcast();
  final StreamController<Map<String, dynamic>> _callerIdStream =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<ScanningEvent> _scanningStream =
      StreamController<ScanningEvent>.broadcast();

  Stream<List<DeviceModel>> get devicesStream => _devicesstream.stream;
  Stream<Map<String, dynamic>> get callerIdStream => _callerIdStream.stream;
  Stream<ScanningEvent> get scanningStream => _scanningStream.stream;

  StreamSubscription? _bleSubscription;
  StreamSubscription? _usbSubscription;
  StreamSubscription? _callerIdSubscription;

  static const String _deviceChannelName = 'flutter_callerid/device_events';
  static const String _callerIdChannelName = 'flutter_callerid/callerid_events';

  final EventChannel _deviceEventChannel = EventChannel(_deviceChannelName);
  final EventChannel _callerIdEventChannel = EventChannel(_callerIdChannelName);

  final List<DeviceModel> _devices = [];
  int _port = 9100;

  // Convenience getters for current state
  bool get isBleScanning => _scanningState[ConnectionType.BLE] ?? false;
  bool get isNetworkScanning => _scanningState[ConnectionType.NETWORK] ?? false;
  bool get isUsbScanning => _scanningState[ConnectionType.USB] ?? false;
  bool get isAnyScanning => _scanningState.values.any((scanning) => scanning);

  // Current scanning state
  final Map<ConnectionType, bool> _scanningState = {
    ConnectionType.BLE: false,
    ConnectionType.NETWORK: false,
    ConnectionType.USB: false,
  };

  // Helper methods to update scanning state
  void _updateScanningState(ConnectionType type, bool isScanning) {
    // Only emit if state actually changed
    if (_scanningState[type] != isScanning) {
      _scanningState[type] = isScanning;
      _scanningStream.add(
        ScanningEvent(connectionType: type, isScanning: isScanning),
      );
    }
  }

  Future<void> stopScan({
    bool stopBle = true,
    bool stopUsb = true,
    bool stopNetwork = true,
  }) async {
    try {
      if (stopBle) {
        await _bleSubscription?.cancel();
        _bleSubscription = null;
        await FlutterBluePlus.stopScan();
        _updateScanningState(ConnectionType.BLE, false);
      }
      if (stopUsb) {
        await _usbSubscription?.cancel();
        _updateScanningState(ConnectionType.USB, false);
      }
      if (stopNetwork) {
        _updateScanningState(ConnectionType.NETWORK, false);
      }
    } catch (e) {
      log('Failed to stop scanning for devices $e');
    }
  }

  // Get Devices from BT and USB
  Future<void> getDevices({
    List<ConnectionType> connectionTypes = const [ConnectionType.USB],
    bool androidUsesFineLocation = false,
    int cloudPrinterNum = 1,
  }) async {
    if (connectionTypes.isEmpty) {
      throw Exception('No connection type provided');
    }
    _devices.clear();
    _sentDeviceKeys.clear();
    if (connectionTypes.contains(ConnectionType.USB)) {
      debugPrint("getUSBDevices");
      await stopScan(stopUsb: true, stopBle: false, stopNetwork: false);
      _updateScanningState(ConnectionType.USB, true);
      await _getUSBDevices();
    }

    if (connectionTypes.contains(ConnectionType.BLE)) {
      debugPrint("getBLEDevices");
      if (Platform.isAndroid) {
        await _bluetoothIsEnabled();
        await stopScan(stopUsb: false, stopBle: true, stopNetwork: false);
        _updateScanningState(ConnectionType.BLE, true);
        await _getBleDevices(androidUsesFineLocation);
      }
    }
    if (connectionTypes.contains(ConnectionType.NETWORK)) {
      debugPrint("getWIFIDevices");
      await stopScan(stopUsb: false, stopBle: false, stopNetwork: true);
      _updateScanningState(ConnectionType.NETWORK, true);
      await _getNetworkDevices(cloudPrinterNum);
    }
  }

  Future<void> _getNetworkDevices(int cloudPrinterNum) async {
    String? ip = await _getLocalIP();
    if (ip != null) {
      // subnet
      final subnet = ip.substring(0, ip.lastIndexOf('.'));

      // Process IPs in concurrent batches for faster scanning
      const int batchSize = 25; // Process 25 IPs concurrently per batch
      const int maxConcurrency = 50; // Maximum concurrent operations

      List<Future<void>> allBatches = [];

      for (int startIp = 1; startIp <= 255; startIp += batchSize) {
        if (!_scanningState[ConnectionType.NETWORK]!) break;

        int endIp = (startIp + batchSize - 1).clamp(1, 255);
        allBatches.add(
          _processBatchOfIPs(subnet, startIp, endIp, cloudPrinterNum),
        );

        // Limit concurrent batches to avoid overwhelming the system
        if (allBatches.length >= maxConcurrency ~/ batchSize) {
          await Future.wait(allBatches);
          allBatches.clear();

          // Check if we found enough devices
          final foundDevices =
              _devices
                  .where((d) => d.connectionType == ConnectionType.NETWORK)
                  .length;
          if (foundDevices >= cloudPrinterNum) {
            break;
          }
        }
      }

      // Wait for remaining batches
      if (allBatches.isNotEmpty) {
        await Future.wait(allBatches);
      }
      _updateScanningState(ConnectionType.NETWORK, false);

      // remove duplicates by address
      _devices.removeWhere(
        (device) => device.address == null || device.address == '',
      );
      _sortDevices();
    }
  }

  Future<void> _processBatchOfIPs(
    String subnet,
    int startIp,
    int endIp,
    int maxDevices,
  ) async {
    if (!_scanningState[ConnectionType.NETWORK]!) return;

    List<Future<DeviceModel?>> pingFutures = [];

    for (int i = startIp; i <= endIp; i++) {
      if (!_scanningState[ConnectionType.NETWORK]!) return;

      final deviceIp = '$subnet.$i';
      pingFutures.add(_pingAndCreateDevice(deviceIp, i));
    }

    try {
      final results = await Future.wait(pingFutures);

      for (final device in results) {
        if (device != null && _scanningState[ConnectionType.NETWORK]!) {
          debugPrint('Valid device found ${device.address}');
          _devices.add(device);

          // Check if we've reached the limit
          final networkDeviceCount =
              _devices
                  .where((d) => d.connectionType == ConnectionType.NETWORK)
                  .length;
          if (networkDeviceCount >= maxDevices) {
            _updateScanningState(ConnectionType.NETWORK, false);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error in batch processing: $e');
    }
  }

  Future<DeviceModel?> _pingAndCreateDevice(String ip, int deviceNumber) async {
    try {
      final socket = await Socket.connect(
        ip,
        _port,
        timeout: const Duration(seconds: 2),
      ); // Reduced timeout for faster scanning
      socket.destroy();

      return DeviceModel(
        address: ip,
        name: 'Cloud Printer $deviceNumber',
        connectionType: ConnectionType.NETWORK,
        isConnected: false,
      );
    } catch (error) {
      debugPrint('Failed to ping $ip ${error.toString()}');
      return null;
    }
  }

  Future<void> _bluetoothIsEnabled() async {
    if (await FlutterBluePlus.isSupported == false) {
      log("Bluetooth not supported by this device");
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
  }

  Future<void> _getBleDevices(bool androidUsesFineLocation) async {
    try {
      final systemDevices = await _getBLESystemDevices();
      final bondedDevices = await _getBLEBondedDevices();
      _devices.addAll(systemDevices);
      _devices.addAll(bondedDevices);
      _sortDevices();

      await FlutterBluePlus.startScan(
        androidUsesFineLocation: androidUsesFineLocation,
        timeout: const Duration(seconds: 10),
      );
      Set<String> uniqueDeviceAddresses = {};
      List<DeviceModel> bleDevices = [];

      _bleSubscription = FlutterBluePlus.scanResults.listen((event) {
        final uniqueDevices = event.toSet();
        for (var e in uniqueDevices) {
          if (e.device.platformName.isNotEmpty) {
            if (uniqueDeviceAddresses.contains(e.device.remoteId.str)) {
              continue;
            }
            debugPrint(
              "Unique devices: ${e.device.platformName} ${e.device.isConnected}",
            );
            uniqueDeviceAddresses.add(e.device.remoteId.str);
            bleDevices.add(
              DeviceModel(
                address: e.device.remoteId.str,
                name: e.device.platformName,
                connectionType: ConnectionType.BLE,
                isConnected: e.device.isConnected,
              ),
            );
            for (var device in bleDevices) {
              _updateOrAddPrinter(device);
            }
          }
        }
      });

      if (_bleSubscription != null) {
        // Clean up when scan stops
        FlutterBluePlus.cancelWhenScanComplete(_bleSubscription!);
        // Wait until scanning is complete
        await FlutterBluePlus.isScanning.where((val) => val == false).first;
        _updateScanningState(ConnectionType.BLE, false);
      }
    } catch (e) {
      _updateScanningState(ConnectionType.BLE, false);
      log("Failed to get BLE devices $e");
    }
  }

  Future<void> _getUSBDevices() async {
    try {
      final devices = await FlutterCalleridPlatform.instance.startUsbScan();
      List<DeviceModel> usbPrinters = [];
      for (var map in devices) {
        final device = DeviceModel(
          vendorId: map['vendorId'].toString(),
          productId: map['productId'].toString(),
          name: map['name'],
          connectionType: ConnectionType.USB,
          address: map['vendorId'].toString(),
          isConnected: map['connected'] ?? false,
          isRemove: map['isRemove'] ?? false,
        );
        // device.isConnected = await FlutterCalleridPlatform.instance.isConnected(device.vendorId!, device.productId!);
        usbPrinters.add(device);
      }

      _devices.addAll(usbPrinters);

      // Start listening to USB events
      _usbSubscription = _deviceEventChannel.receiveBroadcastStream().listen((
        event,
      ) {
        final map = Map<String, dynamic>.from(event);
        _updateOrAddPrinter(
          DeviceModel(
            vendorId: map['vendorId'].toString(),
            productId: map['productId'].toString(),
            name: map['name'],
            connectionType: ConnectionType.USB,
            address: map['vendorId'].toString(),
            isConnected: map['connected'] ?? false,
            isRemove: map['isRemove'] ?? false,
          ),
        );
      });

      _sortDevices();
    } catch (e) {
      _updateScanningState(ConnectionType.USB, false);
      log("$e [USB Connection]");
    }
  }

  Future<bool> connect(DeviceModel device) async {
    if (device.connectionType == ConnectionType.USB) {
      return await FlutterCalleridPlatform.instance.connectToHidDevice(
        device.vendorId!,
        device.productId!,
      );
    } else if (device.connectionType == ConnectionType.BLE) {
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
    } else if (device.connectionType == ConnectionType.NETWORK) {}
    return false;
  }

  Future<bool> isConnected(DeviceModel device) async {
    if (device.connectionType == ConnectionType.USB) {
      return await FlutterCalleridPlatform.instance.isConnected(
        device.vendorId!,
        device.productId!,
      );
    } else {
      try {
        final bt = BluetoothDevice.fromId(device.address!);
        return bt.isConnected;
      } catch (e) {
        return false;
      }
    }
  }

  Future<void> disconnect(DeviceModel device) async {
    if (device.connectionType == ConnectionType.BLE) {
      try {
        final bt = BluetoothDevice.fromId(device.address!);
        await bt.disconnect();
      } catch (e) {
        log('Failed to disconnect device');
      }
    }
  }

  Future<bool> startListening(DeviceModel device) async {
    _callerIdSubscription?.cancel();
    _callerIdSubscription = _callerIdEventChannel
        .receiveBroadcastStream()
        .listen((event) {
          final map = Map<String, dynamic>.from(event);
          log("Received Caller ID: ${map['caller']} at ${map['datetime']}");
          _callerIdStream.add(map);
        });

    return FlutterCalleridPlatform.instance.startListening(
      device.vendorId!,
      device.productId!,
    );
  }

  Future<bool> stopListening() async {
    await _callerIdSubscription?.cancel();
    _callerIdSubscription = null;
    return FlutterCalleridPlatform.instance.stopListening();
  }

  Future<List<DeviceModel>> _getBLESystemDevices() async {
    return (await FlutterBluePlus.systemDevices([]))
        .map(
          (device) => DeviceModel(
            address: device.remoteId.str,
            name: device.platformName,
            connectionType: ConnectionType.BLE,
            isConnected: device.isConnected,
          ),
        )
        .toList();
  }

  Future<List<DeviceModel>> _getBLEBondedDevices() async {
    return (await FlutterBluePlus.bondedDevices)
        .map(
          (device) => DeviceModel(
            address: device.remoteId.str,
            name: device.platformName,
            connectionType: ConnectionType.BLE,
            isConnected: device.isConnected,
          ),
        )
        .toList();
  }

  void _updateOrAddPrinter(DeviceModel printer) {
    final index = _devices.indexWhere(
      (device) => device.address == printer.address,
    );
    if (index == -1) {
      _devices.add(printer);
    } else {
      _devices[index] = printer;
    }
    _sortDevices();
  }

  final Set<String> _sentDeviceKeys = {};

  void _recordDevices(List<DeviceModel> devices) {
    for (var device in devices) {
      String uniqueKey = '${device.vendorId}_${device.address}';
      _sentDeviceKeys.add(uniqueKey);
    }
  }

  // void _sortDevices() {
  //   _devices.removeWhere(
  //     (element) => element.name == null || element.name == '',
  //   );

  //   // Remove duplicates based on vendorId + address
  //   Set<String> seen = {};
  //   _devices.retainWhere((element) {
  //     String uniqueKey = '${element.vendorId}_${element.address}';

  //     // Skip if already sent or duplicate in current batch
  //     if (_sentDeviceKeys.contains(uniqueKey) || seen.contains(uniqueKey)) {
  //       return false;
  //     }

  //     seen.add(uniqueKey);
  //     return true;
  //   });

  //   _recordDevices(_devices);
  //   if (_devices.isNotEmpty) {
  //     _devicesstream.add(_devices);
  //   }
  // }

  void _sortDevices() {
    _devices.removeWhere(
      (element) => element.name == null || element.name == '',
    );
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

  Future<String?> _getLocalIP() async {
    final info = NetworkInfo();
    final wifiIP =
        await info.getWifiIP(); // This gives your IP on the local network
    return wifiIP;
  }

  void dispose() {
    _devicesstream.close();
    _callerIdStream.close();
    _scanningStream.close();
    _bleSubscription?.cancel();
    _usbSubscription?.cancel();
    _callerIdSubscription?.cancel();
  }
}
