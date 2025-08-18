import 'package:flutter_test/flutter_test.dart';
import 'package:surplace_pos/main.dart'; // pubspec.yaml -> name: surplace_pos

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Uygulamamızı oluşturup bir kare çizdiriyoruz.
    // HATA DÜZELTİLDİ: MyApp yerine projemizin doğru adı olan App kullanılıyor.
    await tester.pumpWidget(const App()); 
    
    // Uygulamanın doğru bir şekilde başladığını teyit etmek için
    // kök widget'ın (App) ekranda olduğunu kontrol ediyoruz.
    expect(find.byType(App), findsOneWidget);
  });
}
