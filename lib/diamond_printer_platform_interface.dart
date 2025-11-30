import 'dart:typed_data';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'diamond_printer_method_channel.dart';
import 'models/printer_device.dart';

abstract class DiamondPrinterPlatform extends PlatformInterface {
  /// Constructs a DiamondPrinterPlatform.
  DiamondPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static DiamondPrinterPlatform _instance = MethodChannelDiamondPrinter();

  /// The default instance of [DiamondPrinterPlatform] to use.
  ///
  /// Defaults to [MethodChannelDiamondPrinter].
  static DiamondPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DiamondPrinterPlatform] when
  /// they register themselves.
  static set instance(DiamondPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
  
  Future<List<PrinterDevice>> scanPrinters({
    bool bluetooth = true,
    bool wifi = true,
  }) {
    throw UnimplementedError('scanPrinters() has not been implemented.');
  }
  
  Future<bool> connect(String address, {String type = 'bluetooth'}) {
    throw UnimplementedError('connect() has not been implemented.');
  }
  
  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }
  
  Future<void> printText(String text, {String language = 'escpos'}) {
    throw UnimplementedError('printText() has not been implemented.');
  }
  
  Future<void> printImage(Uint8List imageBytes, {String language = 'escpos', Map<String, dynamic>? config}) {
    throw UnimplementedError('printImage() has not been implemented.');
  }
  
  Future<void> printPdf(String filePath, {String language = 'escpos'}) {
    throw UnimplementedError('printPdf() has not been implemented.');
  }
  
  Future<void> sendRawData(Uint8List rawBytes) {
    throw UnimplementedError('sendRawData() has not been implemented.');
  }
  
  Future<bool> isConnected() {
    throw UnimplementedError('isConnected() has not been implemented.');
  }
}
