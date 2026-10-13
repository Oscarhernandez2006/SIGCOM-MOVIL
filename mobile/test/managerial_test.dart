import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/managerial.dart';
import 'package:sigcom_movil/screens/managerial_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  final rankingDays = <DateTime?>[];

  @override
  Future<List<CompanyStats>> managerial(String company, DateTime from, DateTime to) async => [
    CompanyStats.fromJson({
      'id': '3',
      'name': 'AGROPECUARIA',
      'totals': {'revenue': 1000000, 'orders': 926, 'units': 5000, 'avg_ticket': 1200000, 'customers': 424},
      'trend': [
        {'date': '2026-10-01', 'revenue': 200000000},
        {'date': '2026-10-02', 'revenue': 250000000},
      ],
      'top_products': [],
      'top_customers': [
        {'name': 'CARNES SANTACRUZ SAS', 'code': '900326452', 'orders': 63, 'revenue': 288124000},
      ],
      'top_sellers': [
        {'name': 'JOEL PAVA', 'orders': 51, 'revenue': 51538800},
      ],
      'margin': {
        'revenue': 3000000000,
        'cost': 2400000000,
        'profit': 600000000,
        'margin_pct': 20,
        'kilos': 187273.9,
        'by_seller': [
          {'name': 'SANDRA VASQUEZ', 'revenue': 900000000, 'profit': 180000000, 'margin_pct': 20, 'kilos': 50000},
        ],
        'by_product': [
          {'name': 'PUNTA DE ANCA', 'revenue': 500000000, 'profit': 100000000, 'margin_pct': 20},
        ],
      },
    }),
    CompanyStats.fromJson({
      'id': '8',
      'name': 'CARNES FRIAS',
      'totals': {'revenue': 1000000000, 'orders': 80, 'units': 900, 'avg_ticket': 12500000, 'customers': 40},
      'trend': [],
      'top_products': [
        {'name': 'SALCHICHA', 'quantity': 300, 'revenue': 9000000},
      ],
      'top_customers': [],
      'top_sellers': [],
      'margin': null,
    }),
  ];

  @override
  Future<SellersRanking> sellersRanking(String company, DateTime month, {DateTime? day}) async {
    rankingDays.add(day);
    return SellersRanking.fromJson({
      'period_label': 'octubre de 2026',
      'sales': {
        'total': 1959295401,
        'sellers': [
          {'name': 'SANDRA VASQUEZ', 'total': 900000000},
        ],
      },
      'orders': {
        'total': 1125752600,
        'count': 926,
        'sellers': [
          {'name': 'JOEL PAVA', 'total': 51538800, 'orders': 51},
        ],
      },
    });
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Muestra el comparativo, el detalle por compañía y el ranking de vendedores', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagerialScreen(
            api: api,
            company: const Company(id: '3', name: 'AGRO', logo: 'santacruz'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Agropecuaria usa la facturación del ERP (margen); Carnes Frías, sus pedidos.
    expect(find.text('Total general'), findsOneWidget);
    expect(find.text('\$ 4.000.000.000'), findsOneWidget);
    expect(find.text('75,0 %'), findsOneWidget);
    expect(find.text('Margen 20,0 %'), findsOneWidget);

    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('SANDRA VASQUEZ').first, 200, scrollable: page);
    await tester.ensureVisible(find.text('Pedido (app)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedido (app)'));
    await tester.pumpAndSettle();
    expect(find.text('JOEL PAVA'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Pedido del mes (app)'), 200, scrollable: page);
    expect(find.text('\$ 1.959.295.401'), findsOneWidget);
    expect(api.rankingDays, [null]);

    await tester.scrollUntilVisible(find.text('CARNES FRIAS').first, -300, scrollable: page);
    final chip = find.widgetWithText(ChoiceChip, 'CARNES FRIAS');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('SALCHICHA'), 200, scrollable: page);
    expect(find.text('Productos más vendidos'.toUpperCase()), findsOneWidget);
    expect(find.text('SALCHICHA'), findsOneWidget);
  });
}
