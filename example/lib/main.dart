import 'dart:developer';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_callerid/flutter_callerid.dart';
import 'package:flutter_callerid/model/usb_device_model.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Caller ID Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(title: 'Flutter Caller ID Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _flutterCalleridPlugin = FlutterCallerid();
  String _lastPhoneNumber = 'Waiting for calls...';
  String _connectionStatus = 'Disconnected';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      startScan();
    });
  }

  StreamSubscription<List<DeviceModel>>? _devicesStreamSubscription;
  StreamSubscription<Map<String, dynamic>>? _callerIdStreamSubscription;
  List<DeviceModel> _devices = [];
  DeviceModel? _connectedDevice;
  // Get Printer List
  void startScan() async {
    _devicesStreamSubscription?.cancel();
    await _flutterCalleridPlugin.getDevices(connectionTypes: [ConnectionType.USB], androidUsesFineLocation: false);
    _devicesStreamSubscription = _flutterCalleridPlugin.devicesStream.listen((List<DeviceModel> event) {
      log(event.map((e) => e.name).toList().toString());
      setState(() {
        _devices = event;
        _devices.removeWhere((element) => element.name == null || element.name == '');
      });
    });
  }

  void startListening(DeviceModel? device) async {
    if (device == null) {
      return;
    }
    await _flutterCalleridPlugin.startListening(device);
    getCallerIdData();
  }

  void getCallerIdData() {
    _callerIdStreamSubscription?.cancel();
    _callerIdStreamSubscription = _flutterCalleridPlugin.callerIdStream.listen((callInfo) {
      log('Incoming call from ${callInfo['caller']} at ${callInfo['datetime']}');
    });
  }

  void stopListening() async {
    await _flutterCalleridPlugin.stopListening();
  }

  void connectToHidDevice(DeviceModel device) async {
    _connectedDevice = device;
    bool connected = await _flutterCalleridPlugin.connectToHidDevice(device);
    setState(() {
      _connectedDevice?.isConnected = connected;
    });
  }

  void disconnect(DeviceModel device) async {
    await _flutterCalleridPlugin.disconnect(device);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_connectionStatus'),
            const SizedBox(height: 16),
            Text('Last Phone Number: $_lastPhoneNumber'),
            const SizedBox(height: 16),
            const Text('Available Devices:'),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _devices.length,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_devices[index].name ?? ''),
                    subtitle: Text(_devices[index].isConnected ?? false ? 'Connected' : 'Disconnected'),
                    onTap: () => connectToHidDevice(_devices[index]),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            ElevatedButton(onPressed: startScan, child: const Text('Refresh Devices')),

            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => startListening(_connectedDevice), child: const Text('Start Listening')),
            ElevatedButton(onPressed: stopListening, child: const Text('Stop Listening')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
