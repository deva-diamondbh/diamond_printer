package com.diamond.printer.diamond_printer

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.diamond.printer.diamond_printer.connection.BluetoothConnectionManager
import com.diamond.printer.diamond_printer.connection.ConnectionManager
import com.diamond.printer.diamond_printer.connection.WiFiConnectionManager
import com.diamond.printer.diamond_printer.protocol.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** DiamondPrinterPlugin */
class DiamondPrinterPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    
    private lateinit var channel: MethodChannel
    private var connectionManager: ConnectionManager? = null
    private var bluetoothManager: BluetoothConnectionManager? = null
    private var wifiManager: WiFiConnectionManager = WiFiConnectionManager()
    private var activity: Activity? = null
    private var applicationContext: android.content.Context? = null
    
    companion object {
        private const val TAG = "DiamondPrinterPlugin"
        private const val PERMISSION_REQUEST_CODE = 12345
    }
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "diamond_printer")
        channel.setMethodCallHandler(this)
        applicationContext = flutterPluginBinding.applicationContext
        bluetoothManager = BluetoothConnectionManager(flutterPluginBinding.applicationContext)
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "scanPrinters" -> {
                handleScanPrinters(call, result)
            }
            "connect" -> {
                handleConnect(call, result)
            }
            "disconnect" -> {
                handleDisconnect(result)
            }
            "isConnected" -> {
                result.success(connectionManager?.isConnected() ?: false)
            }
            "printText" -> {
                handlePrintText(call, result)
            }
            "printImage" -> {
                handlePrintImage(call, result)
            }
            "printPdf" -> {
                handlePrintPdf(call, result)
            }
            "sendRawData" -> {
                handleSendRawData(call, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun handleScanPrinters(call: MethodCall, result: Result) {
        val scanBluetooth = call.argument<Boolean>("bluetooth") ?: true
        val scanWifi = call.argument<Boolean>("wifi") ?: true
        
        if (bluetoothManager == null) {
            result.error("ERROR", "Bluetooth manager not initialized", null)
            return
        }
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val devices = mutableListOf<Map<String, String>>()
                
                if (scanBluetooth) {
                    // Check if we have basic Bluetooth permissions
                    val hasBasicPermissions = hasBasicBluetoothPermissions()
                    val hasFullPermissions = hasBluetoothPermissions()
                    
                    Log.d(TAG, "Basic BT permissions: $hasBasicPermissions, Full permissions: $hasFullPermissions")
                    
                    if (!hasBasicPermissions) {
                        // Request permissions on main thread
                        withContext(Dispatchers.Main) {
                            requestBluetoothPermissions()
                        }
                        // Give paired devices as fallback
                        val pairedDevices = bluetoothManager?.getPairedDevices() ?: emptyList()
                        devices.addAll(pairedDevices)
                        Log.d(TAG, "No permissions - returning ${pairedDevices.size} paired devices")
                    } else if (!hasFullPermissions) {
                        // Has basic permissions but not discovery permissions
                        // Return paired devices only
                        val pairedDevices = bluetoothManager?.getPairedDevices() ?: emptyList()
                        devices.addAll(pairedDevices)
                        Log.d(TAG, "Limited permissions - returning ${pairedDevices.size} paired devices")
                        
                        // Request full permissions for next time
                        withContext(Dispatchers.Main) {
                            requestBluetoothPermissions()
                        }
                    } else {
                        // Has full permissions - do discovery
                        Log.d(TAG, "Starting Bluetooth device discovery...")
                        val btDevices = bluetoothManager?.discoverDevices() ?: emptyList()
                        devices.addAll(btDevices)
                        Log.d(TAG, "Found ${btDevices.size} Bluetooth devices (paired + discovered)")
                    }
                }
                
                // WiFi scanning typically requires manual IP entry
                // We don't auto-discover network printers here
                
                withContext(Dispatchers.Main) {
                    result.success(devices)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error scanning printers: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    // Return paired devices as fallback even on error
                    try {
                        val pairedDevices = bluetoothManager?.getPairedDevices() ?: emptyList()
                        if (pairedDevices.isNotEmpty()) {
                            result.success(pairedDevices)
                        } else {
                            result.error("SCAN_ERROR", e.message, null)
                        }
                    } catch (e2: Exception) {
                        result.error("SCAN_ERROR", e.message, null)
                    }
                }
            }
        }
    }
    
    private fun handleConnect(call: MethodCall, result: Result) {
        val address = call.argument<String>("address")
        val type = call.argument<String>("type") ?: "bluetooth"
        
        if (address == null) {
            result.error("INVALID_ARGUMENT", "Address cannot be null", null)
            return
        }
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Disconnect any existing connection
                connectionManager?.disconnect()
                
                // Wait longer for socket to fully close and resources to be released
                delay(1000) // 1 second delay to ensure socket is fully closed
                
                // Create appropriate connection manager
                connectionManager = when (type.lowercase()) {
                    "bluetooth" -> {
                        if (!hasBluetoothPermissions()) {
                            withContext(Dispatchers.Main) {
                                result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
                            }
                            return@launch
                        }
                        if (bluetoothManager == null) {
                            withContext(Dispatchers.Main) {
                                result.error("ERROR", "Bluetooth manager not initialized", null)
                            }
                            return@launch
                        }
                        // Ensure bluetoothManager is in clean state
                        Log.d(TAG, "Cleaning up bluetoothManager before new connection...")
                        bluetoothManager?.disconnect()
                        delay(500) // Wait for disconnect to complete (BluetoothConnectionManager has 500ms sleep)
                        
                        // Double-check that it's clean, if not wait more
                        var retryCount = 0
                        while (bluetoothManager?.isClean() != true && retryCount < 5) {
                            Log.w(TAG, "BluetoothManager not clean yet, waiting more... (attempt ${retryCount + 1})")
                            delay(200)
                            retryCount++
                        }
                        
                        if (bluetoothManager?.isClean() != true) {
                            Log.w(TAG, "BluetoothManager still not clean after retries, proceeding anyway...")
                        } else {
                            Log.d(TAG, "BluetoothManager is now clean, ready for new connection")
                        }
                        
                        bluetoothManager
                    }
                    "wifi" -> {
                        wifiManager.disconnect()
                        delay(300) // Wait for disconnect to complete (WiFiConnectionManager has 200ms sleep)
                        wifiManager
                    }
                    else -> {
                        withContext(Dispatchers.Main) {
                            result.error("INVALID_TYPE", "Unsupported connection type: $type", null)
                        }
                        return@launch
                    }
                }
                
                // Attempt connection
                val connected = connectionManager?.connect(address) ?: false
                
                withContext(Dispatchers.Main) {
                    result.success(connected)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Connection error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.error("CONNECTION_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun handleDisconnect(result: Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Disconnect the connection manager
                connectionManager?.disconnect()
                
                // Always ensure bluetoothManager is clean (it's a singleton, reused across connections)
                // This is critical because bluetoothManager persists even when connectionManager changes
                bluetoothManager?.disconnect()
                
                // Wait longer to ensure socket is fully closed and resources are released
                delay(1000) // Wait for disconnect to complete (BluetoothConnectionManager has 500ms sleep)
                
                // Verify bluetoothManager is clean with retries
                var retryCount = 0
                while (bluetoothManager?.isClean() != true && retryCount < 3) {
                    Log.w(TAG, "BluetoothManager not clean after disconnect, retrying... (attempt ${retryCount + 1})")
                    bluetoothManager?.disconnect()
                    delay(500)
                    retryCount++
                }
                
                if (bluetoothManager?.isClean() != true) {
                    Log.w(TAG, "BluetoothManager still not clean after retries, but proceeding...")
                } else {
                    Log.d(TAG, "BluetoothManager is now clean")
                }
                
                // Now set to null after cleanup is complete
                connectionManager = null
                Log.d(TAG, "Disconnect handled - connectionManager set to null after cleanup")
                
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Disconnect error: ${e.message}", e)
                // Still try to clean up bluetoothManager
                try {
                    bluetoothManager?.disconnect()
                    delay(500)
                } catch (e2: Exception) {
                    Log.e(TAG, "Error cleaning bluetoothManager: ${e2.message}")
                }
                // Wait a bit before setting to null
                delay(1000)
                connectionManager = null
                
                withContext(Dispatchers.Main) {
                    result.error("DISCONNECT_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun handlePrintText(call: MethodCall, result: Result) {
        val text = call.argument<String>("text")
        val language = call.argument<String>("language") ?: "escpos"
        
        if (text == null) {
            result.error("INVALID_ARGUMENT", "Text cannot be null", null)
            return
        }
        
        if (connectionManager?.isConnected() != true) {
            result.error("NOT_CONNECTED", "Not connected to a printer", null)
            return
        }
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val commandGenerator = getCommandGenerator(language)
                val command = commandGenerator.generateTextCommand(text)
                
                connectionManager?.sendData(command)
                
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Print text error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.error("PRINT_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun handlePrintImage(call: MethodCall, result: Result) {
        val imageBytes = call.argument<ByteArray>("imageBytes")
        val language = call.argument<String>("language") ?: "escpos"
        val configMap = call.argument<Map<String, Any>>("config")
        
        if (imageBytes == null) {
            result.error("INVALID_ARGUMENT", "Image bytes cannot be null", null)
            return
        }
        
        if (connectionManager?.isConnected() != true) {
            result.error("NOT_CONNECTED", "Not connected to a printer", null)
            return
        }
        
        // Extract paper width from config (default to 640 dots for 80mm paper at 203 DPI)
        val paperWidthDots = configMap?.get("paperWidthDots") as? Int ?: 640
        val maxImageWidth = (paperWidthDots * 0.9).toInt() // 90% to allow margins
        
        Log.d(TAG, "Printing image with paper width: ${paperWidthDots}dots (max image width: ${maxImageWidth}px)")
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Convert bytes to bitmap
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                
                if (bitmap == null) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_IMAGE", "Failed to decode image", null)
                    }
                    return@launch
                }
                
                val commandGenerator = getCommandGenerator(language)
                val command = commandGenerator.generateImageCommand(bitmap, maxImageWidth)
                
                connectionManager?.sendData(command)
                
                bitmap.recycle()
                
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Print image error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.error("PRINT_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun handlePrintPdf(call: MethodCall, result: Result) {
        val filePath = call.argument<String>("filePath")
        val language = call.argument<String>("language") ?: "escpos"
        
        if (filePath == null) {
            result.error("INVALID_ARGUMENT", "File path cannot be null", null)
            return
        }
        
        if (connectionManager?.isConnected() != true) {
            result.error("NOT_CONNECTED", "Not connected to a printer", null)
            return
        }
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val file = File(filePath)
                if (!file.exists()) {
                    withContext(Dispatchers.Main) {
                        result.error("FILE_NOT_FOUND", "PDF file not found: $filePath", null)
                    }
                    return@launch
                }
                
                // Open PDF and render pages
                val fileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                val pdfRenderer = PdfRenderer(fileDescriptor)
                val commandGenerator = getCommandGenerator(language)
                
                // Render and print each page
                for (pageIndex in 0 until pdfRenderer.pageCount) {
                    val page = pdfRenderer.openPage(pageIndex)
                    
                    // Create bitmap for the page
                    val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                    
                    // Generate and send print command
                    val command = commandGenerator.generateImageCommand(bitmap)
                    connectionManager?.sendData(command)
                    
                    page.close()
                    bitmap.recycle()
                    
                    // Add page break if not last page
                    if (pageIndex < pdfRenderer.pageCount - 1) {
                        connectionManager?.sendData(commandGenerator.generateFeedCommand(3))
                    }
                }
                
                pdfRenderer.close()
                fileDescriptor.close()
                
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Print PDF error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.error("PRINT_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun handleSendRawData(call: MethodCall, result: Result) {
        val rawBytes = call.argument<ByteArray>("rawBytes")
        
        if (rawBytes == null) {
            result.error("INVALID_ARGUMENT", "Raw bytes cannot be null", null)
            return
        }
        
        if (connectionManager?.isConnected() != true) {
            result.error("NOT_CONNECTED", "Not connected to a printer", null)
            return
        }
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                connectionManager?.sendData(rawBytes)
                
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Send raw data error: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    result.error("SEND_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun getCommandGenerator(language: String): PrinterCommandGenerator {
        return when (language.lowercase()) {
            "escpos", "eos" -> ESCPOSCommandGenerator()
            "cpcl" -> CPCLCommandGenerator()
            "zpl" -> ZPLCommandGenerator()
            else -> ESCPOSCommandGenerator() // Default to ESC/POS
        }
    }
    
    /**
     * Check if we have basic Bluetooth permissions (for paired devices)
     */
    private fun hasBasicBluetoothPermissions(): Boolean {
        val context = applicationContext ?: activity ?: return false
        
        // For Android 12+ (API 31+), need at least BLUETOOTH_CONNECT
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        }
        
        // For older versions, need BLUETOOTH
        return true // BLUETOOTH permission is granted at install time for older versions
    }
    
    /**
     * Check if we have full Bluetooth permissions (including discovery)
     */
    private fun hasBluetoothPermissions(): Boolean {
        val context = applicationContext ?: activity ?: return false
        
        // For Android 12+ (API 31+), need BLUETOOTH_CONNECT and BLUETOOTH_SCAN
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                   ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        }
        
        // For Android 6-11, need BLUETOOTH, BLUETOOTH_ADMIN, and LOCATION for discovery
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            val hasLocation = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Location permission: $hasLocation")
            return hasLocation
        }
        
        // For older versions, all permissions granted at install
        return true
    }
    
    private fun requestBluetoothPermissions() {
        val context = activity
        
        if (context == null) {
            Log.e(TAG, "Activity is null, cannot request permissions")
            return
        }
        
        val permissions = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_SCAN
            )
        } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        } else {
            // No runtime permissions needed for older versions
            return
        }
        
        Log.d(TAG, "Requesting permissions: ${permissions.joinToString()}")
        ActivityCompat.requestPermissions(context, permissions, PERMISSION_REQUEST_CODE)
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            // Handle permission result if needed
            return true
        }
        return false
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        connectionManager?.disconnect()
        bluetoothManager?.cleanup()
    }
    
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
    
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }
    
    override fun onDetachedFromActivity() {
        activity = null
    }
}
