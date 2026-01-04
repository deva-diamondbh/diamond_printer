package com.diamond.printer.diamond_printer.connection

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import java.io.IOException
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
        private const val DISCOVERY_TIMEOUT = 15000L // 15 seconds - increased for better Classic Bluetooth device discovery
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
            
            // Double-check that socket is null before proceeding
            var cleanupRetries = 0
            while (bluetoothSocket != null && cleanupRetries < 3) {
                Log.w(TAG, "Socket still exists after disconnect, forcing cleanup... (attempt ${cleanupRetries + 1})")
                try {
                    bluetoothSocket?.let { socket ->
                        try {
                            if (socket.isConnected) {
                                socket.close()
                                Log.d(TAG, "Force closed connected socket")
                            } else {
                                socket.close()
                                Log.d(TAG, "Force closed unconnected socket")
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Error force closing socket: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error accessing socket during cleanup: ${e.message}")
                }
                bluetoothSocket = null
                outputStream = null
                Thread.sleep(400) // Wait longer for each retry
                cleanupRetries++
            }
            
            if (bluetoothSocket != null) {
                Log.e(TAG, "WARNING: Socket still exists after cleanup attempts, proceeding anyway")
                // Force nullify even if close failed
                bluetoothSocket = null
                outputStream = null
                Thread.sleep(500) // Final wait
            }
            
            Log.d(TAG, "Attempting to connect to $address (socket is null: ${bluetoothSocket == null})")
            
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
            
            // Try standard connection first (most reliable for Bixolon SPP-R310)
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
                // Slightly longer delay before trying next method (for Bixolon devices)
                Thread.sleep(300)
            }
            
            // Try insecure connection as fallback (some Bixolon models prefer this)
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
                // Slightly longer delay before trying next method (for Bixolon devices)
                Thread.sleep(300)
            }
            
            // Try reflection-based connection as last resort (for problematic Bixolon devices)
            try {
                Log.d(TAG, "Trying reflection-based connection (Bixolon fallback)...")
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
                    // Check if socket is connected before trying to close
                    val wasConnected = socket.isConnected
                    if (wasConnected) {
                        socket.close()
                        Log.d(TAG, "Socket closed (was connected)")
                    } else {
                        // Even if not connected, try to close to clean up
                        try {
                            socket.close()
                            Log.d(TAG, "Socket closed (was not connected)")
                        } catch (e: Exception) {
                            Log.w(TAG, "Socket already closed or error: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error closing socket: ${e.message}")
                }
            }
            
            // Wait longer to ensure socket is fully closed and resources are released
            Thread.sleep(500)
        } catch (e: Exception) {
            Log.e(TAG, "Error during disconnect: ${e.message}")
        } finally {
            // Always nullify references to ensure clean state
            outputStream = null
            bluetoothSocket = null
            Log.d(TAG, "Disconnect complete - socket and stream set to null")
        }
    }
    
    override fun isConnected(): Boolean {
        return try {
            bluetoothSocket?.isConnected == true
        } catch (e: Exception) {
            // If there's an error checking connection, assume not connected
            Log.w(TAG, "Error checking connection state: ${e.message}")
            false
        }
    }
    
    /**
     * Check if the connection manager is in a clean state (no active socket)
     */
    fun isClean(): Boolean {
        return bluetoothSocket == null && outputStream == null
    }
    
    override fun getOutputStream(): OutputStream? {
        return outputStream
    }
    
    override fun sendData(data: ByteArray) {
        var retryCount = 0
        val maxRetries = 3
        
        while (retryCount <= maxRetries) {
            try {
                if (!isConnected()) {
                    throw IllegalStateException("Not connected to a device")
                }
                
                val outputStream = this.outputStream ?: throw IllegalStateException("Output stream is null")
                
                // For small text data (< 1KB), send immediately without delays to avoid gaps
                // For large images, use chunking and delays to prevent buffer overflow
                if (data.size < 1024) {
                    // Small data (text) - send immediately without delays
                    outputStream.write(data)
                    outputStream.flush()
                    Log.d(TAG, "Sent ${data.size} bytes (text, no delays)")
                } else {
                    // Large data (images) - use chunking and delays
                    val chunkSize = when {
                        data.size > 20000 -> 512  // 512 bytes for very large images (>20KB)
                        data.size > 10000 -> 768  // 768 bytes for large images (>10KB)
                        else -> 1024              // 1KB for medium data
                    }
                    
                    var offset = 0
                    
                    while (offset < data.size) {
                        // Verify connection before each chunk
                        if (!isConnected()) {
                            throw IllegalStateException("Connection lost during transmission")
                        }
                        
                        val remaining = data.size - offset
                        val currentChunkSize = minOf(chunkSize, remaining)
                        
                        // Write chunk
                        outputStream.write(data, offset, currentChunkSize)
                        outputStream.flush()
                        
                        offset += currentChunkSize
                        
                        // Delays between chunks only for large images
                        // This prevents "Broken pipe" errors by giving printer time to process
                        if (offset < data.size) {
                            val delayMs = when {
                                data.size > 20000 -> 30L  // 30ms for very large images
                                data.size > 10000 -> 20L  // 20ms for large images
                                else -> 10L               // 10ms for medium data
                            }
                            Thread.sleep(delayMs)
                        }
                    }
                    
                    // Final delay only for large images
                    outputStream.flush()
                    val finalDelayMs = when {
                        data.size > 20000 -> 300L // 300ms for very large images (>20KB)
                        data.size > 10000 -> 200L // 200ms for large images (>10KB)
                        else -> 50L               // 50ms for medium data
                    }
                    Thread.sleep(finalDelayMs)
                    Log.d(TAG, "Sent ${data.size} bytes in chunks (chunk size: $chunkSize, final delay: ${finalDelayMs}ms)")
                }
                
                return // Success - exit retry loop
                
            } catch (e: IOException) {
                // Handle "Broken pipe" and other IO errors with retry
                if (e.message?.contains("Broken pipe", ignoreCase = true) == true || 
                    e.message?.contains("Connection reset", ignoreCase = true) == true) {
                    retryCount++
                    if (retryCount <= maxRetries) {
                        Log.w(TAG, "Connection error (${e.message}), retrying... (attempt $retryCount/$maxRetries)")
                        // Wait before retry with exponential backoff
                        val retryDelay = minOf(1000L, 200L * retryCount)
                        Thread.sleep(retryDelay)
                        
                        // Try to reconnect if connection is lost
                        if (!isConnected()) {
                            Log.w(TAG, "Connection lost, attempting to reconnect...")
                            // Note: Reconnection would need the device address, which we don't have here
                            // For now, just throw the error
                            throw IllegalStateException("Connection lost and cannot reconnect without device address")
                        }
                    } else {
                        Log.e(TAG, "Failed to send data after $maxRetries retries: ${e.message}", e)
                        throw e
                    }
                } else {
                    // Non-retryable IO error
                    Log.e(TAG, "IO error sending data: ${e.message}", e)
                    throw e
                }
            } catch (e: Exception) {
                // Non-IO errors are not retried
                Log.e(TAG, "Error sending data: ${e.message}", e)
                throw e
            }
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
     * CRITICAL: Paired devices are included first (important for Classic Bluetooth devices like Bixolon)
     */
    private fun getAllDevices(): List<Map<String, String>> {
        val devices = mutableListOf<Map<String, String>>()
        val addedAddresses = mutableSetOf<String>()
        
        try {
            // Add paired devices first (CRITICAL for Bixolon SPP-R310 and similar Classic Bluetooth devices)
            // Bixolon printers often need to be paired first before they appear in discovery
            bluetoothAdapter?.bondedDevices?.forEach { device ->
                try {
                    val deviceName = device.name?.takeIf { it.isNotBlank() } 
                        ?: "Bluetooth Device (${device.address.takeLast(8)})"
                    val deviceInfo = mapOf(
                        "name" to deviceName,
                        "address" to device.address,
                        "type" to "bluetooth",
                        "bonded" to "true"
                    )
                    devices.add(deviceInfo)
                    addedAddresses.add(device.address)
                    Log.d(TAG, "Added paired device: $deviceName - ${device.address}")
                } catch (e: SecurityException) {
                    Log.w(TAG, "SecurityException accessing paired device ${device.address}: ${e.message}")
                    // Try to add with minimal info
                    try {
                        devices.add(
                            mapOf(
                                "name" to "Bluetooth Device",
                                "address" to device.address,
                                "type" to "bluetooth",
                                "bonded" to "true"
                            )
                        )
                        addedAddresses.add(device.address)
                    } catch (e2: Exception) {
                        Log.e(TAG, "Failed to add device even with minimal info: ${e2.message}")
                    }
                }
            }
            
            // Add newly discovered devices (even if they don't have names)
            discoveredDevices.forEach { device ->
                if (!addedAddresses.contains(device.address)) {
                    try {
                        val deviceName = device.name?.takeIf { it.isNotBlank() }
                            ?: "Bluetooth Device (${device.address.takeLast(8)})"
                        val deviceInfo = mapOf(
                            "name" to deviceName,
                            "address" to device.address,
                            "type" to "bluetooth",
                            "bonded" to "false"
                        )
                        devices.add(deviceInfo)
                        addedAddresses.add(device.address)
                        Log.d(TAG, "Added discovered device: $deviceName - ${device.address}")
                    } catch (e: SecurityException) {
                        Log.w(TAG, "SecurityException accessing discovered device ${device.address}: ${e.message}")
                        // Still try to add with address only
                        try {
                            devices.add(
                                mapOf(
                                    "name" to "Bluetooth Device",
                                    "address" to device.address,
                                    "type" to "bluetooth",
                                    "bonded" to "false"
                                )
                            )
                            addedAddresses.add(device.address)
                        } catch (e2: Exception) {
                            Log.e(TAG, "Failed to add discovered device: ${e2.message}")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting all devices: ${e.message}", e)
        }
        
        Log.d(TAG, "Total devices found: ${devices.size} (${addedAddresses.size} unique addresses)")
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

