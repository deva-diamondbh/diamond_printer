import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diamond_printer_platform_interface.dart';
import 'models/printer_device.dart';

/// Method channel implementation of [DiamondPrinterPlatform].
///
/// This class provides the default implementation using Flutter's method
/// channels to communicate with native platform code (Android/iOS).
/// The method channel name is 'diamond_printer'.
///
/// This implementation is used by default and handles all communication
/// between Dart code and native platform implementations.
///
/// Example:
/// ```dart
/// // The default instance uses this implementation
/// final platform = DiamondPrinterPlatform.instance;
/// final devices = await platform.scanPrinters();
/// ```
class MethodChannelDiamondPrinter extends DiamondPrinterPlatform {
  /// The method channel used to interact with the native platform.
  ///
  /// The channel name is 'diamond_printer' and must match the channel
  /// name used in the native platform code (Android/iOS).
  ///
  /// This is marked as `@visibleForTesting` to allow test implementations
  /// to mock or verify method channel calls.
  @visibleForTesting
  final methodChannel = const MethodChannel('diamond_printer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<List<PrinterDevice>> scanPrinters({
    bool bluetooth = true,
    bool wifi = true,
  }) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('scanPrinters', {
      'bluetooth': bluetooth,
      'wifi': wifi,
    });

    if (result == null) {
      return [];
    }

    return result
        .map((item) => PrinterDevice.fromMap(item as Map<dynamic, dynamic>))
        .toList();
  }

  @override
  Future<bool> connect(String address, {String type = 'bluetooth'}) async {
    final result = await methodChannel.invokeMethod<bool>(
      'connect',
      {'address': address, 'type': type},
    );
    return result ?? false;
  }

  @override
  Future<void> disconnect() async {
    await methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> printText(
    String text, {
    String language = 'escpos',
    String? alignment,
  }) async {
    await methodChannel.invokeMethod<void>(
      'printText',
      {
        'text': text,
        'language': language,
        if (alignment != null) 'alignment': alignment,
      },
    );
  }

  @override
  Future<void> printImage(
    Uint8List imageBytes, {
    String language = 'escpos',
    Map<String, dynamic>? config,
    String? alignment,
  }) async {
    await methodChannel.invokeMethod<void>('printImage', {
      'imageBytes': imageBytes,
      'language': language,
      'config': config,
      if (alignment != null) 'alignment': alignment,
    });
  }

  @override
  Future<void> printPdf(
    String filePath, {
    String language = 'escpos',
    String? alignment,
  }) async {
    await methodChannel.invokeMethod<void>(
      'printPdf',
      {
        'filePath': filePath,
        'language': language,
        if (alignment != null) 'alignment': alignment,
      },
    );
  }

  @override
  Future<void> sendRawData(Uint8List rawBytes) async {
    await methodChannel.invokeMethod<void>(
      'sendRawData',
      {'rawBytes': rawBytes},
    );
  }

  @override
  Future<bool> isConnected() async {
    final result = await methodChannel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }
}
