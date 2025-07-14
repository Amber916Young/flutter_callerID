import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class UsbDeviceModel {
  String? address;
  String? name;
  ConnectionType? connectionType;
  bool? isConnected;
  String? vendorId;
  String? productId;

  UsbDeviceModel({this.address, this.name, this.connectionType, this.isConnected, this.vendorId, this.productId});

  UsbDeviceModel.fromJson(Map<String, dynamic> json) {
    address = json['address'];
    name = json['connectionType'] == 'BLE' ? json['platformName'] : json['name'];
    connectionType = _getConnectionTypeFromString(json['connectionType']);
    isConnected = json['isConnected'];
    vendorId = json['vendorId'];
    productId = json['productId'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['address'] = address;
    if (connectionType == ConnectionType.BLE) {
      data['platformName'] = name;
    } else {
      data['name'] = name;
    }
    data['connectionType'] = connectionTypeString;
    data['isConnected'] = isConnected;
    data['vendorId'] = vendorId;
    data['productId'] = productId;
    return data;
  }

  ConnectionType _getConnectionTypeFromString(String? connectionType) {
    switch (connectionType) {
      case 'BLE':
        return ConnectionType.BLE;
      case 'USB':
        return ConnectionType.USB;
      case 'NETWORK':
        return ConnectionType.NETWORK;
      default:
        throw ArgumentError('Invalid connection type');
    }
  }
}

enum ConnectionType { BLE, USB, NETWORK }

extension PrinterExtension on UsbDeviceModel {
  String get connectionTypeString {
    switch (connectionType) {
      case ConnectionType.BLE:
        return 'BLE';
      case ConnectionType.USB:
        return 'USB';
      case ConnectionType.NETWORK:
        return 'NETWORK';
      default:
        return '';
    }
  }

  Stream<BluetoothConnectionState> get connectionState {
    if (connectionType != ConnectionType.BLE) {
      throw UnsupportedError('Only BLE printers are supported');
    }
    if (address == null) {
      throw ArgumentError('Address is required for BLE printers');
    }
    return BluetoothDevice.fromId(address!).connectionState;
  }
}
