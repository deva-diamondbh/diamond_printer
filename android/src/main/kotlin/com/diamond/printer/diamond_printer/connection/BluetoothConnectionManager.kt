package com.diamond.printer.diamond_printer.connection

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import java.io.OutputStream
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Manages Bluetooth SPP connections to printers
 */
class BluetoothConnectionManager(private val context: Context) : ConnectionManager {
    private var bluetoothSocket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private var discoveryReceiver: BroadcastReceiver? = null
    private val discoveredDevices = mutableSetOf<BluetoothDevice>()
    
    companion object {
        private const val TAG = "BTConnectionManager"
        // Standard SPP UUID for serial communication
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val DISCOVERY_TIMEOUT = 12000L // 12 seconds
    }
    
    override fun connect(address: String): Boolean {
        return try {
            if (bluetoothAdapter == null) {
                Log.e(TAG, "Bluetooth adapter not available")
                return false
            }
            
            if (!bluetoothAdapter.isEnabled) {
                Log.e(TAG, "Bluetooth is not enabled")
                return false
            }
            
            // Disconnect any existing connection
            disconnect()
            
            Log.d(TAG, "Attempting to connect to $address")
            
            // Get the Bluetooth device
            val device: BluetoothDevice = try {
                bluetoothAdapter.getRemoteDevice(address)
            } catch (e: Exception) {
                Log.e(TAG, "Invalid device address: $address", e)
                return false
            }
            
            // Cancel discovery to improve connection speed
            try {
                if (bluetoothAdapter.isDiscovering) {
                    bluetoothAdapter.cancelDiscovery()
                    Log.d(TAG, "Discovery cancelled")
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "SecurityException cancelling discovery: ${e.message}")
            }
            
            // Try standard connection first
            try {
                Log.d(TAG, "Trying secure connection...")
                bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                bluetoothSocket?.connect()
                
                if (bluetoothSocket?.isConnected == true) {
                    outputStream = bluetoothSocket?.outputStream
                    Log.d(TAG, "✓ Successfully connected to $address (secure)")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Secure connection failed: ${e.message}")
                disconnect()
            }
            
            // Try insecure connection as fallback
            try {
                Log.d(TAG, "Trying insecure connection...")
                bluetoothSocket = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                bluetoothSocket?.connect()
                
                if (bluetoothSocket?.isConnected == true) {
                    outputStream = bluetoothSocket?.outputStream
                    Log.d(TAG, "✓ Successfully connected to $address (insecure)")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Insecure connection failed: ${e.message}")
                disconnect()
            }
            
            // Try reflection-based connection as last resort (for problematic devices)
            try {
                Log.d(TAG, "Trying reflection-based connection...")
                val socket = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    .invoke(device, 1) as BluetoothSocket
                bluetoothSocket = socket
                socket.connect()
                
                if (socket.isConnected) {
                    outputStream = socket.outputStream
                    Log.d(TAG, "✓ Successfully connected to $address (reflection)")
                    return true
                }
            } catch (e: Exception) {
                Log.w(TAG, "Reflection connection failed: ${e.message}")
                disconnect()
            }
            
            Log.e(TAG, "All connection methods failed for $address")
            false
            
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException - Missing Bluetooth permissions: ${e.message}", e)
            disconnect()
            false
        } catch (e: Exception) {
            Log.e(TAG, "Connection failed: ${e.message}", e)
            disconnect()
            false
        }
    }
    
    override fun disconnect() {
        try {
            // Close output stream first
            outputStream?.let {
                try {
                    it.flush()
                    it.close()
                    Log.d(TAG, "OutputStream closed")
                } catch (e: Exception) {
                    Log.w(TAG, "Error closing output stream: ${e.message}")
                }
            }
            
            // Close socket with proper cleanup
            bluetoothSocket?.let { socket ->
                try {
                    if (socket.isConnected) {
                        socket.close()
                        Log.d(TAG, "Socket closed")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error closing socket: ${e.message}")
                }
            }
            
            // Wait a bit to ensure socket is fully closed
            Thread.sleep(200)
        } catch (e: Exception) {
            Log.e(TAG, "Error during disconnect: ${e.message}")
        } finally {
            outputStream = null
            bluetoothSocket = null
            Log.d(TAG, "Disconnect complete - socket and stream set to null")
        }
    }
    
    override fun isConnected(): Boolean {
        return bluetoothSocket?.isConnected == true
    }
    
    override fun getOutputStream(): OutputStream? {
        return outputStream
    }
    
    override fun sendData(data: ByteArray) {
        try {
            if (!isConnected()) {
                throw IllegalStateException("Not connected to a device")
            }
            
            outputStream?.write(data)
            outputStream?.flush()
            
            Log.d(TAG, "Sent ${data.size} bytes")
        } catch (e: Exception) {
            Log.e(TAG, "Error sending data: ${e.message}", e)
            throw e
        }
    }
    
    /**
     * Get paired Bluetooth devices (immediate, no discovery)
     * This method works even without runtime permissions on most Android versions
     */
    fun getPairedDevices(): List<Map<String, String>> {
        val devices = mutableListOf<Map<String, String>>()
        
        try {
            if (bluetoothAdapter == null) {
                Log.e(TAG, "Bluetooth adapter not available")
                return devices
            }
            
            if (!bluetoothAdapter.isEnabled) {
                Log.w(TAG, "Bluetooth is not enabled")
                return devices
            }
            
            val bondedDevices = try {
                bluetoothAdapter.bondedDevices
            } catch (e: SecurityException) {
                Log.e(TAG, "SecurityException getting bonded devices: ${e.message}")
                return devices
            }
            
            bondedDevices?.forEach { device ->
                try {
                    devices.add(
                        mapOf(
                            "name" to (device.name ?: "Unknown Device"),
                            "address" to device.address,
                            "type" to "bluetooth",
                            "bonded" to "true"
                        )
                    )
                    Log.d(TAG, "Found paired device: ${device.name} - ${device.address}")
                } catch (e: SecurityException) {
                    Log.e(TAG, "SecurityException accessing device: ${e.message}")
                    // Try to add just the address
                    devices.add(
                        mapOf(
                            "name" to "Bluetooth Device",
                            "address" to device.address,
                            "type" to "bluetooth",
                            "bonded" to "true"
                        )
                    )
                }
            }
            
            Log.d(TAG, "Total paired devices: ${devices.size}")
        } catch (e: Exception) {
            Log.e(TAG, "Error getting paired devices: ${e.message}", e)
        }
        
        return devices
    }
    
    /**
     * Discover nearby Bluetooth devices (includes paired + newly discovered)
     */
    suspend fun discoverDevices(): List<Map<String, String>> {
        if (bluetoothAdapter == null) {
            Log.e(TAG, "Bluetooth adapter not available")
            return getPairedDevices() // Return paired devices as fallback
        }
        
        if (!bluetoothAdapter.isEnabled) {
            Log.e(TAG, "Bluetooth is not enabled")
            return getPairedDevices()
        }
        
        // Cancel any ongoing discovery
        if (bluetoothAdapter.isDiscovering) {
            bluetoothAdapter.cancelDiscovery()
        }
        
        discoveredDevices.clear()
        
        return suspendCancellableCoroutine { continuation ->
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.action) {
                        BluetoothDevice.ACTION_FOUND -> {
                            val device: BluetoothDevice? = 
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                            device?.let {
                                Log.d(TAG, "Found device: ${it.name} - ${it.address}")
                                discoveredDevices.add(it)
                            }
                        }
                        BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                            Log.d(TAG, "Discovery finished")
                            try {
                                context.unregisterReceiver(this)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error unregistering receiver: ${e.message}")
                            }
                            
                            if (continuation.isActive) {
                                val allDevices = getAllDevices()
                                continuation.resume(allDevices)
                            }
                        }
                    }
                }
            }
            
            discoveryReceiver = receiver
            
            // Register receiver for discovery events
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            
            try {
                context.registerReceiver(receiver, filter)
                
                // Start discovery
                val started = bluetoothAdapter.startDiscovery()
                Log.d(TAG, "Discovery started: $started")
                
                if (!started) {
                    // If discovery failed to start, return paired devices immediately
                    try {
                        context.unregisterReceiver(receiver)
                    } catch (e: Exception) {
                        // Ignore
                    }
                    if (continuation.isActive) {
                        continuation.resume(getPairedDevices())
                    }
                }
                
                // Set up timeout
                CoroutineScope(Dispatchers.IO).launch {
                    delay(DISCOVERY_TIMEOUT)
                    if (continuation.isActive) {
                        Log.d(TAG, "Discovery timeout reached")
                        bluetoothAdapter.cancelDiscovery()
                        try {
                            context.unregisterReceiver(receiver)
                        } catch (e: Exception) {
                            // Already unregistered
                        }
                        val allDevices = getAllDevices()
                        continuation.resume(allDevices)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error during discovery: ${e.message}", e)
                if (continuation.isActive) {
                    continuation.resume(getPairedDevices())
                }
            }
            
            continuation.invokeOnCancellation {
                bluetoothAdapter.cancelDiscovery()
                try {
                    context.unregisterReceiver(receiver)
                } catch (e: Exception) {
                    // Already unregistered
                }
            }
        }
    }
    
    /**
     * Get all devices (paired + discovered)
     */
    private fun getAllDevices(): List<Map<String, String>> {
        val devices = mutableListOf<Map<String, String>>()
        val addedAddresses = mutableSetOf<String>()
        
        try {
            // Add paired devices first
            bluetoothAdapter?.bondedDevices?.forEach { device ->
                devices.add(
                    mapOf(
                        "name" to (device.name ?: "Unknown Device"),
                        "address" to device.address,
                        "type" to "bluetooth",
                        "bonded" to "true"
                    )
                )
                addedAddresses.add(device.address)
            }
            
            // Add newly discovered devices
            discoveredDevices.forEach { device ->
                if (!addedAddresses.contains(device.address)) {
                    devices.add(
                        mapOf(
                            "name" to (device.name ?: "Unknown Device"),
                            "address" to device.address,
                            "type" to "bluetooth",
                            "bonded" to "false"
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting all devices: ${e.message}")
        }
        
        Log.d(TAG, "Total devices found: ${devices.size}")
        return devices
    }
    
    fun cleanup() {
        try {
            bluetoothAdapter?.cancelDiscovery()
            discoveryReceiver?.let {
                context.unregisterReceiver(it)
            }
        } catch (e: Exception) {
            // Ignore cleanup errors
        }
    }
}

