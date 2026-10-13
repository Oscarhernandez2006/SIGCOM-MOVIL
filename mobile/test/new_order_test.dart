import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/ordering.dart';
import 'package:sigcom_movil/screens/new_order_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.sessionExpired = false});

  bool sessionExpired;
  String? confirmedPassword;
  final drafts = <OrderDraft>[];

  @override
  Future<OrderingContext> orderingContext(String company) async {
    if (sessionExpired) throw WebSessionRequired('Confirma tu contraseña para continuar.');
    return OrderingContext.fromJson({
      'schedule': {'enabled': true, 'open': '07:00', 'close': '16:30', 'is_open': true},
      'min_total': 150000,
      'requires_location': false,
      'featured': [],
    });
  }

  @override
  Future<void> confirmWebSession(String password) async {
    confirmedPassword = password;
    sessionExpired = false;
  }

  @override
  Future<List<OrderClient>> orderClients(String company, String search) async => [
    OrderClient.fromJson({
      'id': '11111111-1111-1111-1111-111111111111',
      'code': '900326452',
      'name': 'CARNES SANTACRUZ SAS',
      'branch_name': 'ASADERO LA 43',
      'price_list': '001',
      'price_list_name': 'GENERAL',
      'payment_term': 'CON',
      'city': 'Barranquilla',
      'delivery_schedule': {
        'days': [0, 1, 2, 3, 4],
        'hourFrom': '07:00',
        'hourTo': '17:00',
      },
    }),
  ];

  @override
  Future<List<Product>> products(String company, String priceList, {String? type}) async => [
    Product.fromJson({
      'sku': '1001',
      'name': 'PUNTA DE ANCA',
      'price': 30000,
      'unit': 'KG',
      'stock': 50,
      'tax_rate': 0,
      'category': 'RES',
    }),
    Product.fromJson({
      'sku': '2027',
      'name': 'PATICAS DE CERDO',
      'price': 3800,
      'unit': 'KG',
      'stock': 0,
      'tax_rate': 0,
      'category': 'CERDO',
    }),
  ];

  @override
  Future<List<TodayOrder>> clientTodayOrders(String company, String clientId) async => [];

  @override
  Future<OrderResult> createOrder(String company, OrderDraft draft) async {
    drafts.add(draft);
    return OrderResult.fromJson({'id': 'o1', 'number': '8700', 'status': 'synced', 'total': 150000});
  }
}

Future<void> _pump(WidgetTester tester, ApiService api) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => NewOrderScreen(
                    api: api,
                    company: const Company(id: '3', name: 'AGRO', logo: 'santacruz'),
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  test('Formatea el horario de recibido igual que la web', () {
    expect(
      const DeliverySchedule(days: {0, 1, 2, 3, 4}, hourFrom: '07:00', hourTo: '17:00').label,
      'Lunes a viernes de 7 a. m. a 5 p. m.',
    );
    expect(
      const DeliverySchedule(days: {0, 2, 4}, hourFrom: '08:30', hourTo: '12:00').label,
      'Lunes, miércoles y viernes de 8:30 a. m. a 12 p. m.',
    );
    expect(
      const DeliverySchedule(days: {0, 1, 4}, hourFrom: '06:00', hourTo: '14:00').label,
      'Lunes a martes y viernes de 6 a. m. a 2 p. m.',
    );
  });

  testWidgets('Arma y envía un pedido completo', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);
    await tester.pumpAndSettle();

    await tester.tap(find.text('CARNES SANTACRUZ SAS'));
    await tester.pumpAndSettle();

    // Sin stock no se puede agregar; con stock sí.
    expect(find.text('PUNTA DE ANCA'), findsOneWidget);
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('\$ 150.000'), findsOneWidget);

    await tester.tap(find.text('Cerdo (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Sin stock'), findsOneWidget);
    final add = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Agregar'));
    expect(add.onPressed, isNull);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Lunes a viernes de 7 a. m. a 5 p. m.'), findsOneWidget);

    // Sin fecha no envía.
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona la fecha de entrega del pedido.'), findsOneWidget);
    expect(api.drafts, isEmpty);

    await tester.tap(find.text('Fecha de entrega *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar pedido'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Pedido #8700'), findsOneWidget);
    expect(find.text('El pedido se envió a Siesa correctamente.'), findsOneWidget);
    final draft = api.drafts.single;
    expect(draft.customerId, '11111111-1111-1111-1111-111111111111');
    expect(draft.items, {'1001': 5});
    expect(draft.deliveryType, 'despacho');
    expect(draft.schedule?.days, {0, 1, 2, 3, 4});
    expect(draft.idempotencyKey, hasLength(32));

    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('Pide la contraseña si la sesión con SIGCOM venció y reintenta', (tester) async {
    final api = _FakeApi(sessionExpired: true);
    await _pump(tester, api);

    expect(find.text('Confirma tu contraseña'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'clave123');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(api.confirmedPassword, 'clave123');
    expect(find.text('CARNES SANTACRUZ SAS'), findsOneWidget);
  });
}
