package com.diamond.printer.diamond_printer.connection

import android.util.Log
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Manages WiFi/Network socket connections to printers
 */
class WiFiConnectionManager : ConnectionManager {
    private var socket: Socket? = null
    private var outputStream: OutputStream? = null
    
    companion object {
        private const val TAG = "WiFiConnectionManager"
        private const val DEFAULT_PORT = 9100 // Standard port for network printers
        private const val CONNECTION_TIMEOUT = 5000 // 5 seconds
    }
    
    override fun connect(address: String): Boolean {
        return try {
            // Disconnect any existing connection
            disconnect()
            
            // Parse address (format: "IP:PORT" or just "IP")
            val (ip, port) = parseAddress(address)
            
            // Create socket and connect
            socket = Socket()
            socket?.connect(InetSocketAddress(ip, port), CONNECTION_TIMEOUT)
            
            // Get output stream
            outputStream = socket?.getOutputStream()
            
            Log.d(TAG, "Successfully connected to $ip:$port")
            true
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
            socket?.let { sock ->
                try {
                    val wasConnected = sock.isConnected
                    if (wasConnected) {
                        sock.close()
                        Log.d(TAG, "Socket closed (was connected)")
                    } else {
                        try {
                            sock.close()
                            Log.d(TAG, "Socket closed (was not connected)")
                        } catch (e: Exception) {
                            Log.w(TAG, "Socket already closed or error: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Error closing socket: ${e.message}")
                }
            }
            
            // Small delay to ensure socket is fully closed (WiFi sockets are usually faster)
            Thread.sleep(200)
        } catch (e: Exception) {
            Log.e(TAG, "Error during disconnect: ${e.message}")
        } finally {
            // Always nullify references to ensure clean state
            outputStream = null
            socket = null
            Log.d(TAG, "Disconnect complete - socket and stream set to null")
        }
    }
    
    override fun isConnected(): Boolean {
        return socket?.isConnected == true && socket?.isClosed == false
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
     * Parse address string into IP and port
     */
    private fun parseAddress(address: String): Pair<String, Int> {
        val parts = address.split(":")
        val ip = parts[0]
        val port = if (parts.size > 1) parts[1].toIntOrNull() ?: DEFAULT_PORT else DEFAULT_PORT
        return Pair(ip, port)
    }
}

