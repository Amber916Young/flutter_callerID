package com.orderit.callerid.flutter_callerid;

import static android.content.Context.USB_SERVICE;

import android.annotation.SuppressLint;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.hardware.usb.UsbRequest;
import android.os.Build;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.hoho.android.usbserial.driver.CdcAcmSerialDriver;
import com.hoho.android.usbserial.driver.UsbSerialDriver;
import com.hoho.android.usbserial.driver.UsbSerialPort;

import io.flutter.plugin.common.EventChannel;

public class FlutterCallerIdMethod {
    @SuppressLint("StaticFieldLeak")
    private static Context context;

    private static final String ACTION_USB_PERMISSION = "com.example.flutter_thermal_printer.USB_PERMISSION";
    private static final String ACTION_USB_ATTACHED = "android.hardware.usb.action.USB_DEVICE_ATTACHED";
    private static final String ACTION_USB_DETACHED = "android.hardware.usb.action.USB_DEVICE_DETACHED";
    private static final String TAG = "FPP";
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private EventChannel.EventSink deviceEventSink;
    private EventChannel.EventSink callerIdEventSink;

    private BroadcastReceiver usbStateChangeReceiver;
    private UsbDeviceConnection connection;
    private UsbInterface mIntf;

    private UsbEndpoint rEndpoint;
    private UsbEndpoint wEndpoint;
    private boolean reading = false;
    private static final int TIMEOUT = 3000;
    private static int SLEEP = 100;
    private static final String ACK = "ACK\r\n";
    private static final String DCK = "DCK\r\n";
    private static PendingIntent mPermissionIntent;

    FlutterCallerIdMethod(Context context) {
        FlutterCallerIdMethod.context = context;
        mPermissionIntent = PendingIntent.getActivity(context, 0, new Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE);
    }

    public EventChannel.StreamHandler getDeviceStreamHandler() {
        return new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object args, EventChannel.EventSink events) {
                deviceEventSink = events;
                createUsbStateChangeReceiver();
                IntentFilter filter = new IntentFilter();
                filter.addAction(ACTION_USB_ATTACHED);
                filter.addAction(ACTION_USB_DETACHED);
                filter.addAction(ACTION_USB_PERMISSION);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.registerReceiver(usbStateChangeReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
                } else {
                    context.registerReceiver(usbStateChangeReceiver, filter);
                }
            }

            @Override
            public void onCancel(Object args) {
                context.unregisterReceiver(usbStateChangeReceiver);
                deviceEventSink = null;
            }
        };
    }

    public EventChannel.StreamHandler getCallerIdStreamHandler() {
        return new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object args, EventChannel.EventSink events) {
                callerIdEventSink = events;
            }

            @Override
            public void onCancel(Object args) {
                callerIdEventSink = null;
            }
        };
    }

    private void createUsbStateChangeReceiver() {
        usbStateChangeReceiver = new BroadcastReceiver() {
            @SuppressLint("LongLogTag")
            @Override
            public void onReceive(Context context, Intent intent) {
                if (Objects.equals(intent.getAction(), ACTION_USB_ATTACHED)) {
                    UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                    Log.d(TAG, "ACTION_USB_ATTACHED");
                    sendDevice(device);
                } else if (Objects.equals(intent.getAction(), ACTION_USB_DETACHED)) {
                    UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                    Log.d(TAG, "ACTION_USB_DETACHED");
                    sendDevice(device);
                } else if (Objects.equals(intent.getAction(), ACTION_USB_PERMISSION)) {
                    Log.d(TAG, "ACTION_USB_PERMISSION " + (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)));
                    synchronized (this) {
                        UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                        boolean permissionGranted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
                        if (permissionGranted) {
                            Log.d(TAG, "Permission granted for device " + device);
                            sendDevice(device);
                        } else {
                            Log.d(TAG, "Permission denied for device " + device);
                            connect(connectionVendorId, connectionProductId);
                        }
                    }
                }
            }
        };
    }


    private void sendDevice(UsbDevice device) {
        if (device == null) {
            Log.d(TAG, "Device is null.");
            return;
        }
        boolean isConnected = isConnected(String.valueOf(device.getVendorId()), String.valueOf(device.getProductId()));
        HashMap<String, Object> deviceData = new HashMap<>();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            deviceData.put("name", device.getProductName());
        }
        deviceData.put("vendorId", String.valueOf(device.getVendorId()));
        deviceData.put("productId", String.valueOf(device.getProductId()));
        deviceData.put("connected", isConnected);
        Log.d(TAG, "Sending device data: " + deviceData);
        if (deviceEventSink != null) {
            mainHandler.post(() -> deviceEventSink.success(deviceData));
        }

    }


    public List<Map<String, Object>> getUsbDevicesList() {
        UsbManager m = (UsbManager) context.getSystemService(USB_SERVICE);
        HashMap<String, UsbDevice> usbDevices = m.getDeviceList();
        List<Map<String, Object>> data = new ArrayList<Map<String, Object>>();
        for (Map.Entry<String, UsbDevice> entry : usbDevices.entrySet()) {
            UsbDevice device = entry.getValue();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                HashMap<String, Object> deviceData = new HashMap<String, Object>();
                deviceData.put("name", device.getProductName());
                deviceData.put("vendorId", String.valueOf(device.getVendorId()));
                deviceData.put("productId", String.valueOf(device.getProductId()));
                deviceData.put("connected", m.hasPermission(device));
                data.add(deviceData);
            }
        }
        return data;
    }

    private String connectionVendorId;
    private String connectionProductId;

    private Integer requestingPermission = 0;

    // Connect using VendorId and ProductId
    public void connect(String vendorId, String productId) {
        connectionVendorId = vendorId;
        connectionProductId = productId;
        UsbManager m = (UsbManager) context.getSystemService(Context.USB_SERVICE);
        UsbDevice device = findDevice(m, vendorId, productId);

        if (device == null) {
            Log.d(TAG, "Device not found.");
            return;
        }

        if (!m.hasPermission(device)) {
//            requestingPermission++;
//            PendingIntent permissionIntent = PendingIntent.getBroadcast(context, 0, new Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE);
//            m.requestPermission(device, permissionIntent);
            Log.d(TAG, "Requesting permission for device...");
            PendingIntent permissionIntent = PendingIntent.getBroadcast(context, 0, new Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE);
            m.requestPermission(device, permissionIntent);
        } else {
            Log.d(TAG, "Permission already granted. Proceeding.");
            sendDevice(device); // Proceed directly if permission exists
        }
    }

    public boolean isConnected(String vendorId, String productId) {
        UsbDevice device = findDevice((UsbManager) context.getSystemService(USB_SERVICE), vendorId, productId);
        return device != null && ((UsbManager) context.getSystemService(USB_SERVICE)).hasPermission(device);
    }

    public boolean disconnect(String vendorId, String productId) {
        UsbDevice device = findDevice((UsbManager) context.getSystemService(USB_SERVICE), vendorId, productId);
        if (device == null || !((UsbManager) context.getSystemService(USB_SERVICE)).hasPermission(device))
            return false;

        UsbDeviceConnection connection = ((UsbManager) context.getSystemService(USB_SERVICE)).openDevice(device);
        connection.releaseInterface(device.getInterface(0));
        connection.close();
        sendDevice(device);
        return true;
    }

    public String getDeviceType(UsbInterface intf) {
        int cls = intf.getInterfaceClass();
        switch (cls) {
            case UsbConstants.USB_CLASS_COMM:
            case 0x0A:
                return "CDC串口设备";
            case UsbConstants.USB_CLASS_HID:
                return "HID设备";
            case UsbConstants.USB_CLASS_VENDOR_SPEC:
                return "厂商自定义";
            default:
                return "未知类(" + cls + ")";
        }
    }

    public void startListening(String vendorId, String productId) {
        Log.d(TAG, "Attempting to connect to device...");

        UsbManager m = (UsbManager) context.getSystemService(Context.USB_SERVICE);
        UsbDevice currentDevice = null;
        for (UsbDevice device : m.getDeviceList().values()) {
            if (String.valueOf(device.getVendorId()).equals(vendorId) && String.valueOf(device.getProductId()).equals(productId)) {
                currentDevice = device;
                break;
            }
        }

        if (currentDevice == null) {
            Log.e(TAG, "No connected device.");
            return;
        }
        if (!m.hasPermission(currentDevice)) {
            Log.e(TAG, "No permission for device. Please request it via broadcast.");
            return;
        }
        UsbInterface intf = currentDevice.getInterface(0);
        String deviceType = getDeviceType(intf);
        Log.d("USB", deviceType);

        connection = m.openDevice(currentDevice);
        if (connection == null) {
            Log.e(TAG, "Failed to open or claim interface.");
            return;
        }

        mIntf = currentDevice.getInterface(0);
        if (!connection.claimInterface(mIntf, true)) {
            Log.e(TAG, "Failed to claim interface.");
            return;
        }

        Log.d(TAG, "  Interface Class: " + mIntf.getInterfaceClass());

        // Dynamically pick endpoints by direction
        for (int i = 0; i < mIntf.getEndpointCount(); i++) {
            UsbEndpoint ep = mIntf.getEndpoint(i);
            if (ep.getDirection() == UsbConstants.USB_DIR_IN) rEndpoint = ep;
            else if (ep.getDirection() == UsbConstants.USB_DIR_OUT) wEndpoint = ep;
            Log.d(TAG, "Endpoint #" + i + " type=" + ep.getType() + ", direction=" + (ep.getDirection() == UsbConstants.USB_DIR_IN ? "IN" : "OUT") + ", address=" + ep.getAddress() + ", maxPacketSize=" + ep.getMaxPacketSize());
        }


        if (rEndpoint == null) {
            Log.e(TAG, "No readable endpoint found.");
            return;
        }

        Log.d(TAG, "Claimed interface and endpoints. Starting read loop...");
        sendData("AT+VCID=1\\r");
        new Thread(this::readLoop).start();
        reading = true;
    }

    private String sDateTime = "";
    private String sCaller = "";
    private String sCallee = "";
    private String sOther = "";
    private char sPort = 0;

    private void analyzePackage(byte[] bytes) {
        try {
            final String strPackage = composeString(bytes);
            Log.d("====", strPackage);

            if (strPackage.contains("ENQ")) sendData(ACK);
            else if (strPackage.contains("ETB")) sendData(ACK);
//            else if (strPackage.contains("STA")) echoLineEvent(strPackage);
            else {
                sendData(DCK);
                if (testCliPackage(bytes)) {
                    //TODO pass data to flutter
                    Log.d("analyzePackage", sDateTime + "<-- " + sCaller + "-----" + sCallee + "-----" + sPort + "-----" + sOther);
                    Map<String, Object> callInfo = new HashMap<>();
                    callInfo.put("caller", sCaller);
                    callInfo.put("callee", sCallee);
                    callInfo.put("datetime", sDateTime);
                    callInfo.put("port", String.valueOf(sPort));
                    if (callerIdEventSink != null)
                        mainHandler.post(() -> callerIdEventSink.success(callInfo));


                }
            }
        } catch (Exception e) {
            Log.d("analyzePackage", Log.getStackTraceString(e));
        }
    }

    private boolean testCliPackage(byte[] Package) {
        boolean res = false;
        try {
            byte[] portNames = {'A', 'B', 'C', 'D', 'S'};
            int[] pckTypes = {0x04, 0x80};

            byte pPort = Package[0];
            int pType = Math.abs((int) Package[1]);
            int pLen = Math.abs((int) Package[2]);

            if ((pLen > 0) && (pLen < 65) && Arrays.binarySearch(portNames, pPort) >= 0 && Arrays.binarySearch(pckTypes, pType) >= 0) {
                if (pType == 0x80) {
                    res = parseMDMF(Package);
                }
                if (pType == 0x04) {
                    res = parseSDMF(Package);
                }
            }
        } catch (Exception e) {
            Log.d("testCliPackage", Log.getStackTraceString(e));
        }
        return res;
    }

    private boolean parseSDMF(byte[] Package) {
        int packlength = 0;
        char theChar = 0;

        try {
            packlength = Package[2] + 4;
            sPort = (char) Package[0];
            sCaller = "";
            sCallee = "";
            sDateTime = "";
            sOther = "";

            for (int i = 3; i <= packlength - 2; i++) {
                if (i < Package.length) {
                    theChar = (char) Package[i];
                    if (i < 11) {
                        sDateTime = sDateTime + (char) Package[i];
                    } else {
                        sCaller = sCaller + theChar;
                    }
                }
            }
        } catch (Exception e) {
            Log.d("CEBridge - parsesDMF", Log.getStackTraceString(e));
        }

        return (!enableCheckDigitControl || testCheckDigit(Package));
    }

    private boolean parseMDMF(byte[] Package) {
        int packlength = 0;
        int datalength = 0;
        char theChar = 0;
        int i;

        try {
            packlength = Package[2] + 4;
            sPort = (char) Package[0];
            sCaller = "";
            sCallee = "";
            sDateTime = "";
            sOther = "";

            if (packlength > Package.length) {
                packlength = Package.length;
            }

            if (packlength > 0) {
                i = 3;
                datalength = 0;
                while (i < Package.length) {
                    if (Package[i] == 1) // Date Field
                    {
                        i++;
                        if (i < packlength - 1) {
                            datalength = Package[i];
                            if (datalength != 8) datalength = 8;
                            if (datalength == 8) {
                                while ((datalength > 0) && (datalength < packlength)) {
                                    i++;
                                    theChar = (char) Package[i];
                                    sDateTime = sDateTime + theChar;
                                    datalength--;
                                }
                            }
                        }
                    } else if (Package[i] == 2)  // Number Field
                    {
                        i++;
                        if (i < packlength - 1) {
                            datalength = Package[i];
                            if (datalength > (packlength - i - 1))
                                datalength = (packlength - i - 1);
                            while ((datalength > 0) && (datalength < packlength)) {
                                i++;
                                theChar = (char) Package[i];
                                sCaller = sCaller + theChar;
                                datalength--;
                            }
                        }
                    } else if (Package[i] == 34)  //Callee field
                    {
                        // Other Fields
                        i++;
                        if (i < packlength - 1) {
                            datalength = Package[i];
                            while ((datalength > 0) && (datalength < packlength)) {
                                i++;
                                theChar = (char) Package[i];
                                sCallee = sCallee + theChar;
                                datalength--;
                            }
                        }
                    } else {
                        // Other Fields
                        i++;
                        if (i < packlength - 1) {
                            datalength = Package[i];
                            while ((datalength > 0) && (datalength < packlength)) {
                                i++;
                                theChar = (char) Package[i];
                                sOther = sOther + theChar;
                                datalength--;
                            }
                        }
                    }
                    i++;
                }
            }
        } catch (Exception e) {
            Log.d("CEBridge - parseMDMF", Log.getStackTraceString(e));
        }

        return (!enableCheckDigitControl || testCheckDigit(Package));
    }

    private static final boolean enableCheckDigitControl = true;

    private static boolean testCheckDigit(byte[] inputReport) {
        int pLen = 0;
        int cDigit = 123;
        int pDigit = 0;

        try {
            pLen = inputReport[2] + 3;
            cDigit = inputReport[pLen] & 255;
            for (int i = 1; i < pLen; i++)
                pDigit = (pDigit + Math.abs((int) inputReport[i] & 255)) & 255;
            pDigit = Math.abs((int) (0x100 - pDigit)) & 255;
        } catch (Exception e) {
            Log.d("testCheckDigit", Log.getStackTraceString(e));
        }

        return pDigit == cDigit;
    }

    private String composeString(byte[] bytes) {
        String strPackage = "";

        try {
            StringBuilder builder = new StringBuilder();
            for (byte b : bytes) {
                if (b > 0) {
                    char c = (char) b;
                    builder.append(c);
                }
            }
            strPackage = builder.toString();
        } catch (Exception e) {
            Log.d("composeString", Log.getStackTraceString(e));
        }

        return strPackage;
    }

    private void readLoop() {
        byte[] buffer = new byte[64];

        while (reading) {
            int len = connection.bulkTransfer(rEndpoint, buffer, buffer.length, TIMEOUT);
            if (len > 0) {

                analyzePackage(buffer);

            } else if (len == -1) {
                Log.w(TAG, "No data or timeout.");
            }
            Sleep(SLEEP);

        }
    }

    private void Sleep(int milliseconds) {
        try {
            Thread.sleep(milliseconds);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    public void stopListening() {
        reading = false;
        if (connection != null) {
            connection.releaseInterface(mIntf);
            connection.close();
            connection = null;
        }
        rEndpoint = null;
        wEndpoint = null;
        Log.d(TAG, "Stopped listening to Caller ID.");
    }

    private UsbDevice findDevice(UsbManager manager, String vendorId, String productId) {
        for (UsbDevice device : manager.getDeviceList().values()) {
            if (String.valueOf(device.getVendorId()).equals(vendorId) && String.valueOf(device.getProductId()).equals(productId))
                return device;
        }
        return null;
    }

    private void sendData(String message) {
        try {
            if (connection != null && wEndpoint != null) {
                byte[] data = message.getBytes(StandardCharsets.UTF_8);
                int result = connection.bulkTransfer(wEndpoint, data, data.length, TIMEOUT);
                Log.d(TAG, "sendData " + (result >= 0 ? "success" : "fail") + ": " + message);
            }
        } catch (Exception e) {
            Log.e(TAG, "sendData failed", e);
        }
    }


}