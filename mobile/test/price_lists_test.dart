import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/price_list.dart';
import 'package:sigcom_movil/screens/price_lists_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/theme.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  String? openedCode;
  bool synced = false;

  @override
  Future<PriceListsResult> priceListsCatalog(String company) async => PriceListsResult.fromJson({
    'can_sync': true,
    'lists': [
      {
        'code': '001',
        'name': 'LISTA GENERAL',
        'items': 241,
        'clients': 2389,
        'updated_at': '2026-10-10T06:53:28-05:00',
      },
      {'code': '006', 'name': 'subproductos', 'items': 15, 'clients': 0, 'updated_at': '2026-10-10T06:53:28-05:00'},
    ],
  });

  @override
  Future<List<PriceListItem>> priceListItems(String company, String code) async {
    openedCode = code;
    return const [
      PriceListItem(sku: '1378', name: 'ATRAVESADO AL VACIO', unit: 'KG', price: 29400),
      PriceListItem(sku: '2027', name: 'PATICAS DE CERDO', unit: 'KG', price: 3800),
    ];
  }

  @override
  Future<PriceListSyncResult> syncPriceLists(String company) async {
    synced = true;
    return const PriceListSyncResult(lists: 36, created: 2, updated: 10, removed: 1, total: 2167);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Lista, busca, abre y sincroniza listas de precios', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: PriceListsScreen(
            api: api,
            company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz', canPriceLists: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LISTA GENERAL'), findsOneWidget);
    expect(find.text('Sin clientes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sub');
    await tester.pump();
    expect(find.text('LISTA GENERAL'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    await tester.tap(find.byTooltip('Sincronizar con Siesa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sincronizar'));
    await tester.pumpAndSettle();
    expect(api.synced, isTrue);
    expect(find.textContaining('36 listas'), findsOneWidget);

    await tester.tap(find.text('LISTA GENERAL'));
    await tester.pumpAndSettle();
    expect(api.openedCode, '001');
    expect(find.text('PATICAS DE CERDO'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1378');
    await tester.pump();
    expect(find.text('PATICAS DE CERDO'), findsNothing);
    expect(find.text('ATRAVESADO AL VACIO'), findsOneWidget);
  });
}
