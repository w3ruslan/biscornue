import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';

/* =======================
    Sabitler
    ======================= */
// LÜTFEN BU IP ADRESİNİ KENDİ YAZICINIZIN IP ADRESİYLE DEĞİŞTİRİN
const String PRINTER_IP = '192.168.1.1'; // <-- Epson yazıcının IP'si
const int    PRINTER_PORT = 9100;        // Genelde 9100 (RAW)

const String _ADMIN_PIN = '6538';

/* =======================
    ENTRY
    ======================= */
void main() {
  final appState = AppState();
  appState.loadSettings(); // Ayarları yükle
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
    MODELLER & STATE
    ======================= */
class Product {
  String name;
  final List<OptionGroup> groups;
  Product({required this.name, List<OptionGroup>? groups})
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
}

class OptionItem {
  final String id;
  String label;
  double price;
  OptionItem({required this.id, required this.label, required this.price});
}

class CartLine {
  final Product product;
  final Map<String, List<OptionItem>> picked; // deep copy saklı
  CartLine({required this.product, required this.picked});
  double get total => product.priceForSelection(picked);
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

  Future<void> loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    prepMinutes = sp.getInt('prepMinutes') ?? 5;
    notifyListeners();
  }

  Future<void> setPrepMinutes(int m) async {
    prepMinutes = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('prepMinutes', m);
    notifyListeners();
  }

  void addProduct(Product p) { products.add(p); notifyListeners(); }
  void replaceProductAt(int i, Product p) { products[i] = p; notifyListeners(); }

  void addLineToCart(Product p, Map<String, List<OptionItem>> picked) {
    final deep = { for (final e in picked.entries) e.key: List<OptionItem>.from(e.value) };
    cart.add(CartLine(product: p, picked: deep));
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
    cart[i] = CartLine(product: p, picked: deep);
    notifyListeners();
  }

  void finalizeCartToOrder({required String customer}) {
    if (cart.isEmpty) return;
    final deepLines = cart.map((l) => CartLine(
      product: l.product,
      picked: { for (final e in l.picked.entries) e.key: List<OptionItem>.from(e.value) },
    )).toList();

    final now   = DateTime.now();
    final ready = now.add(Duration(minutes: prepMinutes));

    orders.add(SavedOrder(
      id: now.millisecondsSinceEpoch.toString(),
      createdAt: now,
      readyAt: ready,
      lines: deepLines,
      customer: customer,
    ));
    cart.clear();
    notifyListeners();
  }
  void clearOrders() { orders.clear(); notifyListeners(); }
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
  bool _seeded = false;
  int index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;

    final app = AppScope.of(context);
    if (app.products.isEmpty) {
      final products = <Product>[
        Product(name: 'Sandwich', groups: [
          OptionGroup(
            id: 'type_sand', title: 'Sandwich', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'kebab',     label: 'Kebab',        price: 8.90),
              OptionItem(id: 'poulet',    label: 'Poulet',       price: 8.90),
              OptionItem(id: 'steak',     label: 'Steak hache',  price: 8.90),
              OptionItem(id: 'vege',      label: 'Vegetarien',   price: 8.90),
              OptionItem(id: 'berlineur', label: 'Berlineur',    price: 10.90),
            ],
          ),
          OptionGroup(
            id: 'pain', title: 'Pain', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'pita',    label: 'Pain pita', price: 0.00),
              OptionItem(id: 'galette', label: 'Galette',   price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'crudites',
            title: 'Crudites / Retirer (max 4)',
            multiple: true,
            minSelect: 0,
            maxSelect: 4,
            items: [
              OptionItem(id: 'sans_crudites', label: 'Sans crudites', price: 0),
              OptionItem(id: 'sans_tomates', label: 'Sans tomates', price: 0),
              OptionItem(id: 'sans_salade', label: 'Sans salade', price: 0),
              OptionItem(id: 'sans_oignons', label: 'Sans oignons', price: 0),
              OptionItem(id: 'sans_cornichons', label: 'Sans cornichons', price: 0),
            ],
          ),
          OptionGroup(
            id: 'supp', title: 'Supplements', multiple: true, minSelect: 0, maxSelect: 3,
            items: [
              OptionItem(id: 'cheddar',        label: 'Cheddar',                      price: 1.50),
              OptionItem(id: 'mozzarella',     label: 'Mozzarella rapee',             price: 1.50),
              OptionItem(id: 'feta',           label: 'Feta',                         price: 1.50),
              OptionItem(id: 'porc',           label: 'Poitrine de porc fume',        price: 1.50),
              OptionItem(id: 'chevre',         label: 'Chevre',                       price: 1.50),
              OptionItem(id: 'legumes',        label: 'Legumes grilles',              price: 1.50),
              OptionItem(id: 'oeuf',           label: 'Oeuf',                         price: 1.50),
              OptionItem(id: 'double_cheddar', label: 'Double Cheddar',               price: 3.00),
              OptionItem(id: 'double_mozza',   label: 'Double Mozzarella rapee',      price: 3.00),
              OptionItem(id: 'double_porc',    label: 'Double Poitrine de porc fume', price: 3.00),
            ],
          ),
          OptionGroup(
            id: 'sauces', title: 'Sauces', multiple: true, minSelect: 1, maxSelect: 2,
            items: [
              OptionItem(id: 'sans_sauce', label: 'Sans sauce',            price: 0.00),
              OptionItem(id: 'blanche',    label: 'Sauce blanche maison',  price: 0.00),
              OptionItem(id: 'ketchup',    label: 'Ketchup',               price: 0.00),
              OptionItem(id: 'mayo',       label: 'Mayonnaise',            price: 0.00),
              OptionItem(id: 'algerienne', label: 'Algerienne',            price: 0.00),
              OptionItem(id: 'bbq',        label: 'Barbecue',              price: 0.00),
              OptionItem(id: 'bigburger',  label: 'Big Burger',            price: 0.00),
              OptionItem(id: 'harissa',    label: 'Harissa',               price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'formule', title: 'Formule', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'seul',    label: 'Seul',                     price: 0.00),
              OptionItem(id: 'frites',  label: 'Avec frites',              price: 1.00),
              OptionItem(id: 'boisson', label: 'Avec boisson',             price: 1.00),
              OptionItem(id: 'menu',    label: 'Avec frites et boisson',   price: 2.00),
            ],
          ),
        ]),
        Product(name: 'Tacos', groups: [
          OptionGroup(
            id: 'type_tacos', title: 'Taille', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'm', label: 'M', price: 8.50),
              OptionItem(id: 'l', label: 'L', price: 10.00),
            ],
          ),
          OptionGroup(
            id: 'viande_tacos', title: 'Viande', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'kebab',  label: 'Kebab',  price: 0.00),
              OptionItem(id: 'poulet', label: 'Poulet', price: 0.00),
              OptionItem(id: 'steak',  label: 'Steak',  price: 0.00),
              OptionItem(id: 'vege',   label: 'Vegetarien', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'supp_tacos', title: 'Supplements', multiple: true, minSelect: 0, maxSelect: 3,
            items: [
              OptionItem(id: 'cheddar',    label: 'Cheddar',          price: 1.50),
              OptionItem(id: 'mozzarella', label: 'Mozzarella rapee', price: 1.50),
              OptionItem(id: 'oeuf',       label: 'Oeuf',             price: 1.00),
            ],
          ),
          OptionGroup(
            id: 'sauce_tacos', title: 'Sauces', multiple: true, minSelect: 1, maxSelect: 2,
            items: [
              OptionItem(id: 'blanche',    label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup',    label: 'Ketchup',              price: 0.00),
              OptionItem(id: 'mayo',       label: 'Mayonnaise',           price: 0.00),
              OptionItem(id: 'algerienne', label: 'Algerienne',           price: 0.00),
              OptionItem(id: 'bbq',        label: 'Barbecue',             price: 0.00),
              OptionItem(id: 'harissa',    label: 'Harissa',              price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'formule_tacos', title: 'Formule', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'seul',   label: 'Seul',                   price: 0.00),
              OptionItem(id: 'menu',   label: 'Avec frites et boisson', price: 2.00),
            ],
          ),
        ]),
        Product(name: 'Burgers', groups: [
          OptionGroup(
            id: 'type_burger', title: 'Burger', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'classic',  label: 'Classic',         price: 7.90),
              OptionItem(id: 'double',   label: 'Double cheese',   price: 9.90),
              OptionItem(id: 'chicken',  label: 'Chicken',         price: 8.50),
              OptionItem(id: 'veggie',   label: 'Veggie',          price: 8.50),
            ],
          ),
          OptionGroup(
            id: 'sauce_burger', title: 'Sauces', multiple: true, minSelect: 0, maxSelect: 2,
            items: [
              OptionItem(id: 'blanche',    label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup',    label: 'Ketchup',              price: 0.00),
              OptionItem(id: 'mayo',       label: 'Mayonnaise',           price: 0.00),
              OptionItem(id: 'bbq',        label: 'Barbecue',             price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'formule_burger', title: 'Formule', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'seul',    label: 'Seul',                    price: 0.00),
              OptionItem(id: 'frites',  label: 'Avec frites',             price: 1.00),
              OptionItem(id: 'menu',    label: 'Avec frites et boisson',  price: 2.00),
            ],
          ),
        ]),
        Product(name: 'Box', groups: [
          OptionGroup(
            id: 'type_box', title: 'Choix box', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'tenders6', label: '6 Tenders',  price: 6.50),
              OptionItem(id: 'nuggets9', label: '9 Nuggets',  price: 7.90),
              OptionItem(id: 'wings8',   label: '8 Wings',    price: 7.90),
              OptionItem(id: 'mix12',    label: 'Mix 12 pcs', price: 9.90),
            ],
          ),
          OptionGroup(
            id: 'sauce_box', title: 'Sauces', multiple: true, minSelect: 1, maxSelect: 2,
            items: [
              OptionItem(id: 'ketchup', label: 'Ketchup',   price: 0.00),
              OptionItem(id: 'mayo',    label: 'Mayonnaise',price: 0.00),
              OptionItem(id: 'bbq',     label: 'Barbecue',  price: 0.00),
              OptionItem(id: 'blanche', label: 'Sauce blanche maison', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'plus_box', title: 'Accompagnement', multiple: true, minSelect: 0, maxSelect: 2,
            items: [
              OptionItem(id: 'frites',  label: 'Frites',  price: 2.00),
              OptionItem(id: 'boisson', label: 'Boisson', price: 1.50),
            ],
          ),
        ]),
        Product(name: 'Menu Enfant', groups: [
          OptionGroup(
            id: 'choix_enfant', title: 'Choix', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'cheese_menu',  label: 'Cheeseburger avec frites', price: 7.90),
              OptionItem(id: 'nuggets_menu', label: '5 Nuggets et frites',      price: 7.90),
            ],
          ),
          OptionGroup(
            id: 'crudites_enfant', title: 'Crudites', multiple: true, minSelect: 0, maxSelect: 3,
            items: [
              OptionItem(id: 'avec',          label: 'Avec crudites',  price: 0.00),
              OptionItem(id: 'sans_salade',   label: 'Sans salade',    price: 0.00),
              OptionItem(id: 'sans_cornichon',label: 'Sans cornichon', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'sauce_enfant', title: 'Sauces', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'sans_sauce', label: 'Sans sauce',           price: 0.00),
              OptionItem(id: 'blanche',    label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup',    label: 'Ketchup',              price: 0.00),
              OptionItem(id: 'mayo',       label: 'Mayonnaise',           price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'boisson_enfant', title: 'Boisson', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'sans_boisson', label: 'Sans boisson', price: 0.00),
              OptionItem(id: 'avec_boisson', label: 'Avec boisson', price: 1.00),
            ],
          ),
        ]),
        Product(name: 'Petit Faim', groups: [
          OptionGroup(
            id: 'choix_pf', title: 'Choix', multiple: false, minSelect: 1, maxSelect: 1,
            items: [
              OptionItem(id: 'frites_p',  label: 'Frites petite portion', price: 3.00),
              OptionItem(id: 'frites_g',  label: 'Frites grande portion', price: 6.00),
              OptionItem(id: 'tenders3',  label: '3 Tenders', price: 0.00),
              OptionItem(id: 'tenders6',  label: '6 Tenders', price: 0.00),
              OptionItem(id: 'nuggets6',  label: '6 Nuggets', price: 0.00),
              OptionItem(id: 'nuggets12', label: '12 Nuggets', price: 0.00),
            ],
          ),
          OptionGroup(
            id: 'sauce_pf', title: 'Sauces', multiple: true, minSelect: 1, maxSelect: 2,
            items: [
              OptionItem(id: 'sans_sauce', label: 'Sans sauce',           price: 0.00),
              OptionItem(id: 'blanche',    label: 'Sauce blanche maison', price: 0.00),
              OptionItem(id: 'ketchup',    label: 'Ketchup',              price: 0.00),
              OptionItem(id: 'mayo',       label: 'Mayonnaise',           price: 0.00),
              OptionItem(id: 'algerienne', label: 'Algerienne',           price: 0.00),
              OptionItem(id: 'bbq',        label: 'Barbecue',             price: 0.00),
              OptionItem(id: 'bigburger',  label: 'Big Burger',           price: 0.00),
              OptionItem(id: 'harissa',    label: 'Harissa',              price: 0.00),
            ],
          ),
        ]),
      ];

      app.products.addAll(products);
    }
  }

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
      appBar: AppBar(title: const Text('BISCORNUE')),
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
            label: 'Panier (€${totalCart.toStringAsFixed(2)})',
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
    PAGE 2 : CRÉER + DÜZENLE (kısa versiyon)
    ======================= */
class CreateProductPage extends StatefulWidget {
  final void Function(int) onGoToTab;
  final int? editIndex;
  const CreateProductPage({super.key, required this.onGoToTab, this.editIndex});
  @override
  State<CreateProductPage> createState() => _CreateProductPageState();
}

class _CreateProductPageState extends State<CreateProductPage> {
  final TextEditingController nameCtrl = TextEditingController(text: 'Sandwich');
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
    if (nameCtrl.text.trim().isEmpty) { _snack(context, 'Nom du produit requis.'); return; }
    for (final g in editingGroups) {
      if (g.title.trim().isEmpty) { _snack(context, 'Titre du groupe manquant.'); return; }
      if (g.items.isEmpty) { _snack(context, 'Ajoutez au moins une option dans "${g.title}".'); return; }
      if (g.minSelect < 0 || g.maxSelect < 1 || g.minSelect > g.maxSelect) {
        _snack(context, 'Règles min/max invalides dans "${g.title}".'); return;
      }
      if (!g.multiple && (g.minSelect != 1 || g.maxSelect != 1)) {
        _snack(context, 'Choix unique doit avoir min=1 et max=1 (${g.title}).'); return;
      }
    }
    final p = Product(name: nameCtrl.text.trim(), groups: List.of(editingGroups));
    if (editingIndex == null) { app.addProduct(p); _snack(context, 'Produit créé.'); }
    else { app.replaceProductAt(editingIndex!, p); _snack(context, 'Produit mis à jour.'); }
    nameCtrl.text = ''; editingGroups.clear(); setState(() => editingIndex = null);

    if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
          }, tooltip: 'Retour'),
          const SizedBox(width: 8),
          Text(editingIndex == null ? 'Créer un produit' : 'Modifier un produit',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              nameCtrl.text = ''; editingGroups.clear(); setState(() => editingIndex = null);
              if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
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
                    decoration: const InputDecoration(
                      labelText: 'Délai de préparation (minutes)',
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
                    _snack(context, 'Délai enregistré: $m min');
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

        TextField(controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nom du produit', border: OutlineInputBorder())),
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

  void apply() {
    widget.group.title = titleCtrl.text.trim();
    widget.group.multiple = _mode == 1;
    widget.group.minSelect = int.tryParse(minCtrl.text) ?? 0;
    widget.group.maxSelect = int.tryParse(maxCtrl.text) ?? 1;
    widget.onChanged();
  }

  int get _mode => widget.group.multiple ? 1 : 0;
  set _mode(int v) { if (v == 0) { minCtrl.text = '1'; maxCtrl.text = '1'; } apply(); setState(() {}); }

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
                on
