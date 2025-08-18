import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart'; // HATA GİDERİLDİ: Eksik olan temel Flutter paketi eklendi.
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';

/* =======================
    Sabitler (Varsayılan Değerler)
    ======================= */
const String PRINTER_IP = '192.168.1.1';
const int    PRINTER_PORT = 9100;
const String _ADMIN_PIN = '6538';

/* =======================
    ENTRY
    ======================= */
void main() {
  final appState = AppState();
  appState.loadSettings();
  runApp(AppScope(notifier: appState, child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BISCORNUE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const Home(),
    );
  }
}

/* =======================
    AYARLAR MODELİ
    ======================= */
String _fnv64(String s, {String salt = 'bis-1'}) {
  final data = (salt + s).codeUnits;
  int hash = 0xcbf29ce484222325;
  for (final b in data) {
    hash ^= b;
    hash = (hash * 0x00000100000001B3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

class AppSettings {
  String printerIp;
  int printerPort;
  int paperCols;
  String pinHash;
  AppSettings({
    required this.printerIp,
    required this.printerPort,
    required this.paperCols,
    required this.pinHash,
  });
  factory AppSettings.defaults() => AppSettings(
    printerIp: PRINTER_IP,
    printerPort: PRINTER_PORT,
    paperCols: 32,
    pinHash: _fnv64(_ADMIN_PIN),
  );
  Map<String, dynamic> toJson() => {
    'printerIp': printerIp,
    'printerPort': printerPort,
    'paperCols': paperCols,
    'pinHash': pinHash,
  };
  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
    printerIp: j['printerIp'] ?? '192.168.1.1',
    printerPort: j['printerPort'] ?? 9100,
    paperCols: j['paperCols'] ?? 32,
    pinHash: j['pinHash'] ?? _fnv64(_ADMIN_PIN),
  );
}

extension _Prefs on SharedPreferences {
  String? getStringOrNull(String k) => containsKey(k) ? getString(k) : null;
}

/* =======================
    MODELLER & STATE
    ======================= */
class Product {
  String name;
  final List<OptionGroup> groups;
  final int? prepMinutes; 

  Product({required this.name, List<OptionGroup>? groups, this.prepMinutes})
      : groups = groups ?? [];

  double priceForSelection(Map<String, List<OptionItem>> picked) {
    double total = 0;
    for (final g in groups) {
      final list = picked[g.id] ?? const [];
      for (final it in list) total += it.price;
    }
    return total;
  }
}

class OptionGroup {
  final String id;
  String title;
  bool multiple;
  int minSelect;
  int maxSelect;
  final List<OptionItem> items;
  OptionGroup({
    required this.id,
    required this.title,
    required this.multiple,
    required this.minSelect,
    required this.maxSelect,
    List<OptionItem>? items,
  }) : items = items ?? [];
}

class OptionItem {
  final String id;
  String label;
  double price;
  OptionItem({required this.id, required this.label, required this.price});
}

class CartLine {
  final Product product;
  final Map<String, List<OptionItem>> picked;
  int qty;
  CartLine({required this.product, required this.picked, this.qty = 1});
  double get unitTotal => product.priceForSelection(picked);
  double get total => unitTotal * qty;
}

class SavedOrder {
  final String id;
  final DateTime createdAt;
  final DateTime readyAt;
  final List<CartLine> lines;
  final String customer;
  
  SavedOrder({
    required this.id,
    required this.createdAt,
    required this.readyAt,
    required this.lines,
    required this.customer,
  });
  double get total => lines.fold(0.0, (s, l) => s + l.total);
}

class AppState extends ChangeNotifier {
  final List<Product> products = [];
  final List<CartLine> cart = [];
  final List<SavedOrder> orders = [];
  int prepMinutes = 5;

  AppSettings settings = AppSettings.defaults();

  Future<void> loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    prepMinutes = sp.getInt('prepMinutes') ?? 5;

    final s = sp.getStringOrNull('appSettings');
    settings = s == null
      ? AppSettings.defaults()
      : AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    
    await _loadProductsFromPrefs(sp);
    await _loadOrdersFromPrefs(sp);

    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('appSettings', jsonEncode(settings.toJson()));
  }

  Future<void> setPrinterIp(String ip) async { settings.printerIp = ip.trim(); await _saveSettings(); notifyListeners(); }
  Future<void> setPrinterPort(int p) async { settings.printerPort = p; await _saveSettings(); notifyListeners(); }
  Future<void> setPaperCols(int c) async { settings.paperCols = c.clamp(20, 64).toInt(); await _saveSettings(); notifyListeners(); }
  Future<void> setAdminPin(String newPin) async {
    settings.pinHash = _fnv64(newPin);
    await _saveSettings();
    notifyListeners();
  }

  Future<bool> testPrinterConnectivity({String? ip, int? port}) async {
    final host = (ip ?? settings.printerIp);
    final prt  = (port ?? settings.printerPort);
    try {
      final s = await Socket.connect(host, prt, timeout: const Duration(seconds: 2));
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadProductsFromPrefs(SharedPreferences sp) async {
    final s = sp.getString('productsJson');
    if (s == null) return;
    final list = (jsonDecode(s) as List)
        .map((e) => ProductJson.fromJson(e as Map<String, dynamic>))
        .toList();
    products..clear()..addAll(list);
  }

  Future<void> _saveProductsToPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final data = products.map((p) => p.toJson()).toList();
    await sp.setString('productsJson', jsonEncode(data));
  }

  Future<void> _loadOrdersFromPrefs(SharedPreferences sp) async {
    final s = sp.getString('ordersJson');
    if (s == null) return;
    final list = (jsonDecode(s) as List)
        .map((e) => SavedOrderJson.fromJson(e as Map<String, dynamic>))
        .toList();
    orders..clear()..addAll(list);
  }

  Future<void> _saveOrdersToPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final data = orders.map((o) => o.toJson()).toList();
    await sp.setString('ordersJson', jsonEncode(data));
  }

  Future<void> setPrepMinutes(int m) async {
    prepMinutes = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('prepMinutes', m);
    notifyListeners();
  }

  void addProduct(Product p) { products.add(p); _saveProductsToPrefs(); notifyListeners(); }
  void replaceProductAt(int i, Product p) { products[i] = p; _saveProductsToPrefs(); notifyListeners(); }

  void addLineToCart(Product p, Map<String, List<OptionItem>> picked, {int qty = 1}) {
    final deep = { for (final e in picked.entries) e.key: List<OptionItem>.from(e.value) };
    cart.add(CartLine(product: p, picked: deep, qty: qty.clamp(1, 999).toInt()));
    notifyListeners();
  }
  void updateCartQtyAt(int i, int newQty) {
    if (i<0 || i>=cart.length) return;
    cart[i].qty = newQty.clamp(1, 999).toInt();
    notifyListeners();
  }

  void removeCartLineAt(int i) { if (i>=0 && i<cart.length) { cart.removeAt(i); notifyListeners(); } }
  void clearCart() { cart.clear(); notifyListeners(); }

  void updateCartLineAt(int i, Map<String, List<OptionItem>> picked) {
    if (i < 0 || i >= cart.length) return;
    final deep = {
      for (final e in picked.entries) e.key: List<OptionItem>.from(e.value)
    };
    final p = cart[i].product;
    cart[i] = CartLine(product: p, picked: deep, qty: cart[i].qty);
    notifyListeners();
  }

  void finalizeCartToOrder({required String customer}) {
    if (cart.isEmpty) return;
    final deepLines = cart.map((l) => CartLine(
      product: l.product,
      picked: { for (final e in l.picked.entries) e.key: List<OptionItem>.from(e.value) },
      qty: l.qty,
    )).toList();

    int maxPrep = prepMinutes;
    for (final line in cart) {
      if (line.product.prepMinutes != null && line.product.prepMinutes! > maxPrep) {
        maxPrep = line.product.prepMinutes!;
      }
    }

    final now   = DateTime.now();
    final ready = now.add(Duration(minutes: maxPrep));

    orders.add(SavedOrder(
      id: now.millisecondsSinceEpoch.toString(),
      createdAt: now,
      readyAt: ready,
      lines: deepLines,
      customer: customer,
    ));
    cart.clear();
    _saveOrdersToPrefs();
    notifyListeners();
  }

  void clearOrders() { orders.clear(); _saveOrdersToPrefs(); notifyListeners(); }
}

/* InheritedNotifier: global state erişimi */
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required AppState notifier, required Widget child, Key? key})
      : super(key: key, notifier: notifier, child: child);
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope bulunamadı.');
    return scope!.notifier!;
  }
}

/* =======================
    HOME (4 sekme)
    ======================= */
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final totalCart = app.cart.fold(0.0, (s, l) => s + l.total);
    final cartBadge = app.cart.length;

    final pages = [
      const ProductsPage(),
      CreateProductPage(onGoToTab: (i) => setState(() => index = i)),
      const CartPage(),
      const OrdersPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('BISCORNUE'),
        actions: [
          IconButton(
            tooltip: 'Paramètres',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Produits'),
          const NavigationDestination(icon: Icon(Icons.add_box_outlined), label: 'Créer'),
          NavigationDestination(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_bag_outlined),
                if (cartBadge > 0)
                  Positioned(
                    right: -6, top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                      child: Text('$cartBadge', style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            label: 'Panier (${_money(totalCart)})',
          ),
          const NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Commandes'),
        ],
        onDestinationSelected: (i) async {
          if (i == 1) { final ok = await _askPin(context); if (!ok) return; }
          if (i == 2) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
          setState(() => index = i);
        },
      ),
    );
  }
}

/* =======================
    PAGE 1 : PRODUITS
    ======================= */
class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final products = app.products;

    if (products.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.info_outline, size: 48),
          SizedBox(height: 8),
          Text('Aucun produit. Allez à "Créer" pour en ajouter.'),
        ]),
      );
    }

    final width = MediaQuery.of(context).size.width;
    int cross = 2;
    if (width > 600) cross = 3;
    if (width > 900) cross = 4;
    final aspect = width > 900 ? 0.9 : (width > 600 ? 0.95 : 0.88);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: aspect,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ProductCard(product: products[i]),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    Future<void> openWizard() async {
      final added = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => OrderWizard(product: product)),
      );
      if (added == true && context.mounted) {
        _snack(context, 'Ajouté au panier.');
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: openWizard,
      child: Ink(
        decoration: BoxDecoration(
          color: color.surfaceVariant, borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 56, width: 56,
                    decoration: BoxDecoration(
                      color: color.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.fastfood_rounded, color: color.primary, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(product.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${product.groups.length} groupe(s)'),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: choisirButton(() => openWizard(), context),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final ok = await _askPin(context);
                  if (!ok) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateProductPage(
                        onGoToTab: (_) {},
                        editIndex: AppScope.of(context).products.indexOf(product),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* =======================
    PAGE 2 : CRÉER + DÜZENLE
    ======================= */
class CreateProductPage extends StatefulWidget {
  final void Function(int) onGoToTab;
  final int? editIndex;
  const CreateProductPage({super.key, required this.onGoToTab, this.editIndex});
  @override
  State<CreateProductPage> createState() => _CreateProductPageState();
}

class _CreateProductPageState extends State<CreateProductPage> {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController productPrepCtrl = TextEditingController();
  final List<OptionGroup> editingGroups = [];
  int? editingIndex;
  final TextEditingController delayCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    editingIndex = widget.editIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editingIndex != null) _loadForEdit(editingIndex!);
      final app = AppScope.of(context);
      delayCtrl.text = app.prepMinutes.toString();
    });
  }

  void _loadForEdit(int idx) {
    final app = AppScope.of(context);
    if (idx < 0 || idx >= app.products.length) return;
    final p = app.products[idx];
    nameCtrl.text = p.name;
    productPrepCtrl.text = p.prepMinutes?.toString() ?? '';
    editingGroups..clear()..addAll(p.groups.map(_copyGroup));
    setState(() => editingIndex = idx);
  }
  
  Future<bool> _confirmDiscard(BuildContext context) async {
    final hasChanges = nameCtrl.text.trim().isNotEmpty || editingGroups.isNotEmpty;
    if (!hasChanges) return true;
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler les modifications ?'),
        content: const Text('Les changements non enregistrés seront perdus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui')),
        ],
      ),
    ) ?? false;
  }

  OptionGroup _copyGroup(OptionGroup g) => OptionGroup(
    id: g.id, title: g.title, multiple: g.multiple, minSelect: g.minSelect, maxSelect: g.maxSelect,
    items: g.items.map((e) => OptionItem(id: e.id, label: e.label, price: e.price)).toList(),
  );

  void addGroup() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    editingGroups.add(OptionGroup(id: id, title: 'Nouveau groupe', multiple: false, minSelect: 1, maxSelect: 1));
    setState(() {});
  }

  void saveProduct() {
    final app = AppScope.of(context);
    if (nameCtrl.text.trim().isEmpty) { _snack(context, 'Le nom du produit est requis.'); return; }
    for (final g in editingGroups) {
      if (g.title.trim().isEmpty) { _snack(context, 'Le titre du groupe est manquant.'); return; }
      if (g.items.isEmpty) { _snack(context, 'Ajoutez au moins une option dans "${g.title}".'); return; }
      if (g.minSelect < 0 || g.maxSelect < 1 || g.minSelect > g.maxSelect) {
        _snack(context, 'Règles min/max invalides dans "${g.title}".'); return;
      }
      if (!g.multiple && (g.minSelect != 1 || g.maxSelect != 1)) {
        _snack(context, 'Un choix unique doit avoir min=1 et max=1 (${g.title}).'); return;
      }
    }
    
    final int? productPrep = int.tryParse(productPrepCtrl.text.trim());

    final p = Product(
      name: nameCtrl.text.trim(), 
      groups: List.of(editingGroups),
      prepMinutes: productPrep,
    );

    if (editingIndex == null) { app.addProduct(p); _snack(context, 'Produit créé.'); }
    else { app.replaceProductAt(editingIndex!, p); _snack(context, 'Produit mis à jour.'); }
    
    nameCtrl.clear();
    productPrepCtrl.clear();
    editingGroups.clear(); 
    setState(() => editingIndex = null);

    if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () async {
            if (await _confirmDiscard(context)) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
            }
          }, tooltip: 'Retour'),
          const SizedBox(width: 8),
          Text(editingIndex == null ? 'Créer un produit' : 'Modifier un produit',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              if (await _confirmDiscard(context)) {
                nameCtrl.clear();
                productPrepCtrl.clear();
                editingGroups.clear(); 
                setState(() => editingIndex = null);
                if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
              }
            },
            icon: const Icon(Icons.close), label: const Text('Annuler'),
          ),
        ]),
        const SizedBox(height: 12),

        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: delayCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Délai de préparation global (minutes)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final m = int.tryParse(delayCtrl.text.trim());
                    if (m == null || m < 0) {
                      _snack(context, 'Valeur invalide.');
                      return;
                    }
                    app.setPrepMinutes(m);
                    _snack(context, 'Délai enregistré : $m min.');
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        ),

        if (app.products.isNotEmpty) ...[
          const Text('Produits existants', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: app.products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = app.products[i];
              return ListTile(
                leading: const Icon(Icons.fastfood_rounded),
                title: Text(p.name),
                subtitle: Text('${p.groups.length} groupe(s)'),
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit), label: const Text('Modifier'),
                  onPressed: () => _loadForEdit(i),
                ),
              );
            },
          ),
          const SizedBox(height: 16), const Divider(), const SizedBox(height: 12),
        ],
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom du produit',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextField(
                controller: productPrepCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Délai (min)',
                  hintText: 'Optionnel',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(onPressed: addGroup, icon: const Icon(Icons.add), label: const Text('Ajouter un groupe')),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: saveProduct, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
        ]),
        const SizedBox(height: 12),

        for (int i = 0; i < editingGroups.length; i++)
          _GroupEditor(
            key: ValueKey(editingGroups[i].id),
            group: editingGroups[i],
            onDelete: () => setState(() => editingGroups.removeAt(i)),
            onChanged: () => setState(() {}),
          ),

        if (editingGroups.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text('Aucun groupe. Ajoutez "Pain", "Viande", "Suppléments", "Sauces", etc.'),
          ),
      ],
    );
  }
}

class _GroupEditor extends StatefulWidget {
  final OptionGroup group;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _GroupEditor({super.key, required this.group, required this.onDelete, required this.onChanged});
  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController minCtrl = TextEditingController();
  final TextEditingController maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    titleCtrl.text = widget.group.title;
    minCtrl.text = widget.group.minSelect.toString();
    maxCtrl.text = widget.group.maxSelect.toString();
  }

  int get _mode => widget.group.multiple ? 1 : 0;
  set _mode(int v) {
    widget.group.multiple = (v == 1);
    if (v == 0) {
      minCtrl.text = '1';
      maxCtrl.text = '1';
    }
    apply();
    setState(() {});
  }

  void apply() {
    widget.group.title = titleCtrl.text.trim();
    widget.group.minSelect = int.tryParse(minCtrl.text) ?? 0;
    widget.group.maxSelect = int.tryParse(maxCtrl.text) ?? 1;
    widget.onChanged();
  }

  void addOption() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    widget.group.items.add(OptionItem(id: id, label: 'Nouvelle option', price: 0));
    widget.onChanged(); setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Titre du groupe', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _mode,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Choix unique')),
                DropdownMenuItem(value: 1, child: Text('Choix multiple')),
              ],
              onChanged: (v) { if (v != null) _mode = v; },
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: minCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sélection min', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: maxCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sélection max', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: addOption, icon: const Icon(Icons.add), label: const Text('Ajouter une option')),
          ]),
          const SizedBox(height: 8),
          for (int i = 0; i < g.items.length; i++)
            _OptionEditor(
              key: ValueKey(g.items[i].id),
              item: g.items[i],
              onDelete: () { g.items.removeAt(i); widget.onChanged(); setState(() {}); },
              onChanged: () { widget.onChanged(); setState(() {}); },
            ),
        ]),
      ),
    );
  }
}

class _OptionEditor extends StatefulWidget {
  final OptionItem item;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _OptionEditor({super.key, required this.item, required this.onDelete, required this.onChanged});
  @override
  State<_OptionEditor> createState() => _OptionEditorState();
}

class _OptionEditorState extends State<_OptionEditor> {
  final TextEditingController labelCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    labelCtrl.text = widget.item.label;
    priceCtrl.text = widget.item.price.toStringAsFixed(2);
  }
  void apply() {
    widget.item.label = labelCtrl.text.trim();
    widget.item.price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    widget.onChanged();
  }
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      title: Row(children: [
        Expanded(
          child: TextField(
            controller: labelCtrl,
            decoration: const InputDecoration(labelText: 'Nom de l’option', border: OutlineInputBorder()),
            onChanged: (_) => apply(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Prix (€)', border: OutlineInputBorder()),
            onChanged: (_) => apply(),
          ),
        ),
        IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
      ]),
    );
  }
}

/* =======================
    WIZARD
    ======================= */
class OrderWizard extends StatefulWidget {
  final Product product;
  final Map<String, List<OptionItem>>? initialPicked;
  final bool editMode;

  const OrderWizard({
    super.key,
    required this.product,
    this.initialPicked,
    this.editMode = false,
  });

  @override
  State<OrderWizard> createState() => _OrderWizardState();
}

class _OrderWizardState extends State<OrderWizard> {
  int step = 0;
  final Map<String, List<OptionItem>> picked = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialPicked != null) {
      for (final e in widget.initialPicked!.entries) {
        picked[e.key] = List<OptionItem>.from(e.value);
      }
    }
  }

  List<OptionGroup> _groupsForVisibility(List<OptionGroup> base) {
    if (widget.product.name != 'Menu Enfant') return base;

    final cheeseSecildiMi =
        (picked['choix_enfant'] ?? const <OptionItem>[]).any((it) => it.id == 'cheese_menu');

    return base.where((g) {
      if (g.id == 'crudites_enfant') return cheeseSecildiMi;
      return true;
    }).toList();
  }

  void _toggleSingle(OptionGroup g, OptionItem it) { picked[g.id] = [it]; setState(() {}); }
  void _toggleMulti(OptionGroup g, OptionItem it) {
    final list = List<OptionItem>.from(picked[g.id] ?? []);
    final isCrud = g.id == 'crudites';
    final isSansCrud = it.id == 'sans_crudites';

    if (isCrud && isSansCrud) {
      picked[g.id] = [it];
      setState(() {});
      return;
    }

    final exists = list.any((e) => e.id == it.id);
    if (exists) {
      list.removeWhere((e) => e.id == it.id);
    } else {
      if (isCrud) {
        list.removeWhere((e) => e.id == 'sans_crudites');
      }
      if (list.length >= g.maxSelect) return;
      list.add(it);
    }

    picked[g.id] = list;
    setState(() {});
  }
  
  bool _validGroup(OptionGroup g) {
    final n = (picked[g.id] ?? const []).length;
    return n >= g.minSelect && n <= g.maxSelect;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupsForVisibility(widget.product.groups);
    final isSummary = step >= groups.length;
    final total = widget.product.priceForSelection(picked);

    return Scaffold(
      appBar: AppBar(
        title: Text(isSummary ? 'Récapitulatif' : widget.product.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (isSummary) {
              setState(() => step = groups.isEmpty ? 0 : groups.length - 1);
            } else if (step > 0) {
              setState(() => step--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 96.0),
              child: isSummary
                  ? _Summary(product: widget.product, picked: picked, total: total)
                  : _GroupStep(
                      group: groups[step],
                      picked: picked,
                      toggleSingle: _toggleSingle,
                      toggleMulti: _toggleMulti,
                    ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: FloatingActionButton.large(
              heroTag: 'prevFab',
              onPressed: step == 0
                  ? null
                  : () => setState(() => step--),
              child: const Icon(Icons.arrow_back),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: FloatingActionButton.large(
              heroTag: 'nextFab',
              onPressed: () {
                if (isSummary) {
                  if (widget.editMode) {
                    final result = {
                      for (final e in picked.entries) e.key: List<OptionItem>.from(e.value)
                    };
                    Navigator.pop(context, result);
                  } else {
                    final app = AppScope.of(context);
                    app.addLineToCart(widget.product, picked);
                    if (!mounted) return;
                    Navigator.pop(context, true);
                  }
                  return;
                }
                final g = groups[step];
                if (!_validGroup(g)) {
                  _showWarn(context, 'Sélection invalide pour "${g.title}".');
                  return;
                }
                setState(() => step++);
              },
              child: Icon(isSummary ? (widget.editMode ? Icons.check : Icons.add_shopping_cart) : Icons.arrow_forward),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupStep extends StatelessWidget {
  final OptionGroup group;
  final Map<String, List<OptionItem>> picked;
  final void Function(OptionGroup, OptionItem) toggleSingle;
  final void Function(OptionGroup, OptionItem) toggleMulti;

  const _GroupStep({
    required this.group,
    required this.picked,
    required this.toggleSingle,
    required this.toggleMulti,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    final desired = 160.0;
    int cross = (size.width / desired).floor().clamp(2, 5);

    final selectedList = picked[group.id] ?? const <OptionItem>[];
    final sansCrudOn = group.id == 'crudites'
        && selectedList.any((e) => e.id == 'sans_crudites');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            group.title +
                (group.multiple
                    ? '  (min ${group.minSelect}, max ${group.maxSelect})'
                    : ''),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: group.items.length,
            itemBuilder: (_, i) {
              final it = group.items[i];
              final isSelected = selectedList.any((e) => e.id == it.id);
              final disabled = sansCrudOn && it.id != 'sans_crudites';

              void onTap() {
                if (group.multiple) {
                  toggleMulti(group, it);
                } else {
                  toggleSingle(group, it);
                }
              }

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: disabled ? null : onTap,
                child: Opacity(
                  opacity: disabled ? 0.35 : 1.0,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.primaryContainer
                          : color.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? color.primary : color.outlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 8,
                          right: 8,
                          child: group.multiple
                              ? Icon(
                                  isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 22,
                                  color: isSelected
                                      ? color.primary
                                      : color.onSurfaceVariant,
                                )
                              : Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 22,
                                  color: isSelected
                                      ? color.primary
                                      : color.onSurfaceVariant,
                                ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  it.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (it.price != 0)
                                  Text(
                                    '+ ${_money(it.price)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: color.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final Product product;
  final Map<String, List<OptionItem>> picked;
  final double total;
  const _Summary({required this.product, required this.picked, required this.total});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Récapitulatif — ${product.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final g in product.groups)
          if ((picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
            Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final it in (picked[g.id] ?? const <OptionItem>[]))
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('• ${it.label}'),
                Text(_money(it.price)),
              ]),
            const SizedBox(height: 8),
            const Divider(),
          ],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('SOUS-TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(_money(total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

/* =======================
    PAGE 3 : PANIER
    ======================= */
class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lines = app.cart;
    final total = lines.fold(0.0, (s, l) => s + l.total);

    if (lines.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.shopping_bag_outlined, size: 48),
          SizedBox(height: 8),
          Text('Panier vide. Ajoutez des produits.'),
        ]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Panier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Vider le panier ?'),
                    content: const Text('Toutes les lignes seront supprimées.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Vider')),
                    ],
                  ),
                );
                if (ok == true) app.clearCart();
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Vider'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = lines[i];
              return ListTile(
                leading: const Icon(Icons.fastfood),
                title: Text('${l.product.name} • ${_money(l.total)}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in l.product.groups)
                      if ((l.picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
                        Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        for (final it in (l.picked[g.id] ?? const <OptionItem>[]))
                          Text('• ${it.label}${it.price == 0 ? '' : ' (+${_money(it.price)})'}'),
                      ],
                  ],
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 0,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => app.updateCartQtyAt(i, l.qty - 1),
                      ),
                      Text('${l.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => app.updateCartQtyAt(i, l.qty + 1),
                      ),
                    ]),
                    IconButton(
                      tooltip: 'Modifier',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final result = await Navigator.push<Map<String, List<OptionItem>>>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderWizard(
                              product: l.product,
                              initialPicked: l.picked,
                              editMode: true,
                            ),
                          ),
                        );
                        if (result != null) {
                          app.updateCartLineAt(i, result);
                          if (context.mounted) {
                            _snack(context, 'Ligne mise à jour.');
                          }
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => app.removeCartLineAt(i),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_money(total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: FilledButton.icon(
            onPressed: () async {
              final name = await _askCustomerName(context);
              if (name == null) return;
              final app = AppScope.of(context);
              final ready = DateTime.now().add(Duration(minutes: app.prepMinutes));
              app.finalizeCartToOrder(customer: name);
              if (context.mounted) {
                _snack(context,
                  'Commande validée pour "$name". Prêt à ${_two(ready.hour)}:${_two(ready.minute)}.');
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Valider la commande'),
          ),
        ),
      ],
    );
  }
}

/* =======================
    PAGE 4 : COMMANDES + YAZDIRMA
    ======================= */
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final orders = app.orders.reversed.toList();

    if (orders.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.receipt_long, size: 48),
          SizedBox(height: 8),
          Text('Aucune commande.'),
        ]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Commandes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final pinOk = await _askPin(context); if (!pinOk) return;
                final choice = await showDialog<int>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Fin de journée ?'),
                    content: const Text('Voulez-vous imprimer un rapport avant de supprimer toutes les commandes ?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Annuler')),
                      FilledButton.tonal(onPressed: () => Navigator.pop(context, 1), child: const Text('Imprimer Rapport')),
                      FilledButton(onPressed: () => Navigator.pop(context, 2), child: const Text('Supprimer Tout')),
                    ],
                  ),
                );
                if (choice == 1) {
                  try {
                    await printDailyReport(context);
                    _snack(context, 'Rapport envoyé à l\'imprimante.');
                  } catch (e) {
                    _snack(context, 'Erreur d\'impression: $e');
                  }
                } else if (choice == 2) {
                  app.clearOrders();
                }
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Journée terminée'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final o = orders[i];
              final who = o.customer.isEmpty ? '' : ' — ${o.customer}';
              return ListTile(
                leading: const Icon(Icons.receipt),
                title: Text('Commande$who • ${o.lines.length} article(s) • ${_money(o.total)}'),
                subtitle: Text('Prêt à ${_two(o.readyAt.hour)}:${_two(o.readyAt.minute)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () async {
                    try {
                      await printOrderAndroid(o, context);
                      _snack(context, 'Ticket envoyé à l\'imprimante.');
                    } catch (e) {
                      _snack(context, 'Erreur d\'impression : $e. L\'IP/port et le réseau Wi-Fi sont-ils corrects ?');
                    }
                  },
                  tooltip: 'Imprimer',
                ),
                onTap: () {
                  showDialog(context: context, builder: (_) {
                    return AlertDialog(
                      title: const Text('Détails de la commande'),
                      content: SizedBox(
                        width: 360,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            if (o.customer.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('Client: ${o.customer}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('Prêt à: ${_two(o.readyAt.hour)}:${_two(o.readyAt.minute)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            for (int idx = 0; idx < o.lines.length; idx++) ...[
                              Text('Article ${idx+1}: ${o.lines[idx].product.name} (x${o.lines[idx].qty})',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              for (final g in o.lines[idx].product.groups)
                                if ((o.lines[idx].picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
                                  Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  for (final it in (o.lines[idx].picked[g.id] ?? const <OptionItem>[]))
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('• ${it.label}'),
                                        Text(_money(it.price)),
                                      ],
                                    ),
                                ],
                              const Divider(),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(_money(o.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            try {
                              await printOrderAndroid(o, context);
                              if (context.mounted) {
                                Navigator.pop(context);
                                _snack(context, 'Ticket envoyé à l\'imprimante.');
                              }
                            } catch (e) {
                               _snack(context, 'Erreur d\'impression : $e');
                            }
                          },
                          child: const Text('Imprimer'),
                        ),
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
                      ],
                    );
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/* =======================
    DİYALOGLAR & UTIL
    ======================= */
Future<bool> _askPin(BuildContext context) async {
  final app = AppScope.of(context);
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Code PIN requis'),
      content: TextField(
        controller: ctrl, keyboardType: TextInputType.number, obscureText: true, maxLength: 8,
        decoration: const InputDecoration(labelText: 'Entrez le code', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
      ],
    ),
  );
  if (ok == true) {
    final valid = _fnv64(ctrl.text.trim()) == app.settings.pinHash;
    if (!valid && context.mounted) { _snack(context, 'Code incorrect.'); }
    return valid;
  }
  return false;
}

Future<String?> _askCustomerName(BuildContext context) async {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('Nom du client'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl, autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Écrire le nom',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) {
                  if (ctrl.text.trim().isEmpty) {
                    setState(() => error = 'Le nom est requis.');
                  } else {
                    Navigator.pop(ctx, ctrl.text.trim());
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) { setState(() => error = 'Le nom est requis.'); return; }
                Navigator.pop(ctx, name);
              },
              child: const Text('Valider'),
            ),
          ],
        );
      });
    },
  );
}

void _snack(BuildContext context, String msg, {int ms = 1500}) {
  if (!context.mounted) return;
  final bottomInset = MediaQuery.of(context).padding.bottom;
  final bottomBar = kBottomNavigationBarHeight;
  final bottomMargin = 12 + bottomInset + bottomBar;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(milliseconds: ms),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottomMargin),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
}

void _showWarn(BuildContext context, String msg) {
  _snack(context, msg);
}

Widget choisirButton(VoidCallback onTap, BuildContext context) {
  final color = Theme.of(context).colorScheme;
  return Material(
    color: color.primary,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: const SizedBox(
        height: 48, width: 48,
        child: Icon(Icons.shopping_cart_outlined, color: Colors.white),
      ),
    ),
  );
}

// ==================================================
// YAZDIRMA YARDIMCILARI
// ==================================================

String _two(int n) => n.toString().padLeft(2, '0');
String _money(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

String _rightLine(String left, String right, {required int width}) {
  left  = left.replaceAll('\n', ' ');
  right = right.replaceAll('\n', ' ');
  if (right.length >= width) {
    return right.substring(0, width);
  }
  final space = width - right.length;
  if (left.length >= space) {
    left = left.substring(0, (space - 1).clamp(0, space));
  }
  return left + ' ' * (space - left.length) + right;
}

List<String> _wrapLeftRight(String left, String right, {required int width}) {
  final lines = <String>[];
  if (left.length + 1 + right.length <= width) {
    lines.add(_rightLine(left, right, width: width));
    return lines;
  }
  int spaceForLeft = width - right.length - 1;
  if (spaceForLeft < 1) spaceForLeft = width;
  if (left.length > spaceForLeft) {
    lines.add(_rightLine(left.substring(0, spaceForLeft), right, width: width));
    left = left.substring(spaceForLeft).trimLeft();
  } else {
    lines.add(_rightLine(left, right, width: width));
    return lines;
  }
  while (left.isNotEmpty) {
    final take = left.length > width ? width : left.length;
    lines.add(left.substring(0, take));
    left = left.substring(take);
  }
  return lines;
}

void _cmd(Socket s, List<int> bytes) => s.add(bytes);
void _boldOn(Socket s)  => _cmd(s, [27, 69, 1]);
void _boldOff(Socket s) => _cmd(s, [27, 69, 0]);
void _size(Socket s, int n) => _cmd(s, [29, 33, n]);
void _alignLeft(Socket s)   => _cmd(s, [27, 97, 0]);
void _alignCenter(Socket s) => _cmd(s, [27, 97, 1]);
void _alignRight(Socket s)  => _cmd(s, [27, 97, 2]);

void _writeCp1252(Socket socket, String text) {
  const map = {
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87,
    0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
    0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94,
    0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99,
    0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
    0x00E0: 0xE0, 0x00E1: 0xE1, 0x00E2: 0xE2, 0x00E7: 0xE7, 0x00E8: 0xE8, 0x00E9: 0xE9,
    0x00EA: 0xEA, 0x00EB: 0xEB, 0x00EE: 0xEE, 0x00EF: 0xEF, 0x00F4: 0xF4, 0x00F9: 0xF9,
    0x00FB: 0xFB, 0x00FC: 0xFC, 0x00C0: 0xC0, 0x00C2: 0xC2, 0x00C7: 0xC7, 0x00C8: 0xC8,
    0x00C9: 0xC9, 0x00CA: 0xCA, 0x00CB: 0xCB, 0x00CE: 0xCE, 0x00CF: 0xCF, 0x00D4: 0xD4,
    0x00D9: 0xD9, 0x00DB: 0xDB, 0x00DC: 0xDC,
  };

  final out = <int>[];
  for (final r in text.runes) {
    if (r <= 0x7F) { out.add(r); continue; }
    final mapped = map[r];
    if (mapped != null) { out.add(mapped); continue; }
    out.add(0x3F);
  }
  socket.add(out);
}

Future<void> printOrderAndroid(SavedOrder o, BuildContext context) async {
  final app = AppScope.of(context);
  final cols = app.settings.paperCols;

  Socket? socket;
  try {
    socket = await Socket.connect(app.settings.printerIp, app.settings.printerPort, timeout: const Duration(seconds: 5));

    _cmd(socket, [27, 64]);
    _cmd(socket, [27, 116, 16]);

    _alignCenter(socket);
    _size(socket, 17); _boldOn(socket);
    _writeCp1252(socket, '*** BISCORNUE ***\n');
    _boldOff(socket); _size(socket, 0);

    if (o.customer.isNotEmpty) {
      _size(socket, 1); _boldOn(socket);
      _writeCp1252(socket, 'Client: ${o.customer}\n');
      _boldOff(socket); _size(socket, 0);
    }

    _boldOn(socket); _size(socket, 1);
    _writeCp1252(socket, 'Prêt à: ${_two(o.readyAt.hour)}:${_two(o.readyAt.minute)}\n');
    _size(socket, 0); _boldOff(socket);

    _alignLeft(socket);
    _writeCp1252(socket, '-' * cols + '\n');

    for (int i = 0; i < o.lines.length; i++) {
      final l = o.lines[i];
      final left = 'Article ${i + 1}: ${l.product.name}${l.qty > 1 ? ' x${l.qty}' : ''}';
      final right = _money(l.total);
      for (final ln in _wrapLeftRight(left, right, width: cols)) {
        _writeCp1252(socket, ln + '\n');
      }
      for (final g in l.product.groups) {
        final sel = l.picked[g.id] ?? const <OptionItem>[];
        if (sel.isNotEmpty) {
          _writeCp1252(socket, '  ${g.title}:\n');
          for (final it in sel) { _writeCp1252(socket, '    * ${it.label}\n'); }
        }
      }
      if (i != o.lines.length - 1) {
        _writeCp1252(socket, '-' * cols + '\n');
      }
    }

    _writeCp1252(socket, '-' * cols + '\n');
    _alignRight(socket); _boldOn(socket); _size(socket, 1);
    for (final ln in _wrapLeftRight('TOTAL', _money(o.total), width: cols)) {
      _writeCp1252(socket, ln + '\n');
    }
    _size(socket, 0); _boldOff(socket);

    _cmd(socket, [10, 10, 29, 86, 66, 0]);
    await socket.flush();
  } finally {
    await socket?.close();
  }
}

Future<void> printDailyReport(BuildContext context) async {
  final app = AppScope.of(context);
  final orders = app.orders;
  final total = orders.fold<double>(0, (s,o)=> s + o.total);
  final count = orders.length;
  final cols = app.settings.paperCols;

  Socket? socket;
  try {
    socket = await Socket.connect(app.settings.printerIp, app.settings.printerPort, timeout: const Duration(seconds: 5));
    _cmd(socket, [27,64]); _cmd(socket, [27,116,16]); _alignCenter(socket); _boldOn(socket); _size(socket, 1);
    _writeCp1252(socket, '*** RAPPORT JOURNALIER ***\n'); _boldOff(socket); _size(socket,0);
    _alignLeft(socket); _writeCp1252(socket, '-' * cols + '\n');
    _writeCp1252(socket, 'Date: ${DateTime.now().toLocal().toString().substring(0, 16)}\n');
    _writeCp1252(socket, 'Commandes: $count\n');
    _writeCp1252(socket, 'Chiffre d\'affaires: ${_money(total)}\n');
    _writeCp1252(socket, '-' * cols + '\n');
    _cmd(socket, [10,10,29,86,66,0]);
    await socket.flush();
  } finally {
    await socket?.close();
  }
}


/* =======================
    JSON KALICILIK YARDIMCILARI
    ======================= */
extension ProductJson on Product {
  Map<String, dynamic> toJson() => {
    'name': name,
    'groups': groups.map((g) => g.toJson()).toList(),
    'prepMinutes': prepMinutes,
  };
  static Product fromJson(Map<String, dynamic> j) => Product(
    name: j['name'] ?? '',
    groups: (j['groups'] as List? ?? []).map((x) => OptionGroupJson.fromJson(x as Map<String, dynamic>)).toList(),
    prepMinutes: j['prepMinutes'],
  );
}

extension OptionGroupJson on OptionGroup {
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'multiple': multiple,
    'minSelect': minSelect,
    'maxSelect': maxSelect,
    'items': items.map((e) => e.toJson()).toList(),
  };
  static OptionGroup fromJson(Map<String, dynamic> j) => OptionGroup(
    id: j['id'],
    title: j['title'] ?? '',
    multiple: j['multiple'] ?? false,
    minSelect: j['minSelect'] ?? 0,
    maxSelect: j['maxSelect'] ?? 1,
    items: (j['items'] as List? ?? []).map((x) => OptionItemJson.fromJson(x as Map<String, dynamic>)).toList(),
  );
}

extension OptionItemJson on OptionItem {
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'price': price};
  static OptionItem fromJson(Map<String, dynamic> j) =>
      OptionItem(id: j['id'], label: j['label'] ?? '', price: (j['price'] ?? 0).toDouble());
}

extension CartLineJson on CartLine {
  Map<String, dynamic> toJson() => {
    'product': product.toJson(),
    'picked': picked.map((k, v) => MapEntry(k, v.map((e)=>e.toJson()).toList())),
    'qty': qty,
  };
  static CartLine fromJson(Map<String, dynamic> j) => CartLine(
    product: ProductJson.fromJson(j['product'] as Map<String, dynamic>),
    picked: (j['picked'] as Map<String, dynamic>? ?? {})
      .map((k, v) => MapEntry(k, (v as List).map((x)=>OptionItemJson.fromJson(x as Map<String, dynamic>)).toList())),
    qty: (j['qty'] ?? 1) as int,
  );
}

extension SavedOrderJson on SavedOrder {
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'readyAt': readyAt.millisecondsSinceEpoch,
    'customer': customer,
    'lines': lines.map((l) => l.toJson()).toList(),
  };
  static SavedOrder fromJson(Map<String, dynamic> j) => SavedOrder(
    id: j['id'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']),
    readyAt: DateTime.fromMillisecondsSinceEpoch(j['readyAt']),
    customer: j['customer'] ?? '',
    lines: (j['lines'] as List? ?? []).map((x)=>CartLineJson.fromJson(x as Map<String, dynamic>)).toList(),
  );
}

/* =======================
    AYARLAR SAYFASI
    ======================= */
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ipCtrl = TextEditingController();
  final portCtrl = TextEditingController();
  final colsCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  String? wifiName;
  bool testing = false;
  bool printing = false;

  @override
  void initState() {
    super.initState();
    NetworkInfo().getWifiName().then((name) {
      if (mounted) setState(() => wifiName = name?.replaceAll('"', ''));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    ipCtrl.text   = app.settings.printerIp;
    portCtrl.text = app.settings.printerPort.toString();
    colsCtrl.text = app.settings.paperCols.toString();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (wifiName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Connecté au Wi-Fi: $wifiName', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          TextField(
            controller: ipCtrl,
            decoration: const InputDecoration(labelText: 'IP imprimante', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: portCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: colsCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Colonnes (58mm=32, 80mm=48)', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              final ip = ipCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim());
              final cols = int.tryParse(colsCtrl.text.trim());
              if (ip.isEmpty || port == null || cols == null) { _snack(context, 'Valeurs invalides.'); return; }
              await app.setPrinterIp(ip);
              await app.setPrinterPort(port);
              await app.setPaperCols(cols);
              _snack(context, 'Enregistré.');
            },
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer'),
          ),
          const Divider(height: 24),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: testing ? null : () async {
                  setState(() => testing = true);
                  final ok = await app.testPrinterConnectivity();
                  if (!mounted) return;
                  setState(() => testing = false);
                  _snack(context, ok ? 'Connexion OK' : 'Connexion échouée');
                },
                icon: const Icon(Icons.wifi_tethering),
                label: Text(testing ? 'Test...' : 'Tester la connexion'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: printing ? null : () async {
                  setState(() => printing = true);
                  try {
                    final demo = SavedOrder(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      createdAt: DateTime.now(),
                      readyAt: DateTime.now(),
                      customer: 'TEST',
                      lines: [
                        CartLine(product: Product(name:'Test', groups:[]), picked:{}, qty:1),
                      ],
                    );
                    await printOrderAndroid(demo, context);
                    _snack(context, 'Ticket de test envoyé.');
                  } catch (e) {
                    _snack(context, 'Erreur: $e');
                  } finally {
                    if (mounted) setState(() => printing = false);
                  }
                },
                icon: const Icon(Icons.print),
                label: Text(printing ? 'Impression...' : 'Test d’impression'),
              ),
            ),
          ]),
          const Divider(height: 24),
          TextField(
            controller: pinCtrl, obscureText: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Nouveau PIN (4–8 chiffres)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              final p = pinCtrl.text.trim();
              if (p.length < 4 || p.length > 8) { _snack(context, 'Longueur du PIN invalide.'); return; }
              await app.setAdminPin(p);
              _snack(context, 'PIN mis à jour.');
              pinCtrl.clear();
            },
            icon: const Icon(Icons.lock_reset),
            label: const Text('Changer le PIN'),
          ),
        ],
      ),
    );
  }
}
