import 'package:flutter_test/flutter_test.dart';
import 'package:diamond_printer/diamond_printer.dart';
import 'package:diamond_printer/diamond_printer_platform_interface.dart';
import 'package:diamond_printer/diamond_printer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDiamondPrinterPlatform
    with MockPlatformInterfaceMixin
    implements DiamondPrinterPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DiamondPrinterPlatform initialPlatform = DiamondPrinterPlatform.instance;

  test('$MethodChannelDiamondPrinter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDiamondPrinter>());
  });

  test('getPlatformVersion', () async {
    DiamondPrinter diamondPrinterPlugin = DiamondPrinter();
    MockDiamondPrinterPlatform fakePlatform = MockDiamondPrinterPlatform();
    DiamondPrinterPlatform.instance = fakePlatform;

    expect(await diamondPrinterPlugin.getPlatformVersion(), '42');
  });
}
