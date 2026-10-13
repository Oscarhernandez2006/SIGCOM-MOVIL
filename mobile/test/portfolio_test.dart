import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/portfolio.dart';
import 'package:sigcom_movil/screens/portfolio_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/utils/format.dart';
import 'package:sigcom_movil/utils/portfolio_pdf.dart';

const _company = Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz');

Map<String, dynamic> _summary(double total, double overdue, int days) => {
  'total': total,
  'overdue': overdue,
  'current': total - overdue,
  'max_days_overdue': days,
  'documents_count': 2,
  'credit_limit': null,
  'aging': {'current': total - overdue, 'd1_30': overdue, 'd31_60': 0, 'd61_90': 0, 'd90_plus': 0},
  'as_of': '2026-10-11',
};

PortfolioDetail _detail({int docs = 2}) => PortfolioDetail.fromJson({
  'client': {
    'nit': '901973552',
    'name': 'DISTRIBUCIONES GIL SAS',
    'payment_term': '08D',
    'emails': ['gil@hotmail.com'],
    'phones': [],
    'branches': [
      {'code': '001', 'name': 'PRINCIPAL', 'address': 'CRA 12', 'city': 'Valledupar'},
    ],
  },
  'summary': _summary(6817740, 3197534, 2),
  'documents': [
    for (var i = 0; i < docs; i++)
      {
        'number': '1FE-${65000 + i}',
        'type': 'FACTURA ELECTRÓNICA DE VENTA',
        'branch': '001',
        'date': '2026-10-01',
        'due_date': i.isEven ? '2026-10-09' : '2026-10-13',
        'days_overdue': i.isEven ? 2 : 0,
        'balance': 3000000,
      },
  ],
});

class _FakeApi extends ApiService {
  final batches = <List<String>>[];
  ({String nit, List<int> pdf, List<String> to})? sent;

  @override
  Future<({List<PortfolioClient> clients, bool limited})> portfolioClients(String company) async => (
    clients: [
      PortfolioClient.fromJson({'nit': '111', 'name': 'CLIENTE AL DÍA', 'branches': 1}),
      PortfolioClient.fromJson({
        'nit': '901973552',
        'name': 'DISTRIBUCIONES GIL SAS',
        'branches': 1,
        'city': 'Valledupar',
      }),
    ],
    limited: false,
  );

  @override
  Future<Map<String, PortfolioSummary?>> portfolioBalances(String company, List<String> nits) async {
    batches.add(nits);
    return {
      '111': PortfolioSummary.fromJson(_summary(0, 0, 0)),
      '901973552': PortfolioSummary.fromJson(_summary(6817740, 3197534, 2)),
    };
  }

  @override
  Future<PortfolioDetail> portfolio(String company, String nit) async => _detail();

  @override
  Future<String> sendPortfolio(
    String company,
    String nit, {
    required List<int> pdf,
    required List<String> to,
    List<String> cc = const [],
    String? message,
  }) async {
    sent = (nit: nit, pdf: pdf, to: to);
    return 'Estado de cartera enviado a ${to.join(', ')}.';
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Genera el PDF aunque el cliente tenga cientos de documentos', (tester) async {
    final bytes = await tester.runAsync(() => buildPortfolioPdf(detail: _detail(docs: 900), company: _company));
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(20000));
  });

  testWidgets('Lista la cartera ordenada por saldo y envía el estado por correo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioScreen(
            api: api,
            company: _company,
            user: const {'name': 'Joel', 'role': 'seller', 'email': 'joel@santacruz.com'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.batches.single, ['111', '901973552']);
    final gil = tester.getTopLeft(find.text('DISTRIBUCIONES GIL SAS'));
    final alDia = tester.getTopLeft(find.text('CLIENTE AL DÍA'));
    expect(gil.dy, lessThan(alDia.dy));
    expect(find.text('Al día'), findsOneWidget);

    await tester.tap(find.text('Con vencido'));
    await tester.pumpAndSettle();
    expect(find.text('CLIENTE AL DÍA'), findsNothing);

    await tester.tap(find.text('DISTRIBUCIONES GIL SAS'));
    await tester.pumpAndSettle();
    expect(find.text('Vencidos (1)'), findsOneWidget);

    await tester.tap(find.text('Enviar correo'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Enviar correo').last);
      for (var i = 0; i < 50 && api.sent == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();

    expect(api.sent!.nit, '901973552');
    expect(api.sent!.to, ['gil@hotmail.com']);
    expect(String.fromCharCodes(api.sent!.pdf.take(5)), '%PDF-');
  });
}
