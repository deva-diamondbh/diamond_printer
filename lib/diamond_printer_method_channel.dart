import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diamond_printer_platform_interface.dart';
import 'models/printer_device.dart';

/// An implementation of [DiamondPrinterPlatform] that uses method channels.
class MethodChannelDiamondPrinter extends DiamondPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('diamond_printer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<List<PrinterDevice>> scanPrinters({bool bluetooth = true, bool wifi = true}) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('scanPrinters', {
      'bluetooth': bluetooth,
      'wifi': wifi,
    });

    if (result == null) {
      return [];
    }

    return result.map((item) => PrinterDevice.fromMap(item as Map<dynamic, dynamic>)).toList();
  }

  @override
  Future<bool> connect(String address, {String type = 'bluetooth'}) async {
    final result = await methodChannel.invokeMethod<bool>('connect', {'address': address, 'type': type});
    return result ?? false;
  }

  @override
  Future<void> disconnect() async {
    await methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> printText(String text, {String language = 'escpos'}) async {
    await methodChannel.invokeMethod<void>('printText', {'text': text, 'language': language});
  }

  @override
  Future<void> printImage(Uint8List imageBytes, {String language = 'escpos', Map<String, dynamic>? config}) async {
    await methodChannel.invokeMethod<void>('printImage', {
      'imageBytes': imageBytes,
      'language': language,
      'config': config,
    });
  }

  @override
  Future<void> printPdf(String filePath, {String language = 'escpos'}) async {
    await methodChannel.invokeMethod<void>('printPdf', {'filePath': filePath, 'language': language});
  }

  @override
  Future<void> sendRawData(Uint8List rawBytes) async {
    await methodChannel.invokeMethod<void>('sendRawData', {'rawBytes': rawBytes});
  }

  @override
  Future<bool> isConnected() async {
    final result = await methodChannel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }
}
