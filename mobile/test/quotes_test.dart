import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/ordering.dart';
import 'package:sigcom_movil/models/quote.dart';
import 'package:sigcom_movil/screens/new_quote_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  Map<String, QuoteDraftLine>? lastLines;
  int? lastValidity;
  ({List<String> to, List<String> cc, String? message})? sent;

  @override
  Future<List<OrderClient>> orderClients(String company, String search) async => [
    OrderClient.fromJson({
      'id': '22222222-2222-2222-2222-222222222222',
      'code': '1065807100',
      'name': 'ESPINOSA BOLAÑOS DANIEL',
      'price_list': '001',
      'email': 'cliente@correo.com',
    }),
  ];

  @override
  Future<List<Product>> products(String company, String priceList, {String? type}) async => [
    Product.fromJson({
      'sku': '2409',
      'name': 'GRASA DE CERDO',
      'price': 10000,
      'unit': 'KG',
      'stock': 0,
      'tax_rate': 19,
      'category': 'CERDO',
    }),
  ];

  @override
  Future<CreatedQuote> createQuote({
    required String company,
    required String customerId,
    required Map<String, QuoteDraftLine> lines,
    required int validityDays,
    String? notes,
  }) async {
    lastLines = lines;
    lastValidity = validityDays;
    return const CreatedQuote(id: 'q1', number: '000016', total: 21420);
  }

  @override
  Future<String> sendQuote(String id, {required List<String> to, List<String> cc = const [], String? message}) async {
    sent = (to: to, cc: cc, message: message);
    return 'Cotización enviada a ${to.join(', ')}.';
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Crea una cotización con descuento y la envía por correo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: NewQuoteScreen(
          api: api,
          company: const Company(id: '3', name: 'AGRO', logo: 'santacruz'),
          user: const {'name': 'Joel', 'role': 'seller', 'email': 'joel@santacruz.com'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ESPINOSA BOLAÑOS DANIEL'));
    await tester.pumpAndSettle();

    // En cotizaciones el stock no limita.
    await tester.tap(find.text('Agregar'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ Agregar descuento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '10');
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    // 2 × 10.000 − 10 % = 18.000; IVA 19 % = 3.420.
    expect(find.text('\$ 21.420'), findsWidgets);

    await tester.tap(find.text('30 días'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear cotización'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.lastLines!['2409']!.quantity, 2);
    expect(api.lastLines!['2409']!.discountPct, 10);
    expect(api.lastValidity, 30);
    expect(find.text('Cotización 000016'), findsOneWidget);

    await tester.tap(find.text('Enviar correo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final to = find.widgetWithText(TextFormField, 'Para *');
    expect(find.descendant(of: to, matching: find.text('cliente@correo.com')), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Copia (CC)'), 'no-es-correo');
    await tester.tap(find.text('Enviar correo').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Correo no válido: no-es-correo'), findsOneWidget);
    expect(api.sent, isNull);

    await tester.enterText(find.widgetWithText(TextFormField, 'Copia (CC)'), 'compras@cliente.com');
    await tester.tap(find.text('Enviar correo').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.sent!.to, ['cliente@correo.com']);
    expect(api.sent!.cc, ['compras@cliente.com', 'joel@santacruz.com']);
    expect(api.sent!.message, contains('000016'));
  });
}
