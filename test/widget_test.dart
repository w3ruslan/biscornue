// Bu bir Flutter widget testidir.
//
// Widget testleri, tek bir widget'ı test etmenize olanak tanır. Test ortamı,
// widget'ın yaşam döngüsünü taklit eden bir arayüz sağlar.

import 'package:flutter_test/flutter_test.dart';
import 'package:surplace_pos/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Uygulamamızı oluşturup bir kare çizdiriyoruz.
    // HATA DÜZELTİLDİ: MyApp yerine projemizin doğru adı olan App kullanılıyor.
    await tester.pumpWidget(const App());

    // Uygulama başlığının "BISCORNUE" olduğunu doğruluyoruz.
    // Bu, uygulamanın doğru bir şekilde başladığını teyit eder.
    expect(find.text('BISCORNUE'), findsOneWidget);
  });
}
