import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Surplace POS',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const PrinterPage(),
    );
  }
}

class PrinterPage extends StatefulWidget {
  const PrinterPage({super.key});

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  final _ipCtrl = TextEditingController(text: '192.168.1.1');
  final _portCtrl = TextEditingController(text: '9100');

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    _ipCtrl.text = sp.getString('printer_ip') ?? _ipCtrl.text;
    _portCtrl.text = (sp.getInt('printer_port') ?? 9100).toString();
    setState(() {});
  }

  Future<void> _savePrefs() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('printer_ip', _ipCtrl.text.trim());
    await sp.setInt('printer_port', int.tryParse(_portCtrl.text.trim()) ?? 9100);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ayarlar kaydedildi.')),
    );
  }

  Future<void> _printTest() async {
    final ip = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9100;

    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen yazıcı IP adresi girin.')),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      // 1) ESC/POS fişini üret
      final profile = await CapabilityProfile.load(); // default profil
      final generator = Generator(PaperSize.mm80, profile);
      final bytes = <int>[];

      bytes.addAll(generator.text(
        'Surplace POS',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ));
      bytes.addAll(generator.text(
        'Test fişi - ağ yazdırma',
        styles: const PosStyles(align: PosAlign.center),
      ));
      bytes.addAll(generator.hr());
      bytes.addAll(generator.row([
        PosColumn(
          text: 'Ürün',
          width: 8,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: 'Tutar',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: 'Sandwich', width: 8),
        PosColumn(
          text: '6.00€',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: 'Boisson', width: 8),
        PosColumn(
          text: '2.50€',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
      bytes.addAll(generator.hr());
      bytes.addAll(generator.row([
        PosColumn(
          text: 'TOPLAM',
          width: 8,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: '8.50€',
          width: 4,
          styles:
              const PosStyles(align: PosAlign.right, height: PosTextSize.size2),
        ),
      ]));
      bytes.addAll(generator.hr());
      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.text(
        'Teşekkürler!',
        styles: const PosStyles(align: PosAlign.center),
      ));
      bytes.addAll(generator.cut());

      // 2) Yazıcıya gönder (raw TCP 9100)
      final socket =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      socket.add(bytes);
      await socket.flush();
      await socket.close();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yazdırıldı: $ip:$port')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yazdırma hatası: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yazıcı Ayarları & Test'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _savePrefs,
            icon: const Icon(Icons.save),
            tooltip: 'Ayarları Kaydet',
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _ipCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Yazıcı IP adresi',
                hintText: 'örn. 192.168.1.1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '9100',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _printTest,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              label: const Text('Test Fişi Yazdır'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Not: Yazıcıyla aynı Wi-Fi ağında olun. Uygulamanın internet izni '
              'workflow sırasında otomatik ekleniyor.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
