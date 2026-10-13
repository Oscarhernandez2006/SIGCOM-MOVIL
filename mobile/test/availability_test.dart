import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/availability.dart';
import 'package:sigcom_movil/screens/availability_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  final requestedLists = <String?>[];
  ({PriceListRef? list, List<String> to})? sent;

  @override
  Future<List<AvailableProduct>> availability(String company, {String? priceList}) async {
    requestedLists.add(priceList);
    return [
      AvailableProduct.fromJson({
        'sku': '1001',
        'name': 'PUNTA DE ANCA',
        'unit': 'KG',
        'stock': 120.5,
        'price': priceList == null ? null : 30000,
        'category': 'RES',
      }),
      AvailableProduct.fromJson({
        'sku': '2027',
        'name': 'PATICAS DE CERDO',
        'unit': 'KG',
        'stock': 40,
        'price': priceList == null ? null : 3800,
        'category': 'CERDO',
      }),
    ];
  }

  @override
  Future<List<PriceListRef>> priceLists(String company) async => [const PriceListRef(code: '001', name: 'GENERAL')];

  @override
  Future<String> sendAvailability(
    String company, {
    PriceListRef? priceList,
    required List<String> to,
    List<String> cc = const [],
    String? message,
  }) async {
    sent = (list: priceList, to: to);
    return 'Disponibilidad enviada a ${to.join(', ')}.';
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Filtra, cambia de lista de precios y envía la disponibilidad', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvailabilityScreen(
            api: api,
            company: const Company(id: '3', name: 'AGRO', logo: 'santacruz'),
            user: const {'name': 'Joel', 'role': 'seller', 'email': 'joel@santacruz.com'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 referencias disponibles hoy'), findsOneWidget);
    expect(find.text('120,5 disp.'), findsOneWidget);
    expect(find.text('\$ 30.000'), findsNothing);

    await tester.tap(find.text('Cerdo (1)'));
    await tester.pumpAndSettle();
    expect(find.text('PUNTA DE ANCA'), findsNothing);
    expect(find.text('PATICAS DE CERDO'), findsOneWidget);

    await tester.tap(find.text('Sin precios (solo disponibilidad)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GENERAL'));
    await tester.pumpAndSettle();
    expect(api.requestedLists, [null, '001']);
    expect(find.text('\$ 3.800'), findsOneWidget);

    await tester.tap(find.text('Enviar correo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Para *'), 'compras@cliente.com');
    await tester.tap(find.text('Enviar correo').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.sent!.to, ['compras@cliente.com']);
    expect(api.sent!.list?.code, '001');
  });
}
