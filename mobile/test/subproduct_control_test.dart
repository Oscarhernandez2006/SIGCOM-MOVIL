import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/approval.dart';
import 'package:sigcom_movil/models/ordering.dart';
import 'package:sigcom_movil/models/subproduct_control.dart';
import 'package:sigcom_movil/screens/subproduct_control_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/theme.dart';
import 'package:sigcom_movil/utils/format.dart';

Map<String, dynamic> _order(String id, String number, String status) => {
  'id': id,
  'number': number,
  'second_number': null,
  'status': status,
  'total': 200000,
  'created_at': DateTime.now().subtract(const Duration(minutes: 20)).toIso8601String(),
  'delivery_date': '2026-10-13',
  'notes': 'Nota',
  'logistics_note': null,
  'sync_error': status == 'failed' ? 'Siesa: bodega cerrada' : null,
  'seller': 'JOEL PAVA',
  'customer': {'name': 'CLIENTE $number', 'code': '900$number', 'branch': 'PRINCIPAL', 'price_list': '001'},
  'items': [
    {
      'sku': 'S1',
      'name': 'HUESO DE RES',
      'unit': 'KG',
      'quantity': 10,
      'unit_price': 20000,
      'discount_pct': 0,
      'total': 200000,
    },
  ],
};

class _FakeApi extends ApiService {
  Map<String, int>? saved;
  String? approved;
  String? priceList;
  String? type;

  @override
  Future<List<ControlOrder>> subproductControl(String company) async => [
    ControlOrder.fromJson(_order('a', '7001', 'pending_control')),
    ControlOrder.fromJson(_order('b', '7002', 'failed')),
  ];

  @override
  Future<List<Product>> products(String company, String priceList, {String? type}) async {
    this.priceList = priceList;
    this.type = type;
    return [
      const Product(sku: 'S1', name: 'HUESO DE RES', price: 20000, unit: 'KG', stock: 5, taxRate: 0, category: 'RES'),
      const Product(sku: 'S2', name: 'SEBO DE RES', price: 3000, unit: 'KG', stock: 0, taxRate: 0, category: 'RES'),
    ];
  }

  @override
  Future<ApprovalDecision> updateControlOrder(String company, ControlOrder order, Map<String, int> items) async {
    saved = items;
    return const ApprovalDecision(status: 'pending_control');
  }

  @override
  Future<ApprovalDecision> approveControlOrder(String company, String orderId) async {
    approved = orderId;
    return const ApprovalDecision(status: 'pending_approval');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Controla, edita y aprueba pedidos de subproductos', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SubproductControlScreen(
            api: api,
            company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz', canControlSubproducts: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('CLIENTE 7001'), findsOneWidget);
    expect(find.text('Siesa: bodega cerrada'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    // Editar: el disponible suma lo reservado por el pedido (5 en stock + 10 del pedido).
    await tester.tap(find.byTooltip('Editar').first);
    await tester.pumpAndSettle();
    expect(api.priceList, '001');
    expect(api.type, 'subproducto');
    expect(find.text('Disponible 15'), findsOneWidget);
    expect(find.text('Sin stock'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(api.saved, {'S1': 11});
    expect(find.text('Pedido #7001 actualizado.'), findsOneWidget);

    await tester.tap(find.text('Aprobar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aprobar y subir'));
    await tester.pump();
    await tester.pump();
    expect(api.approved, 'a');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('pasó a Aprobación de cartera'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
