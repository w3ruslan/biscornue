import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard için

/* =======================
   AYAR: PIN
   ======================= */
const String _ADMIN_PIN = '6538';

/* =======================
   ENTRY
   ======================= */
void main() {
  final appState = AppState();
  runApp(AppScope(notifier: appState, child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commande Sur Place',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const Home(),
    );
  }
}

/* =======================
   MODELLER
   ======================= */

class OptionItem {
  final String id;
  String label;
  double price;
  OptionItem({required this.id, required this.label, required this.price});

  factory OptionItem.fromJson(Map<String, dynamic> j) =>
      OptionItem(id: j['id'], label: j['label'], price: (j['price'] ?? 0).toDouble());
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'price': price};
}

class OptionGroup {
  final String id;
  String title;
  bool multiple; // false=tek, true=çoklu
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

  factory OptionGroup.fromJson(Map<String, dynamic> j) => OptionGroup(
        id: j['id'],
        title: j['title'],
        multiple: j['multiple'] ?? false,
        minSelect: j['minSelect'] ?? 0,
        maxSelect: j['maxSelect'] ?? 1,
        items: (j['items'] as List<dynamic>? ?? [])
            .map((e) => OptionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'multiple': multiple,
        'minSelect': minSelect,
        'maxSelect': maxSelect,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class Product {
  final String id;
  String name;
  final List<OptionGroup> groups;
  Product({required this.id, required this.name, List<OptionGroup>? groups})
      : groups = groups ?? [];

  double priceFor(Map<String, List<OptionItem>> picked) {
    double total = 0;
    for (final g in groups) {
      for (final it in (picked[g.id] ?? const <OptionItem>[])) {
        total += it.price;
      }
    }
    return total;
  }

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'],
        name: j['name'],
        groups: (j['groups'] as List<dynamic>? ?? [])
            .map((e) => OptionGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'groups': groups.map((e) => e.toJson()).toList()};
}

class CartLine {
  final Product snapshot; // o anki ürünün kopyası (sonradan değişse etkilenmesin)
  final Map<String, List<OptionItem>> picked;
  CartLine({required this.snapshot, required this.picked});
  double get total => snapshot.priceFor(picked);
}

class SavedOrder {
  final String id;
  final DateTime createdAt;
  final String customer; // müşteri adı
  final List<CartLine> lines;
  SavedOrder({
    required this.id,
    required this.createdAt,
    required this.customer,
    required this.lines,
  });
  double get total => lines.fold(0.0, (s, l) => s + l.total);
}

/* =======================
   STATE
   ======================= */

class AppState extends ChangeNotifier {
  final List<Product> products = [];
  final List<CartLine> cart = [];
  final List<SavedOrder> orders = [];

  AppState() {
    _seed();
  }

  void _seed() {
    if (products.isNotEmpty) return;

    // ——— SANDWICH
    products.add(Product(
      id: 'p_sand',
      name: 'Sandwich',
      groups: [
        OptionGroup(
          id: 'pain',
          title: 'Pain',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'galette', label: 'Galette', price: 0),
            OptionItem(id: 'pita', label: 'Pain pita', price: 0),
          ],
        ),
        OptionGroup(
          id: 'viande',
          title: 'Viande',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'kebab', label: 'Kebab', price: 0),
            OptionItem(id: 'steak', label: 'Steak', price: 0),
            OptionItem(id: 'poulet', label: 'Poulet', price: 0),
            OptionItem(id: 'veg', label: 'Légumes grillés', price: 0),
          ],
        ),
        OptionGroup(
          id: 'supp',
          title: 'Suppléments (max 3)',
          multiple: true,
          minSelect: 0,
          maxSelect: 3,
          items: [
            OptionItem(id: 'oeuf', label: 'Œuf', price: 1.00),
            OptionItem(id: 'cheddar', label: 'Cheddar', price: 1.00),
            OptionItem(id: 'double_cheddar', label: 'Double cheddar', price: 1.80),
            OptionItem(id: 'bacon', label: 'Bacon', price: 1.50),
            OptionItem(id: 'cornichon', label: 'Cornichons', price: 0.50),
          ],
        ),
        OptionGroup(
          id: 'sauces',
          title: 'Sauces (max 2)',
          multiple: true,
          minSelect: 0,
          maxSelect: 2,
          items: [
            OptionItem(id: 'algerienne', label: 'Algérienne', price: 0),
            OptionItem(id: 'blanche', label: 'Blanche', price: 0),
            OptionItem(id: 'ketchup', label: 'Ketchup', price: 0),
            OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0),
            OptionItem(id: 'bbq', label: 'Barbecue', price: 0),
          ],
        ),
        OptionGroup(
          id: 'accompagnement',
          title: 'Accompagnement',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'frites', label: 'Avec frites', price: 2.50),
            OptionItem(id: 'sans_frites', label: 'Sans frites', price: 0),
          ],
        ),
        OptionGroup(
          id: 'boisson',
          title: 'Boisson',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'avec_boisson', label: 'Avec boisson', price: 2.00),
            OptionItem(id: 'sans_boisson', label: 'Sans boisson', price: 0),
          ],
        ),
      ],
    ));

    // ——— BURGER
    products.add(Product(
      id: 'p_burger',
      name: 'Burger',
      groups: [
        OptionGroup(
          id: 'pain_b',
          title: 'Pain',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'classic', label: 'Classique', price: 0),
            OptionItem(id: 'sesame', label: 'Sésame', price: 0.50),
          ],
        ),
        OptionGroup(
          id: 'cuisson',
          title: 'Cuisson',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'a_point', label: 'À point', price: 0),
            OptionItem(id: 'bien_cuit', label: 'Bien cuit', price: 0),
          ],
        ),
        OptionGroup(
          id: 'tops',
          title: 'Toppings (max 3)',
          multiple: true,
          minSelect: 0,
          maxSelect: 3,
          items: [
            OptionItem(id: 'fromage', label: 'Fromage', price: 1.20),
            OptionItem(id: 'oignons', label: 'Oignons', price: 0.50),
            OptionItem(id: 'cornichons', label: 'Cornichons', price: 0.50),
            OptionItem(id: 'bacon_b', label: 'Bacon', price: 1.50),
          ],
        ),
      ],
    ));

    // ——— PIZZA
    products.add(Product(
      id: 'p_pizza',
      name: 'Pizza',
      groups: [
        OptionGroup(
          id: 'taille',
          title: 'Taille',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'm', label: 'M (26cm)', price: 0),
            OptionItem(id: 'l', label: 'L (32cm) +€2.00', price: 2.00),
          ],
        ),
        OptionGroup(
          id: 'base',
          title: 'Base',
          multiple: false,
          minSelect: 1,
          maxSelect: 1,
          items: [
            OptionItem(id: 'tomate', label: 'Sauce tomate', price: 0),
            OptionItem(id: 'creme', label: 'Crème', price: 0),
          ],
        ),
        OptionGroup(
          id: 'extra',
          title: 'Suppléments (max 3)',
          multiple: true,
          minSelect: 0,
          maxSelect: 3,
          items: [
            OptionItem(id: 'mozz', label: 'Mozzarella', price: 1.20),
            OptionItem(id: 'olive', label: 'Olives', price: 0.60),
            OptionItem(id: 'champ', label: 'Champignons', price: 0.80),
            OptionItem(id: 'jambon', label: 'Jambon', price: 1.50),
          ],
        ),
      ],
    ));
  }

  /* ürün */
  void addProduct(Product p) { products.add(p); notifyListeners(); }
  void replaceProductAt(int i, Product p) { products[i] = p; notifyListeners(); }

  /* sepet */
  void addToCart(Product p, Map<String, List<OptionItem>> picked) {
    final deep = { for (final e in picked.entries) e.key: List<OptionItem>.from(e.value) };
    final snap = Product.fromJson(p.toJson()); // snapshot
    cart.add(CartLine(snapshot: snap, picked: deep));
    notifyListeners();
  }
  void removeCartLine(int i) { if (i>=0 && i<cart.length) { cart.removeAt(i); notifyListeners(); } }
  void clearCart() { cart.clear(); notifyListeners(); }

  /* sipariş */
  void finalizeOrder(String customer) {
    if (cart.isEmpty) return;
    final deep = cart.map((l) => CartLine(
      snapshot: Product.fromJson(l.snapshot.toJson()),
      picked: { for (final e in l.picked.entries) e.key: List<OptionItem>.from(e.value) },
    )).toList();
    orders.add(SavedOrder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      customer: customer,
      lines: deep,
    ));
    cart.clear(); notifyListeners();
  }
  void clearOrders() { orders.clear(); notifyListeners(); }

  /* dışa/içe aktar — sadece MENÜ (ürünler) */
  String exportMenuJson() {
    final data = {'products': products.map((e) => e.toJson()).toList()};
    return const JsonEncoder.withIndent('  ').convert(data);
  }
  void importMenuJson(String jsonStr) {
    final map = json.decode(jsonStr) as Map<String, dynamic>;
    final list = (map['products'] as List<dynamic>? ?? [])
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    products..clear()..addAll(list);
    notifyListeners();
  }
}

/* InheritedNotifier: global erişim */
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState notifier, required Widget child})
      : super(notifier: notifier, child: child);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/* =======================
   HOME
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
    final total = app.cart.fold(0.0, (s, l) => s + l.total);
    final badge = app.cart.length;

    final pages = [
      const ProductsPage(),
      CreateProductPage(onSwitchTab: (i) => setState(() => index = i)),
      const CartPage(),
      const OrdersPage(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Commande Sur Place')),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) async {
          if (i == 1) { final ok = await _askPin(context); if (!ok) return; }
          setState(() => index = i);
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Produits'),
          const NavigationDestination(icon: Icon(Icons.edit_note), label: 'Créer'),
          NavigationDestination(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_bag_outlined),
                if (badge > 0)
                  Positioned(
                    right: -6, top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text('$badge', style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            label: 'Panier (€${total.toStringAsFixed(2)})',
          ),
          const NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Commandes'),
        ],
      ),
    );
  }
}

/* =======================
   PRODUCTS
   ======================= */
class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final items = app.products;

    if (items.isEmpty) {
      return const Center(child: Text('Aucun produit. Allez à "Créer" pour en ajouter.'));
    }

    final w = MediaQuery.of(context).size.width;
    int cross = 2; if (w > 600) cross = 3; if (w > 900) cross = 4;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .86,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _ProductCard(product: items[i], index: i),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product; final int index;
  const _ProductCard({required this.product, required this.index});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    Future<void> openWizard() async {
      final added = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => OrderWizard(product: product)),
      );
      if (added == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajouté au panier.')));
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: openWizard,
      child: Ink(
        decoration: BoxDecoration(color: color.surfaceVariant, borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: color.primary.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.fastfood, color: color.primary, size: 42),
              ),
            ),
            const SizedBox(height: 10),
            Text(product.name, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('${product.groups.length} groupe(s)', style: TextStyle(color: color.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(children: [
              choisirButton(openWizard, context),
              const Spacer(),
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final ok = await _askPin(context); if (!ok) return;
                  if (context.mounted) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CreateProductPage(editIndex: index, onSwitchTab: (_) {}),
                    ));
                  }
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/* =======================
   CREATE / EDIT + MENU IMPORT/EXPORT
   ======================= */
class CreateProductPage extends StatefulWidget {
  final void Function(int) onSwitchTab;
  final int? editIndex;
  const CreateProductPage({super.key, required this.onSwitchTab, this.editIndex});
  @override
  State<CreateProductPage> createState() => _CreateProductPageState();
}

class _CreateProductPageState extends State<CreateProductPage> {
  final TextEditingController nameCtrl = TextEditingController(text: 'Nouveau');
  final List<OptionGroup> editingGroups = [];
  int? editingIndex;

  @override
  void initState() {
    super.initState();
    editingIndex = widget.editIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (editingIndex != null) _loadForEdit(editingIndex!); });
  }

  void _loadForEdit(int idx) {
    final app = AppScope.of(context);
    if (idx < 0 || idx >= app.products.length) return;
    final p = app.products[idx];
    nameCtrl.text = p.name;
    editingGroups..clear()..addAll(p.groups.map(_copyGroup));
    setState(() => editingIndex = idx);
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
    final name = nameCtrl.text.trim();
    if (name.isEmpty) { _snack(context, 'Nom du produit requis.'); return; }
    for (final g in editingGroups) {
      if (g.title.trim().isEmpty) { _snack(context, 'Titre du groupe manquant.'); return; }
      if (g.items.isEmpty) { _snack(context, 'Ajoutez au moins une option dans "${g.title}".'); return; }
      if (!g.multiple && (g.minSelect != 1 || g.maxSelect != 1)) { _snack(context, 'Choix unique → min=1 ve max=1 (${g.title}).'); return; }
      if (g.minSelect < 0 || g.maxSelect < 1 || g.minSelect > g.maxSelect) { _snack(context, 'Règles min/max invalides (${g.title}).'); return; }
    }

    final p = Product(
      id: editingIndex == null ? DateTime.now().microsecondsSinceEpoch.toString() : app.products[editingIndex!].id,
      name: name,
      groups: List.of(editingGroups),
    );

    if (editingIndex == null) { app.addProduct(p); _snack(context, 'Produit créé.'); }
    else { app.replaceProductAt(editingIndex!, p); _snack(context, 'Produit mis à jour.'); }

    nameCtrl.clear(); editingGroups.clear(); setState(() => editingIndex = null);

    if (!Navigator.canPop(context)) widget.onSwitchTab(0); else Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(onPressed: () {
            if (Navigator.canPop(context)) { Navigator.pop(context); } else { widget.onSwitchTab(0); }
          }, icon: const Icon(Icons.arrow_back)),
          const SizedBox(width: 8),
          Text(editingIndex == null ? 'Créer un produit' : 'Modifier un produit',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          MenuAnchor(
            builder: (context, controller, _) => FilledButton.tonalIcon(
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.more_horiz),
              label: const Text('Menu'),
            ),
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.upload_file_outlined),
                child: const Text('Exporter le menu (JSON)'),
                onPressed: () {
                  final jsonStr = app.exportMenuJson();
                  showDialog(context: context, builder: (_) => AlertDialog(
                    title: const Text('Menu JSON'),
                    content: SizedBox(
                      width: 520,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SelectableText(jsonStr, maxLines: 14),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () { Clipboard.setData(ClipboardData(text: jsonStr)); Navigator.pop(context); _snack(context, 'JSON kopyalandı.'); },
                          child: const Text('Kopyala'),
                        ),
                      ]),
                    ),
                  ));
                },
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.download_outlined),
                child: const Text('Importer le menu (coller JSON)'),
                onPressed: () {
                  final ctrl = TextEditingController();
                  showDialog(context: context, builder: (_) => AlertDialog(
                    title: const Text('Menu içe aktar'),
                    content: SizedBox(
                      width: 520,
                      child: TextField(
                        controller: ctrl, maxLines: 14,
                        decoration: const InputDecoration(
                          hintText: 'JSON\'ı buraya yapıştırın', border: OutlineInputBorder()),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
                      FilledButton(onPressed: () { try { app.importMenuJson(ctrl.text); Navigator.pop(context); _snack(context, 'Menü yüklendi.'); } catch (_) { _snack(context, 'Geçersiz JSON.'); } }, child: const Text('Yükle')),
                    ],
                  ));
                },
              ),
            ],
          ),
        ]),
        const SizedBox(height: 12),

        if (app.products.isNotEmpty) ...[
          const Text('Produits existants', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ListView.separated(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: app.products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = app.products[i];
              return ListTile(
                leading: const Icon(Icons.fastfood),
                title: Text(p.name),
                subtitle: Text('${p.groups.length} groupe(s)'),
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Modifier'),
                  onPressed: () => _loadForEdit(i),
                ),
              );
            },
          ),
          const Divider(height: 28),
        ],

        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nom du produit', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(onPressed: addGroup, icon: const Icon(Icons.add), label: const Text('Ajouter un groupe')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: saveProduct, icon: const Icon(Icons.save_outlined), label: const Text('Enregistrer')),
        ]),
        const SizedBox(height: 8),

        for (int i = 0; i < editingGroups.length; i++)
          _GroupEditor(
            key: ValueKey(editingGroups[i].id),
            group: editingGroups[i],
            onDelete: () => setState(() => editingGroups.removeAt(i)),
            onChanged: () => setState(() {}),
          ),
      ],
    );
  }
}

class _GroupEditor extends StatefulWidget {
  final OptionGroup group; final VoidCallback onDelete; final VoidCallback onChanged;
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

  void apply() {
    widget.group.title = titleCtrl.text.trim();
    widget.group.minSelect = int.tryParse(minCtrl.text) ?? 0;
    widget.group.maxSelect = int.tryParse(maxCtrl.text) ?? 1;
    widget.onChanged();
  }

  int get _mode => widget.group.multiple ? 1 : 0;
  set _mode(int v) {
    widget.group.multiple = v == 1;
    if (!widget.group.multiple) { minCtrl.text = '1'; maxCtrl.text = '1'; }
    apply(); setState(() {});
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
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Titre du groupe', border: OutlineInputBorder()),
              onChanged: (_) => apply(),
            )),
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
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              controller: minCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Sélection min', border: OutlineInputBorder()),
              onChanged: (_) => apply(),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: maxCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Sélection max', border: OutlineInputBorder()),
              onChanged: (_) => apply(),
            )),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: addOption, icon: const Icon(Icons.add), label: const Text('Option')),
          ]),
          const SizedBox(height: 6),
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
  final OptionItem item; final VoidCallback onDelete; final VoidCallback onChanged;
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
        Expanded(child: TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(labelText: 'Nom de l’option', border: OutlineInputBorder()),
          onChanged: (_) => apply(),
        )),
        const SizedBox(width: 8),
        SizedBox(width: 120, child: TextField(
          controller: priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prix (€)', border: OutlineInputBorder()),
          onChanged: (_) => apply(),
        )),
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
  const OrderWizard({super.key, required this.product});
  @override
  State<OrderWizard> createState() => _OrderWizardState();
}

class _OrderWizardState extends State<OrderWizard> {
  int step = 0;
  final Map<String, List<OptionItem>> picked = {};

  void _toggleSingle(OptionGroup g, OptionItem it) { picked[g.id] = [it]; setState(() {}); }
  void _toggleMulti(OptionGroup g, OptionItem it) {
    final list = picked[g.id] ?? [];
    final exists = list.any((e) => e.id == it.id);
    if (exists) { list.removeWhere((e) => e.id == it.id); }
    else { if (list.length >= g.maxSelect) return; list.add(it); }
    picked[g.id] = list; setState(() {});
  }
  bool _valid(OptionGroup g) {
    final n = (picked[g.id] ?? const <OptionItem>[]).length;
    return n >= g.minSelect && n <= g.maxSelect;
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.product.groups;
    final isSummary = step >= groups.length;
    final total = widget.product.priceFor(picked);

    return Scaffold(
      appBar: AppBar(
        title: Text(isSummary ? 'Récapitulatif' : widget.product.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (isSummary) { setState(() => step = groups.isEmpty ? 0 : groups.length - 1); }
            else if (step > 0) { setState(() => step--); }
            else { Navigator.pop(context); }
          },
        ),
      ),
      body: isSummary
          ? _Summary(product: widget.product, picked: picked, total: total)
          : _GroupStep(group: groups[step], picked: picked, toggleSingle: _toggleSingle, toggleMulti: _toggleMulti),
      // ——— BUTONLAR DAHA YUKARIDA: bottom padding 36
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 36),
        child: Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: step == 0 ? null : () => setState(() => step--),
            child: const Text('Précédent'),
          )),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(
            onPressed: () {
              if (isSummary) {
                AppScope.of(context).addToCart(widget.product, picked);
                Navigator.pop(context, true);
                return;
              }
              final g = groups[step];
              if (!_valid(g)) {
                _snack(context, 'Sélection invalide pour "${g.title}".');
                return;
              }
              setState(() => step++);
            },
            child: Text(isSummary ? 'Ajouter au panier' : 'Suivant'),
          )),
        ]),
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
    required this.group, required this.picked, required this.toggleSingle, required this.toggleMulti,
  });

  @override
  Widget build(BuildContext context) {
    final list = picked[group.id] ?? const <OptionItem>[];
    final color = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: group.items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              group.title + (group.multiple ? ' (min ${group.minSelect}, max ${group.maxSelect})' : ''),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          );
        }
        final it = group.items[i - 1];
        final selected = list.any((e) => e.id == it.id);

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => group.multiple ? toggleMulti(group, it) : toggleSingle(group, it),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? color.primaryContainer : color.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? color.primary : color.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (it.price != 0)
                    Text('+ €${it.price.toStringAsFixed(2)}', style: TextStyle(color: color.onSurfaceVariant)),
                ])),
                group.multiple
                    ? Checkbox(value: selected, onChanged: (_) => toggleMulti(group, it))
                    : Radio<bool>(value: true, groupValue: selected, onChanged: (_) => toggleSingle(group, it)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  final Product product; final Map<String, List<OptionItem>> picked; final double total;
  const _Summary({required this.product, required this.picked, required this.total});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Récapitulatif — ${product.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        for (final g in product.groups)
          if ((picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
            Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final it in picked[g.id]!)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('• ${it.label}'),
                Text(it.price == 0 ? '€0.00' : '€${it.price.toStringAsFixed(2)}'),
              ]),
            const Divider(),
          ],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('SOUS-TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('€${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 80),
      ],
    );
  }
}

/* =======================
   CART
   ======================= */
class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lines = app.cart;
    final total = lines.fold(0.0, (s, l) => s + l.total);

    if (lines.isEmpty) {
      return const Center(child: Text('Panier vide. Ajoutez des produits.'));
    }

    return Column(children: [
      const SizedBox(height: 6),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: lines.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final l = lines[i];
          return ListTile(
            leading: const Icon(Icons.fastfood),
            title: Text('${l.snapshot.name} • €${l.total.toStringAsFixed(2)}'),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final g in l.snapshot.groups)
                if ((l.picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
                  Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  for (final it in (l.picked[g.id] ?? const <OptionItem>[]))
                    Text('• ${it.label}${it.price == 0 ? '' : ' (+€${it.price.toStringAsFixed(2)})'}'),
                ],
            ]),
            trailing: IconButton(onPressed: () => app.removeCartLine(i), icon: const Icon(Icons.delete_outline)),
          );
        },
      )),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('€${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: FilledButton.icon(
          onPressed: () async {
            final name = await _askCustomerName(context);
            if (name == null) return;
            AppScope.of(context).finalizeOrder(name);
            if (context.mounted) { _snack(context, 'Commande validée pour "$name".'); }
          },
          icon: const Icon(Icons.check), label: const Text('Valider la commande'),
        ),
      ),
    ]);
  }
}

/* =======================
   ORDERS
   ======================= */
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final orders = app.orders.reversed.toList();

    if (orders.isEmpty) {
      return const Center(child: Text('Aucune commande.'));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          const Text('Commandes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              final pinOk = await _askPin(context); if (!pinOk) return;
              final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                title: const Text('Fin de journée ?'),
                content: const Text('Toutes les commandes seront supprimées. Action irréversible.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
                ],
              ));
              if (ok == true) app.clearOrders();
            },
            icon: const Icon(Icons.delete_forever), label: const Text('Journée terminée'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final o = orders[i];
          final who = o.customer.isEmpty ? '' : ' — ${o.customer}';
          return ListTile(
            leading: const Icon(Icons.receipt),
            title: Text('Commande$who • ${o.lines.length} article(s) • €${o.total.toStringAsFixed(2)}'),
            subtitle: Text(
              '${o.createdAt.hour.toString().padLeft(2,'0')}:${o.createdAt.minute.toString().padLeft(2,'0')}  '
              '${o.createdAt.day.toString().padLeft(2,'0')}/${o.createdAt.month.toString().padLeft(2,'0')}',
            ),
            trailing: const Icon(Icons.print_outlined),
            onTap: () {
              showDialog(context: context, builder: (_) => AlertDialog(
                title: const Text('Détails de la commande'),
                content: SizedBox(
                  width: 380,
                  child: ListView(shrinkWrap: true, children: [
                    if (o.customer.isNotEmpty)
                      Text('Client: ${o.customer}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (int idx = 0; idx < o.lines.length; idx++) ...[
                      Text('Article ${idx+1}: ${o.lines[idx].snapshot.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      for (final g in o.lines[idx].snapshot.groups)
                        if ((o.lines[idx].picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
                          Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          for (final it in (o.lines[idx].picked[g.id] ?? const <OptionItem>[]))
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('• ${it.label}'),
                              Text(it.price == 0 ? '€0.00' : '€${it.price.toStringAsFixed(2)}'),
                            ]),
                        ],
                      const Divider(),
                    ],
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('€${o.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () { _snack(context, 'Yazdırma Android’de sonraki adımda eklenecek.'); }, child: const Text('Imprimer')),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
                ],
              ));
            },
          );
        },
      )),
    ]);
  }
}

/* =======================
   DİYALOGLAR & UTIL
   ======================= */
Future<bool> _askPin(BuildContext context) async {
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
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == _ADMIN_PIN), child: const Text('Valider')),
      ],
    ),
  );
  if (ok != true) { _snack(context, 'Code incorrect.'); }
  return ok == true;
}

Future<String?> _askCustomerName(BuildContext context) async {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      return AlertDialog(
        title: const Text('Nom du client'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: 'Écrire le nom', border: const OutlineInputBorder(), errorText: error,
          ),
          onSubmitted: (_) {
            if (ctrl.text.trim().isEmpty) { set(() => error = 'Le nom est requis.'); }
            else { Navigator.pop(ctx, ctrl.text.trim()); }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Annuler')),
          FilledButton(onPressed: () {
            final name = ctrl.text.trim();
            if (name.isEmpty) { set(() => error = 'Le nom est requis.'); return; }
            Navigator.pop(ctx, name);
          }, child: const Text('Valider')),
        ],
      );
    }),
  );
}

void _snack(BuildContext ctx, String msg) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
}

/* =======================
   “CHOISIR” BUTONU — küçük ekranda kırılmayı engeller
   ======================= */
Widget choisirButton(VoidCallback onTap, BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  final tiny = w < 360;
  if (tiny) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.shopping_cart_outlined, size: 20),
      label: const SizedBox.shrink(),
      style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(56, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
    );
  }
  return FilledButton.icon(
    onPressed: onTap,
    icon: const Icon(Icons.shopping_cart_outlined, size: 20),
    label: const Text('Choisir', maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
    style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(118, 42),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
  );
}
