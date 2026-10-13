import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/report.dart';
import 'package:sigcom_movil/screens/reports_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  final queries = <Map<String, String>>[];

  @override
  Future<ReportData> report(String key, String company, ReportQuery query) async {
    queries.add(query.toParams());
    return ReportData.fromJson({
      'title': 'Ventas por vendedor y producto',
      'kpis': [
        {'label': 'Líneas', 'value': 2, 'format': 'int'},
        {'label': 'Unidades', 'value': 30.5, 'format': 'qty'},
        {'label': 'Ingresos', 'value': 900000, 'format': 'money'},
      ],
      'rows': [
        {
          'title': 'PUNTA DE ANCA',
          'subtitle': 'JOEL PAVA · Ref. 1001',
          'value': 600000,
          'format': 'money',
          'details': [
            {'label': 'Cantidad KG', 'value': 20, 'format': 'qty'},
          ],
        },
        {
          'title': 'COSTILLA',
          'subtitle': 'SANDRA · Ref. 1002',
          'value': 300000,
          'format': 'money',
          'details': [
            {'label': 'Cantidad KG', 'value': 10.5, 'format': 'qty'},
          ],
        },
      ],
      'options': {
        'sellers': [
          {'id': '11111111-1111-1111-1111-111111111111', 'name': 'JOEL PAVA'},
        ],
        'products': [
          {'sku': '1001', 'name': 'PUNTA DE ANCA'},
        ],
      },
    });
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Muestra indicadores y filas, y filtra por vendedor', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ReportViewerScreen(
          api: api,
          company: const Company(id: '3', name: 'AGRO', logo: 'santacruz'),
          user: const {'name': 'Admin', 'role': 'admin'},
          def: reportCatalog.firstWhere((r) => r.key == 'seller-product'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\$ 900.000'), findsOneWidget);
    expect(find.text('30,5'), findsOneWidget);
    expect(find.text('Cantidad KG: 10,5'), findsOneWidget);
    expect(api.queries.single.containsKey('from'), isTrue);

    await tester.tap(find.text('Todos los vendedores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JOEL PAVA').last);
    await tester.pumpAndSettle();

    expect(api.queries.last['seller_id'], '11111111-1111-1111-1111-111111111111');
    expect(find.text('JOEL PAVA'), findsOneWidget);
  });

  test('Formatea los valores según su tipo', () {
    expect(formatReportValue(0.452, 'pct'), '45,2 %');
    expect(formatReportValue(1500000, 'money'), '\$ 1.500.000');
    expect(formatReportValue(null, 'money'), '—');
  });
}
