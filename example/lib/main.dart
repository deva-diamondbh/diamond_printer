import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:diamond_printer/diamond_printer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advanced Printer Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PrinterDemoPage(),
    );
  }
}

class PrinterDemoPage extends StatefulWidget {
  const PrinterDemoPage({Key? key}) : super(key: key);

  @override
  State<PrinterDemoPage> createState() => _PrinterDemoPageState();
}

class _PrinterDemoPageState extends State<PrinterDemoPage> {
  final AdvancedPrinter _printer = AdvancedPrinter();
  List<PrinterDevice> _devices = [];
  PrinterDevice? _selectedDevice;
  bool _isScanning = false;
  bool _isConnected = false;
  String _statusMessage = 'Ready';
  String _selectedLanguage = PrinterLanguage.escpos;
  PrinterConfig _printerConfig = PrinterConfig.mm80; // Default 80mm
  final TextEditingController _textController = TextEditingController(
    text: 'Hello from Advanced Printer!\nTest Print',
  );

  @override
  void initState() {
    super.initState();
    _printer.setPrinterConfig(_printerConfig);
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    try {
      final connected = await _printer.isConnected();
      setState(() {
        _isConnected = connected;
        _statusMessage = connected ? 'Connected' : 'Not connected';
      });
    } catch (e) {
      _showError('Error checking connection: $e');
    }
  }

  Future<void> _scanPrinters() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning for printers...';
      _devices = []; // Clear previous results
    });

    try {
      final devices = await _printer.scanPrinters(
        bluetooth: true,
        wifi: false, // WiFi printers typically need manual IP entry
      );
      
      setState(() {
        _devices = devices;
        _isScanning = false;
        if (devices.isEmpty) {
          _statusMessage = 'No printers found. Make sure Bluetooth is ON and printer is powered on.';
        } else {
          _statusMessage = 'Found ${devices.length} printer(s)';
        }
      });
      
      if (devices.isEmpty) {
        _showError(
          'No printers found.\n\n'
          '1. Turn on Bluetooth in settings\n'
          '2. Power on your printer\n'
          '3. Grant location permission if prompted\n'
          '4. Try scanning again'
        );
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMessage = 'Scan failed';
      });
      _showError('Scan failed: $e\n\nMake sure you granted all permissions.');
    }
  }

  Future<void> _connectToPrinter(PrinterDevice device) async {
    setState(() {
      _statusMessage = 'Connecting to ${device.name}...';
    });

    try {
      final connected = await _printer.connect(
        device.address,
        type: device.type,
      );

      setState(() {
        _isConnected = connected;
        if (connected) {
          _selectedDevice = device;
          _statusMessage = 'Connected to ${device.name}';
        } else {
          _statusMessage = 'Connection failed';
        }
      });

      if (connected) {
        _showSuccess('Connected to ${device.name}');
      } else {
        _showError(
          'Failed to connect to ${device.name}\n\n'
          'Tips:\n'
          '• Make sure printer is powered on\n'
          '• Try turning printer off and on\n'
          '• Check printer is within range\n'
          '• Try pairing again in Settings'
        );
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _statusMessage = 'Connection error';
      });
      _showError('Connection error: $e\n\nMake sure Bluetooth permissions are granted.');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _printer.disconnect();
      setState(() {
        _isConnected = false;
        _selectedDevice = null;
        _statusMessage = 'Disconnected';
      });
    } catch (e) {
      _showError('Disconnect error: $e');
    }
  }

  Future<void> _printText() async {
    if (!_isConnected) {
      _showError('Not connected to a printer');
      return;
    }

    final text = _textController.text;
    if (text.isEmpty) {
      _showError('Please enter text to print');
      return;
    }

    setState(() {
      _statusMessage = 'Printing text...';
    });

    try {
      await _printer.printText(text, language: _selectedLanguage);
      setState(() {
        _statusMessage = 'Text printed successfully';
      });
      _showSuccess('Text printed successfully');
    } catch (e) {
      setState(() {
        _statusMessage = 'Print failed';
      });
      _showError('Print failed: $e');
    }
  }

  Future<void> _printTestImage() async {
    if (!_isConnected) {
      _showError('Not connected to a printer');
      return;
    }

    setState(() {
      _statusMessage = 'Printing test image...';
    });

    try {
      // Try to load inv.png first (for testing), fallback to test_image.png
      Uint8List bytes;
      try {
        final ByteData data = await rootBundle.load('assets/images/inv.png');
        bytes = data.buffer.asUint8List();
        debugPrint('Loaded asset image: inv.png (${bytes.length} bytes)');
      } catch (e) {
        // Fallback to test_image.png
        final ByteData data = await rootBundle.load('assets/test_image.png');
        bytes = data.buffer.asUint8List();
        debugPrint('Loaded asset image: test_image.png (${bytes.length} bytes)');
      }

      await _printer.printImage(bytes, language: _selectedLanguage, config: _printerConfig);
      
      setState(() {
        _statusMessage = 'Image printed successfully';
      });
      _showSuccess('Image printed successfully');
    } catch (e) {
      setState(() {
        _statusMessage = 'Print failed';
      });
      _showError('Print image failed: $e. Make sure assets/images/inv.png or assets/test_image.png exists.');
    }
  }

  Future<void> _printTestReceipt() async {
    if (!_isConnected) {
      _showError('Not connected to a printer');
      return;
    }

    setState(() {
      _statusMessage = 'Printing test receipt...';
    });

    try {
      final receipt = '''
================================
         TEST RECEIPT
================================
Date: ${DateTime.now().toString().substring(0, 19)}

Item 1              \$10.00
Item 2              \$15.50
Item 3               \$7.25
--------------------------------
Subtotal:           \$32.75
Tax (10%):           \$3.28
--------------------------------
TOTAL:              \$36.03
================================
   Thank you for your purchase!
================================
''';

      await _printer.printText(receipt, language: _selectedLanguage);
      
      setState(() {
        _statusMessage = 'Receipt printed successfully';
      });
      _showSuccess('Receipt printed successfully');
    } catch (e) {
      setState(() {
        _statusMessage = 'Print failed';
      });
      _showError('Print receipt failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Printer Demo'),
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.check_circle : Icons.error,
                          color: _isConnected ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status: $_statusMessage',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    if (_selectedDevice != null) ...[
                      const SizedBox(height: 8),
                      Text('Device: ${_selectedDevice!.name}'),
                      Text('Address: ${_selectedDevice!.address}'),
                      Text('Type: ${_selectedDevice!.type}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Printer Configuration
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Printer Language',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: PrinterLanguage.escpos,
                          label: Text('ESC/POS'),
                        ),
                        ButtonSegment(
                          value: PrinterLanguage.cpcl,
                          label: Text('CPCL'),
                        ),
                        ButtonSegment(
                          value: PrinterLanguage.zpl,
                          label: Text('ZPL'),
                        ),
                      ],
                      selected: {_selectedLanguage},
                      onSelectionChanged: (Set<String> selection) {
                        setState(() {
                          _selectedLanguage = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Paper Width',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<PrinterConfig>(
                      value: _printerConfig,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: PrinterConfig.mm58,
                          child: Text('58mm (2 inch) - Mobile printers'),
                        ),
                        DropdownMenuItem(
                          value: PrinterConfig.mm80,
                          child: Text('80mm (3 inch) - Most common ⭐'),
                        ),
                        DropdownMenuItem(
                          value: PrinterConfig.mm100,
                          child: Text('100mm (4 inch) - Wide labels'),
                        ),
                      ],
                      onChanged: (PrinterConfig? config) {
                        if (config != null) {
                          setState(() {
                            _printerConfig = config;
                          });
                          _printer.setPrinterConfig(config);
                          _showSuccess('Paper width set to ${config.paperWidthMM.toStringAsFixed(0)}mm');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Connection Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Connection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isScanning ? null : _scanPrinters,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: Text(_isScanning ? 'Scanning...' : 'Scan for Printers'),
                    ),
                    if (_devices.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Available Printers:'),
                      const SizedBox(height: 8),
                      ..._devices.map((device) => ListTile(
                            leading: const Icon(Icons.print),
                            title: Text(device.name),
                            subtitle: Text('${device.address} (${device.type})'),
                            trailing: _selectedDevice?.address == device.address
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            onTap: () => _connectToPrinter(device),
                          )),
                    ],
                    if (_isConnected) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _disconnect,
                        icon: const Icon(Icons.close),
                        label: const Text('Disconnect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Print Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Print Operations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        labelText: 'Text to Print',
                        border: OutlineInputBorder(),
                        hintText: 'Enter text here',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isConnected ? _printText : null,
                      icon: const Icon(Icons.text_fields),
                      label: const Text('Print Text'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isConnected ? _printTestReceipt : null,
                      icon: const Icon(Icons.receipt),
                      label: const Text('Print Test Receipt'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isConnected ? _printTestImage : null,
                      icon: const Icon(Icons.image),
                      label: const Text('Print Test Image'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info Card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'How to Use',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('1. Select your printer language (ESC/POS, CPCL, or ZPL)'),
                    const Text('2. Scan for available printers'),
                    const Text('3. Tap a printer to connect'),
                    const Text('4. Use the print buttons to test printing'),
                    const SizedBox(height: 8),
                    Text(
                      'Note: For Bluetooth printers, make sure they are paired in device settings first.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
