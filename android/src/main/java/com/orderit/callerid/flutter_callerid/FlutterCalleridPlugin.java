// Top imports
package com.orderit.callerid.flutter_callerid;

import android.content.*;
import android.hardware.usb.*;
import android.content.Context;

import androidx.annotation.NonNull;

import java.util.*;

import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * FlutterCalleridPlugin
 */
public class FlutterCalleridPlugin implements FlutterPlugin, MethodCallHandler {

    private MethodChannel methodChannel;
    private EventChannel deviceEventChannel;
    private EventChannel callerIdEventChannel;
    private Context context;
    private FlutterCallerIdMethod flutterCallerIdMethod;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        context = flutterPluginBinding.getApplicationContext();
        methodChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_callerid");
        deviceEventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_callerid/device_events");
        callerIdEventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_callerid/callerid_events");
        methodChannel.setMethodCallHandler(this);
        flutterCallerIdMethod = new FlutterCallerIdMethod(context);
        deviceEventChannel.setStreamHandler(flutterCallerIdMethod.getDeviceStreamHandler());
        callerIdEventChannel.setStreamHandler(flutterCallerIdMethod.getCallerIdStreamHandler());

    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "getAvailableDevices":
                result.success(flutterCallerIdMethod.getUsbDevicesList());
                break;
            case "connectToHidDevice": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                flutterCallerIdMethod.connect(vendorId, productId);
                result.success(false);
                break;
            }
            case "disconnect": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                result.success(flutterCallerIdMethod.disconnect(vendorId, productId));
                break;
            }
            case "startListening": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                flutterCallerIdMethod.startListening(vendorId, productId);
                result.success(true);
                break;
            }
            case "stopListening": {
                flutterCallerIdMethod.stopListening();
                result.success(true);
                break;
            }
            case "isConnected": {
                String vendorId = call.argument("vendorId");
                String productId = call.argument("productId");
                result.success(flutterCallerIdMethod.isConnected(vendorId, productId));
            }
            default:
                result.notImplemented();
                break;
        }
    }


    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        methodChannel.setMethodCallHandler(null);
        deviceEventChannel.setStreamHandler(null);
        callerIdEventChannel.setStreamHandler(null);
    }
}
