import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/dashboard.dart';
import 'package:sigcom_movil/screens/dashboard_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.extra = const {}});

  final Map<String, dynamic> extra;
  String? lastSeller;
  bool? lastNational;

  @override
  Future<DashboardData> dashboard({
    required String company,
    required DateTime from,
    required DateTime to,
    String? sellerId,
    bool national = false,
  }) async {
    lastSeller = sellerId;
    lastNational = national;
    return DashboardData.fromJson({
      'seller': null,
      'sellers': [
        {'id': 'a', 'name': 'JOEL PAVA'},
      ],
      'budget': {'revenue': 7320000000, 'kilos': 732000},
      'sales': null,
      'compliance': null,
      'projection': null,
      'profitability': null,
      'orders': {'count': 829, 'revenue': 1014604200, 'kilos': 79865, 'customers': 424, 'avg_ticket': 1223889},
      'top_customers': [],
      'working_days': {'total': 23, 'elapsed': 7},
      'generated_at': '2026-10-09T21:07:00-05:00',
      ...extra,
    });
  }
}

final _page = find.byType(Scrollable).first;

Future<void> _pump(WidgetTester tester, ApiService api, {bool national = false}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          api: api,
          company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz'),
          user: const {'name': 'Admin', 'role': 'admin'},
          national: national,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _nationalTest() {
  testWidgets('Negocios nacionales: sin filtro de vendedor ni clientes, con meta por tienda', (tester) async {
    final api = _FakeApi(
      extra: {
        'seller': {'id': 'j', 'name': 'JUAN FERNANDO SIERRA GONZALES'},
        'sellers': [],
        'client_budgets': [
          {
            'code': '890900608',
            'name': 'ALMACENES EXITO SA',
            'branch': 'ALMACENES EXITO SA',
            'target_revenue': 4500000000,
            'target_kilos': 0,
            'revenue': 834324245,
            'compliance': 0.1854,
          },
          {
            'code': '900319753',
            'name': 'PRICESMART COLOMBIA S.A.S',
            'branch': null,
            'target_revenue': 0,
            'target_kilos': 0,
            'revenue': 166320654,
            'compliance': null,
          },
        ],
      },
    );
    await _pump(tester, api, national: true);

    expect(api.lastNational, isTrue);
    expect(find.text('Negocios Nacionales'), findsOneWidget);
    expect(find.text('Vendedor: JUAN FERNANDO SIERRA GONZALES'), findsOneWidget);
    expect(find.text('Todos (general)'), findsNothing);

    await tester.scrollUntilVisible(find.text('ALMACENES EXITO SA'), 300, scrollable: _page);
    expect(find.text('18,5 %'), findsOneWidget);
    expect(find.text('Sin meta'), findsOneWidget);
    expect(find.text('MIS CLIENTES / TIENDAS'), findsNothing);
  });
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  _nationalTest();

  testWidgets('Muestra KPIs del dashboard comercial', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api);

    expect(find.text('Tablero de Gestión Comercial'), findsOneWidget);
    expect(find.text('Vendedor: General · Todos los vendedores'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('829'), 200, scrollable: _page);
    expect(find.text('\$ 7.320.000.000'), findsOneWidget);
    expect(find.text('732.000 kg'), findsOneWidget);
    expect(find.text('\$ 1.014.604.200'), findsOneWidget);
    expect(find.text('79.865 kg'), findsOneWidget);
    expect(find.text('Pendiente SIESA'), findsWidgets);
    expect(api.lastSeller, isNull);
  });

  testWidgets('Carnes Frías muestra unidades en vez de kilos', (tester) async {
    await _pump(
      tester,
      _FakeApi(
        extra: {
          'unit': 'und',
          'sales': {'revenue': 640424679, 'kilos': 64829},
          'growth': {'revenue': 0.31, 'kilos': 0.36},
        },
      ),
    );

    expect(find.text('UNIDADES VENDIDAS'), findsOneWidget);
    expect(find.text('64.829 und'), findsWidgets);
    expect(find.text('CREC. UNIDADES'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('829'), 200, scrollable: _page);
    expect(find.text('732.000 und'), findsOneWidget);
    expect(find.textContaining(' kg'), findsNothing);
  });

  testWidgets('Muestra ventas del ERP y detalle por categoría', (tester) async {
    await _pump(
      tester,
      _FakeApi(
        extra: {
          'sales': {'revenue': 1959295401, 'kilos': 187274},
          'compliance': {'revenue': 0.2677, 'kilos': 0.2558},
          'growth': {'revenue': 0.248, 'kilos': -0.05},
          'profitability': {'cost': 1575635614, 'margin': 383659787, 'margin_pct': 0.1958},
          'trend': [
            {'date': '2026-10-01', 'revenue': 210000000},
            {'date': '2026-10-02', 'revenue': 245000000},
          ],
          'categories': [
            {
              'category': 'Cortes',
              'kilos': 100,
              'revenue': 1196363599,
              'items': [
                {'name': 'PUNTA DE ANCA', 'ref': '1001', 'kilos': 100, 'revenue': 1196363599},
              ],
            },
          ],
        },
      ),
    );

    expect(find.text('\$ 1.959.295.401'), findsOneWidget);
    expect(find.text('24,8 %'), findsOneWidget);
    expect(find.text('5,0 %'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Cortes'), 300, scrollable: _page);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cortes'));
    await tester.pumpAndSettle();
    expect(find.text('PUNTA DE ANCA'), findsOneWidget);
  });

  testWidgets('Filtra clientes que compran y que no compran', (tester) async {
    Map<String, dynamic> customer(String name, String city) => {
      'name': name,
      'code': name,
      'branch': null,
      'city': city,
      'orders': 1,
      'revenue': 1000,
      'last_purchase': null,
    };
    await _pump(
      tester,
      _FakeApi(
        extra: {
          'top_customers': [customer('CARNES SANTACRUZ', 'Barranquilla'), customer('ASADERO EL TORO', 'Soledad')],
          'customers_not_buying': [customer('TIENDA LA 30', 'Malambo')],
        },
      ),
    );

    final search = find.widgetWithText(TextField, 'Buscar cliente, tienda, NIT o ciudad');
    await tester.scrollUntilVisible(search, 300, scrollable: _page);
    await tester.enterText(search, 'soledad');
    await tester.pumpAndSettle();
    expect(find.text('ASADERO EL TORO'), findsOneWidget);
    expect(find.text('CARNES SANTACRUZ'), findsNothing);

    await tester.tap(find.text('No compran (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Sin coincidencias para la búsqueda.'), findsOneWidget);
  });
}
