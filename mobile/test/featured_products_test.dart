import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/featured.dart';
import 'package:sigcom_movil/screens/featured_products_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/theme.dart';
import 'package:sigcom_movil/utils/format.dart';

class _FakeApi extends ApiService {
  final added = <String>[];
  final removed = <String>[];

  @override
  Future<List<FeaturedProduct>> featuredProducts(String company, {bool catalog = false}) async => catalog
      ? const [
          FeaturedProduct(sku: '1006', name: 'LOMO ANCHO', unit: null, stock: 20, inCatalog: true),
          FeaturedProduct(sku: '1035', name: 'ASADO DE TIRA', unit: null, stock: 0, inCatalog: true),
        ]
      : const [
          FeaturedProduct(sku: '1006', name: 'LOMO ANCHO', unit: null, stock: 20, inCatalog: true),
          FeaturedProduct(sku: '9999', name: 'PRODUCTO VIEJO', unit: null, stock: null, inCatalog: false),
        ];

  @override
  Future<void> addFeaturedProduct(String company, String sku, String name) async => added.add(sku);

  @override
  Future<void> removeFeaturedProduct(String company, String sku) async => removed.add(sku);
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Marca y quita productos estrella', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: FeaturedProductsScreen(
            api: api,
            company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz', canFeaturedProducts: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 productos estrella'), findsOneWidget);
    expect(find.text('No está en el inventario'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar de estrella').last);
    await tester.pumpAndSettle();
    expect(api.removed, ['9999']);
    expect(find.text('PRODUCTO VIEJO'), findsNothing);

    await tester.tap(find.text('Agregar producto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASADO DE TIRA'));
    await tester.pumpAndSettle();
    expect(api.added, ['1035']);
    expect(find.text('Estrella'), findsNWidgets(2));

    Navigator.of(tester.element(find.text('Catálogo de cortes'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('2 productos estrella'), findsOneWidget);
    expect(find.text('ASADO DE TIRA'), findsOneWidget);
  });
}
