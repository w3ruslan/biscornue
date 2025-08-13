// lib/main.dart
// Tek dosyalık, hatasız POS uygulaması (Sandwich/Burger/Drink + sepet + ağ yazıcı + menü yedekleme)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ESC/POS ağ yazıcı
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils.dart';

// Menü dışa aktarma/paylaşma
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commande Sur Place',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

/// -----------------------
/// Basit veri modelleri
/// -----------------------
class Product {
  final String id;
  final String name;
  final double price;
  final String category;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'price': price, 'category': category};

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        category: j['category'] as String,
      );
}

class CartItem {
  final Product product;
  int qty;

  CartItem(this.product, {this.qty = 1});

  double get lineTotal => product.price * qty;

  Map<String, dynamic> toJson() =>
      {'product': product.toJson(), 'qty': qty};

  factory CartItem.fromJson(Map<String, dynamic> j) =>
      CartItem(Product.fromJson(j['product']), qty: j['qty']);
}

/// Öntanımlı menü
List<Product> defaultMenu() => const [
      Product(id: 's1', name: 'Jambon Fromage', price: 4.20, category: 'Sandwich'),
      Product(id: 's2', name: 'Thon Mayo', price: 4.80, category: 'Sandwich'),
      Product(id: 'b1', name: 'Classic Burger', price: 6.50, category: 'Burger'),
      Product(id: 'b2', name: 'Cheese Burger', price: 6.90, category: 'Burger'),
      Product(id: 'd1', name: 'Coca 33cl', price: 2.00, category: 'Drink'),
      Product(id: 'd2', name: 'Eau 50cl', price: 1.50, category: 'Drink'),
    ];

const _prefMenu = 'menu_json';
const _prefPrinterIp = 'printer_ip';

/// -----------------------
/// Ana Sayfa
/// -----------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final List<String> _cats = const ['Sandwich', 'Burger', 'Drink'];
  late final TabController _tab = TabController(length: 3, vsync: this);

  List<Product> _menu = [];
  final List<CartItem> _cart = [];

  String _printerIp = '192.168.1.1';
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();

    // Menü
    final jsonStr = sp.getString(_prefMenu);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final list = (jsonDecode(jsonStr) as List)
          .map((e) => Product.fromJson(e))
          .toList();
      _menu = list;
    } else {
      _menu = defaultMenu();
    }

    // Yazıcı IP
    _printerIp = sp.getString(_prefPrinterIp) ?? _printerIp;

    setState(() {});
  }

  Future<void> _persistMenu() async {
    final sp = await SharedPreferences.getInstance();
    final js = jsonEncode(_menu.map((e) => e.toJson()).toList());
    await sp.setString(_prefMenu, js);
  }

  double get _total =>
      _cart.fold(0.0, (sum, it) => sum + it.lineTotal);

  void _add(Product p) {
    final i = _cart.indexWhere((e) => e.product.id == p.id);
    setState(() {
      if (i >= 0) {
        _cart[i].qty++;
      } else {
        _cart.add(CartItem(p, qty: 1));
      }
    });
  }

  void _remove(Product p) {
    final i = _cart.indexWhere((e) => e.product.id == p.id);
    if (i < 0) return;
    setState(() {
      if (_cart[i].qty > 1) {
        _cart[i].qty--;
      } else {
        _cart.removeAt(i);
      }
    });
  }

  Future<void> _changePrinterIp() async {
    final c = TextEditingController(text: _printerIp);
    final ip = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Yazıcı IP'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'örn. 192.168.1.1'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ip == null || ip.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefPrinterIp, ip);
    setState(() => _printerIp = ip);
  }

  Future<void> _exportMenu() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/menu_backup.json');
      final js = jsonEncode(_menu.map((e) => e.toJson()).toList());
      await f.writeAsString(js);
      await Share.shareXFiles([XFile(f.path)], text: 'Menü yedeği');
      _snack('Dışa aktarıldı: ${f.path}');
    } catch (e) {
      _snack('Dışa aktarma hatası: $e');
    }
  }

  Future<void> _importMenu() async {
    final c = TextEditingController();
    final js = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Menü içe aktar (JSON yapıştır)'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: c,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[ {"id":"...","name":"...","price":1.0,"category":"..."} ]',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('İçe aktar')),
        ],
      ),
    );
    if (js == null || js.trim().isEmpty) return;
    try {
      final list = (jsonDecode(js) as List)
          .map((e) => Product.fromJson(e))
          .toList();
      setState(() => _menu = list);
      await _persistMenu();
      _snack('Menü güncellendi.');
    } catch (e) {
      _snack('Geçersiz JSON: $e');
    }
  }

  Future<void> _print() async {
    if (_cart.isEmpty) {
      _snack('Sepet boş.');
      return;
    }
    setState(() => _printing = true);
    try {
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm80, profile);

      final res = await printer.connect(_printerIp, port: 9100, timeout: const Duration(seconds: 5));
      if (res.msg != 'Success') {
        _snack('Bağlantı hatası: ${res.msg}');
        setState(() => _printing = false);
        return;
      }

      // Başlık
      printer.text('Commande Sur Place',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ));
      printer.hr();

      // Satırlar
      for (final it in _cart) {
        printer.row([
          PosColumn(text: '${it.qty}x', width: 1),
          PosColumn(text: it.product.name, width: 9),
          PosColumn(
            text: it.lineTotal.toStringAsFixed(2),
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      printer.hr();
      printer.row([
        PosColumn(text: 'TOTAL', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(
          text: '${_total.toStringAsFixed(2)} €',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      printer.hr(ch: '-');

      final now = DateTime.now();
      printer.text(
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        styles: const PosStyles(align: PosAlign.center),
      );

      printer.feed(2);
      printer.cut();
      printer.disconnect();

      setState(() => _cart.clear());
      _snack('Yazdırma tamam.');
    } catch (e) {
      _snack('Yazdırma hatası: $e');
    } finally {
      setState(() => _printing = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cats[_tab.index];
    final items = _menu.where((p) => p.category == cat).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commande Sur Place'),
        actions: [
          IconButton(
            tooltip: 'Yazıcı IP: $_printerIp',
            onPressed: _changePrinterIp,
            icon: const Icon(Icons.print),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') _exportMenu();
              if (v == 'import') _importMenu();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Menüyü dışa aktar')),
              PopupMenuItem(value: 'import', child: Text('Menüyü içe aktar (JSON yapıştır)')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: _cats.map((e) => Tab(text: e)).toList(),
          onTap: (_) => setState(() {}),
        ),
      ),

      // Suivant butonu yukarı çekildi
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: FilledButton.icon(
          onPressed: _printing ? null : _print,
          icon: _printing
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.receipt_long),
          label: const Text('Suivant / Yazdır'),
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: () => _tab.index > 0 ? setState(() => _tab.index -= 1) : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Précedent'),
            ),
            const Spacer(),
            Text('Sepet: ${_cart.length} • ${_total.toStringAsFixed(2)} €',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _tab.index < _cats.length - 1 ? setState(() => _tab.index += 1) : null,
              label: const Text('Suivant'),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),

      body: Row(
        children: [
          // Ürünler
          Expanded(
            flex: 3,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = items[i];
                return ListTile(
                  title: Text(p.name),
                  subtitle: Text('${p.price.toStringAsFixed(2)} €'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(onPressed: () => _remove(p), icon: const Icon(Icons.remove_circle_outline)),
                      IconButton(onPressed: () => _add(p), icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                );
              },
            ),
          ),

          Container(width: 1, color: Colors.black12),

          // Sepet
          Expanded(
            flex: 2,
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Text('Panier (Sepet)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: _cart.isEmpty
                      ? const Center(child: Text('Sepet boş'))
                      : ListView.builder(
                          itemCount: _cart.length,
                          itemBuilder: (_, i) {
                            final c = _cart[i];
                            return ListTile(
                              dense: true,
                              title: Text('${c.qty}x ${c.product.name}'),
                              trailing: Text('${c.lineTotal.toStringAsFixed(2)} €'),
                              onLongPress: () => setState(() => _cart.removeAt(i)),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${_total.toStringAsFixed(2)} €',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
