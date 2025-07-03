package com.orderit.callerid.flutter_callerid;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import com.hoho.android.usbserial.driver.UsbSerialDriver;
import com.hoho.android.usbserial.driver.UsbSerialPort;
import com.hoho.android.usbserial.driver.UsbSerialProber;
import com.hoho.android.usbserial.util.SerialInputOutputManager;

import java.io.IOException;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** FlutterCalleridPlugin */
public class FlutterCalleridPlugin implements FlutterPlugin, MethodCallHandler, 
    SerialInputOutputManager.Listener {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel methodChannel;
  private EventChannel eventChannel;
  private EventChannel.EventSink eventSink;

  private Context context;
  private UsbManager usbManager;
  private UsbSerialPort usbSerialPort;
  private SerialInputOutputManager usbIoManager;
  private BroadcastReceiver usbReceiver;
  private Handler mainHandler;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    context = flutterPluginBinding.getApplicationContext();
    methodChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_callerid");
    methodChannel.setMethodCallHandler(this);
    
    eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_callerid/events");
    eventChannel.setStreamHandler(new EventChannel.StreamHandler() {
      @Override
      public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = events;
      }

      @Override
      public void onCancel(Object arguments) {
        eventSink = null;
      }
    });
    
    usbManager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
    mainHandler = new Handler(Looper.getMainLooper());
    setupUsbReceiver();
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "getPlatformVersion":
        result.success("Android " + android.os.Build.VERSION.RELEASE);
        break;
      case "getAvailableDevices":
        getAvailableDevices(result);
        break;
      case "connectToDevice":
        Integer deviceId = call.argument("deviceId");
        connectToDevice(deviceId, result);
        break;
      case "startListening":
        startListening(result);
        break;
      case "stopListening":
        stopListening(result);
        break;
      case "disconnect":
        disconnect(result);
        break;
      default:
        result.notImplemented();
    }
  }

  private void getAvailableDevices(Result result) {
    try {
      List<UsbSerialDriver> availableDrivers = UsbSerialProber.getDefaultProber()
          .findAllDrivers(usbManager);
      
      StringBuilder devicesInfo = new StringBuilder();
      for (UsbSerialDriver driver : availableDrivers) {
        UsbDevice device = driver.getDevice();
        devicesInfo.append(String.format(
            "Device ID: %d, Name: %s, VID: %04X, PID: %04X\n",
            device.getDeviceId(),
            device.getProductName() != null ? device.getProductName() : "Unknown",
            device.getVendorId(),
            device.getProductId()
        ));
      }
      
      result.success(devicesInfo.toString());
    } catch (Exception e) {
      result.error("ERROR", "Failed to get available devices: " + e.getMessage(), null);
    }
  }

  private void connectToDevice(Integer deviceId, Result result) {
    if (deviceId == null) {
      result.error("INVALID_ARGUMENT", "Device ID cannot be null", null);
      return;
    }

    try {
      List<UsbSerialDriver> availableDrivers = UsbSerialProber.getDefaultProber()
          .findAllDrivers(usbManager);
      
      UsbSerialDriver targetDriver = null;
      for (UsbSerialDriver driver : availableDrivers) {
        if (driver.getDevice().getDeviceId() == deviceId) {
          targetDriver = driver;
          break;
        }
      }
      
      if (targetDriver == null) {
        result.error("DEVICE_NOT_FOUND", "Device with ID " + deviceId + " not found", null);
        return;
      }
      
      UsbDevice device = targetDriver.getDevice();
      if (!usbManager.hasPermission(device)) {
        requestUsbPermission(device, result);
        return;
      }
      
      connectToDriverDevice(targetDriver, result);
      
    } catch (Exception e) {
      result.error("CONNECTION_ERROR", "Failed to connect: " + e.getMessage(), null);
    }
  }

  private void requestUsbPermission(UsbDevice device, Result result) {
    PendingIntent permissionIntent = PendingIntent.getBroadcast(
        context, 0, new Intent("com.orderit.callerid.USB_PERMISSION"), PendingIntent.FLAG_IMMUTABLE
    );
    
    usbManager.requestPermission(device, permissionIntent);
    // Result will be handled in the broadcast receiver
  }

  private void connectToDriverDevice(UsbSerialDriver driver, Result result) {
    try {
      if (usbSerialPort != null) {
        usbSerialPort.close();
      }

      usbSerialPort = driver.getPorts().get(0); // Most devices have just one port
      usbSerialPort.open(usbManager.openDevice(driver.getDevice()));
      
      // Configure serial parameters for caller ID devices
      // Most caller ID devices use 1200 baud, 8 data bits, no parity, 1 stop bit
      usbSerialPort.setParameters(1200, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE);
      
      result.success("Connected successfully");
      
    } catch (IOException e) {
      result.error("CONNECTION_ERROR", "Failed to open port: " + e.getMessage(), null);
    }
  }

  private void startListening(Result result) {
    if (usbSerialPort == null) {
      result.error("NO_CONNECTION", "No device connected", null);
      return;
    }

    try {
      if (usbIoManager != null) {
        usbIoManager.stop();
      }
      
      usbIoManager = new SerialInputOutputManager(usbSerialPort, this);
      usbIoManager.start();
      
      result.success("Started listening for caller ID data");
      
    } catch (Exception e) {
      result.error("LISTEN_ERROR", "Failed to start listening: " + e.getMessage(), null);
    }
  }

  private void stopListening(Result result) {
    if (usbIoManager != null) {
      usbIoManager.stop();
      usbIoManager = null;
    }
    result.success("Stopped listening");
  }

  private void disconnect(Result result) {
    try {
      if (usbIoManager != null) {
        usbIoManager.stop();
        usbIoManager = null;
      }
      
      if (usbSerialPort != null) {
        usbSerialPort.close();
        usbSerialPort = null;
      }
      
      result.success("Disconnected successfully");
      
    } catch (IOException e) {
      result.error("DISCONNECT_ERROR", "Error during disconnect: " + e.getMessage(), null);
    }
  }

  private void setupUsbReceiver() {
    usbReceiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if ("com.orderit.callerid.USB_PERMISSION".equals(action)) {
          synchronized (this) {
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
              if (device != null) {
                // Permission granted, try to connect
                List<UsbSerialDriver> drivers = UsbSerialProber.getDefaultProber()
                    .findAllDrivers(usbManager);
                for (UsbSerialDriver driver : drivers) {
                  if (driver.getDevice().equals(device)) {
                    connectToDriverDevice(driver, new Result() {
                      @Override
                      public void success(Object result) {
                        sendEvent("permission_granted", "Connected to device");
                      }
                      @Override
                      public void error(String errorCode, String errorMessage, Object errorDetails) {
                        sendEvent("connection_error", errorMessage);
                      }
                      @Override
                      public void notImplemented() {}
                    });
                    break;
                  }
                }
              }
            } else {
              sendEvent("permission_denied", "USB permission denied");
            }
          }
        }
      }
    };
    
    context.registerReceiver(usbReceiver, new IntentFilter("com.orderit.callerid.USB_PERMISSION"));
  }

  // SerialInputOutputManager.Listener implementation
  @Override
  public void onNewData(byte[] data) {
    String receivedData = new String(data);
    
    // Parse caller ID data
    // Common formats: "NMBR = 1234567890" or "NMBR=1234567890"
    String phoneNumber = extractPhoneNumber(receivedData);
    
    if (phoneNumber != null) {
      mainHandler.post(() -> {
        sendEvent("phone_number_detected", phoneNumber);
      });
    }
    
    // Also send raw data for debugging
    mainHandler.post(() -> {
      sendEvent("raw_data", receivedData);
    });
  }

  @Override
  public void onRunError(Exception e) {
    mainHandler.post(() -> {
      sendEvent("serial_error", "Serial communication error: " + e.getMessage());
    });
  }

  private String extractPhoneNumber(String data) {
    // Pattern for standard caller ID format: NMBR = phone_number
    Pattern pattern = Pattern.compile("NMBR\\s*=\\s*([\\d\\+\\-\\(\\)\\s]+)");
    Matcher matcher = pattern.matcher(data);
    
    if (matcher.find()) {
      String number = matcher.group(1);
      // Clean up the number (remove spaces, dashes, parentheses)
      return number.replaceAll("[\\s\\-\\(\\)]", "");
    }
    
    return null;
  }

  private void sendEvent(String eventType, String data) {
    if (eventSink != null) {
      eventSink.success(eventType + ":" + data);
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    methodChannel.setMethodCallHandler(null);
    eventChannel.setStreamHandler(null);
    
    if (usbReceiver != null) {
      context.unregisterReceiver(usbReceiver);
    }
    
    if (usbIoManager != null) {
      usbIoManager.stop();
    }
    
    if (usbSerialPort != null) {
      try {
        usbSerialPort.close();
      } catch (IOException e) {
        // Ignore close errors
      }
    }
  }
}
