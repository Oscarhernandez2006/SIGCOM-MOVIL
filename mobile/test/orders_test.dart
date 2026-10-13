import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/order.dart';
import 'package:sigcom_movil/screens/orders_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';

Map<String, dynamic> _order(String id, String number, String status, {String? note}) => {
  'id': id,
  'number': number,
  'second_number': null,
  'type': 'corte',
  'status': status,
  'siesa_status': status == 'synced' ? 'Despachado' : null,
  'total': 95000,
  'items_count': 1,
  'customer': {'name': 'CLIENTE $number', 'code': '900$number', 'branch': 'TIENDA $number'},
  'seller': 'JOEL PAVA',
  'created_at': '2026-10-10T11:55:06-05:00',
  'delivery_date': '2026-10-13',
  'approval_deadline': null,
  'note': note,
};

class _FakeApi extends ApiService {
  OrderGroup? lastGroup;
  String? lastId;
  String? lastType;

  @override
  Future<OrdersResult> orders({
    required String company,
    required DateTime from,
    required DateTime to,
    OrderGroup? group,
    String? search,
    String? status,
    String? type,
  }) async {
    lastGroup = group;
    lastType = type;
    final all = [
      {..._order('a', '8686', 'synced'), 'download_count': 2, 'linked_number': '8600'},
      _order('b', '8687', 'failed', note: 'Siesa rechazó el documento'),
    ];
    return OrdersResult.fromJson({
      'orders': group == OrderGroup.issues ? [all[1]] : all,
      'summary': {
        'in_progress': {'count': 0, 'total': 0},
        'synced': {'count': 1, 'total': 95000},
        'issues': {'count': 1, 'total': 95000},
        'cancelled': {'count': 0, 'total': 0},
      },
      'limited': false,
    });
  }

  @override
  Future<OrderDetail> order(String id) async {
    lastId = id;
    return OrderDetail.fromJson({
      ..._order(id, '8686', 'synced'),
      'subtotal': 95000,
      'taxes': 0,
      'notes': null,
      'logistics_note': 'RUTA VALLEDUPAR',
      'delivery_type': 'despacho',
      'delivery_schedule': null,
      'sync_error': null,
      'cancel_reason': null,
      'disapproval_reason': null,
      'synced_at': '2026-10-10T11:55:12-05:00',
      'tracking': {
        'seller_document': '98601901',
        'seller_code': '014',
        'linked_number': '8600',
        'cartera_balance': null,
        'approved_by': 'JOHANNA CORREA',
        'approved_at': '2026-10-10T11:56:00-05:00',
        'siesa_previous_status': 'Aprobado',
        'siesa_document': 'PV-8686',
        'download_count': 2,
        'downloaded_at': '2026-10-10T14:00:00-05:00',
        'downloaded_by': 'JOSE',
      },
      'items': [
        {
          'sku': '2027',
          'name': 'PATICAS DE CERDO PICADAS',
          'unit': 'KG',
          'quantity': 25,
          'unit_price': 3800,
          'discount_pct': 0,
          'tax_rate': 0,
          'total': 95000,
        },
      ],
    });
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Lista, filtra y abre el detalle de pedidos', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrdersScreen(
            api: api,
            company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz'),
            user: const {'name': 'Joel', 'role': 'seller'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mis pedidos'), findsOneWidget);
    expect(find.text('#8686'), findsOneWidget);
    expect(find.text('Enviado a Siesa'), findsOneWidget);
    expect(find.text('Despachado'), findsOneWidget);
    expect(find.text('Siesa rechazó el documento'), findsOneWidget);

    final filters = find.descendant(
      of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text('Con novedad'), 150, scrollable: filters);
    await tester.tap(find.text('Con novedad'));
    await tester.pumpAndSettle();
    expect(api.lastGroup, OrderGroup.issues);
    expect(find.text('#8686'), findsNothing);

    await tester.scrollUntilVisible(find.text('Todos'), -150, scrollable: filters);
    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLIENTE 8686'));
    await tester.pumpAndSettle();
    expect(api.lastId, 'a');
    expect(find.text('PATICAS DE CERDO PICADAS'), findsOneWidget);
    expect(find.text('RUTA VALLEDUPAR'), findsOneWidget);
    expect(find.text('GENERACIÓN DEL PEDIDO'), findsNothing);
  });

  testWidgets('Seguimiento de pedidos muestra trazabilidad sin anular', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrdersScreen(
            api: api,
            company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz'),
            user: const {'name': 'Johanna', 'role': 'cartera'},
            tracking: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seguimiento de pedidos'), findsOneWidget);
    expect(find.text('Descargado 2 veces'), findsOneWidget);
    expect(find.text('Asociado a 8600'), findsOneWidget);
    expect(find.text('Sin descargar'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Subprod.'));
    await tester.pumpAndSettle();
    expect(api.lastType, 'subproducto');

    await tester.tap(find.text('CLIENTE 8686'));
    await tester.pumpAndSettle();
    expect(find.text('GENERACIÓN DEL PEDIDO'), findsOneWidget);
    expect(find.text('JOHANNA CORREA'), findsOneWidget);
    expect(find.text('Sin cartera pendiente'), findsOneWidget);
    expect(find.text('Anular pedido'), findsNothing);
    await tester.scrollUntilVisible(find.text('JOSE'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('PV-8686'), findsOneWidget);
  });
}
