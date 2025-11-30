package com.diamond.printer.diamond_printer.connection

import java.io.OutputStream

/**
 * Base interface for all connection types
 */
interface ConnectionManager {
    fun connect(address: String): Boolean
    fun disconnect()
    fun isConnected(): Boolean
    fun getOutputStream(): OutputStream?
    fun sendData(data: ByteArray)
}

