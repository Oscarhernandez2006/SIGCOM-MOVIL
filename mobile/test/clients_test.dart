import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/client.dart';
import 'package:sigcom_movil/screens/clients_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/theme.dart';
import 'package:sigcom_movil/utils/format.dart';

Map<String, dynamic> _row(int i, {String seller = '026'}) => {
  'id': 'id-$i',
  'code': '900$i',
  'name': 'CLIENTE $i',
  'branch': '001',
  'branch_name': 'CLIENTE $i',
  'city': 'Barranquilla',
  'price_list': '001',
  'price_list_name': 'LISTA GENERAL',
  'seller_code': seller,
  'seller': seller == '026' ? 'NELLY CHACON' : null,
  'phone': null,
};

class _FakeApi extends ApiService {
  final pages = <int>[];
  String? lastSeller;

  @override
  Future<ClientsPage> clientsCatalog(String company, {String? search, String? seller, int page = 1}) async {
    pages.add(page);
    lastSeller = seller;
    if (seller == '011') {
      return ClientsPage.fromJson({
        'clients': [_row(99, seller: '011')],
        'total': 1,
        'page': 1,
        'has_more': false,
        'can_sync': true,
      });
    }
    return ClientsPage.fromJson({
      'clients': [for (var i = (page - 1) * 40; i < page * 40; i++) _row(i)],
      'total': 80,
      'page': page,
      'has_more': page < 2,
      'can_sync': true,
    });
  }

  @override
  Future<List<ClientSeller>> clientSellers(String company) async => const [
    ClientSeller(code: '011', name: 'JERONIMO FARAH', clients: 646),
    ClientSeller(code: '026', name: 'NELLY CHACON', clients: 214),
  ];

  @override
  Future<ClientDetail> clientDetail(String company, String id) async => ClientDetail.fromJson({
    ..._row(0),
    'payment_term': '01D',
    'address': 'CRA 43 B 9 65',
    'neighborhood': null,
    'department': 'Atlántico',
    'email': 'cliente@correo.com',
    'delivery_schedule': {
      'days': [0, 1, 2, 3, 4],
      'hourFrom': '07:00',
      'hourTo': '17:00',
    },
    'locations': [
      {
        'address': 'Calle 43B # 9-65',
        'reference': 'Frente al parque',
        'neighborhood': 'Mercado',
        'city': 'Barranquilla',
        'department': null,
        'phone': null,
        'seller': 'NELLY CHACON',
        'updated_at': '2026-10-01T11:45:19-05:00',
      },
    ],
    'orders_90d': {'count': 11, 'total': 7765200},
    'recent_orders': [
      {
        'id': 'o1',
        'number': '8597',
        'second_number': null,
        'status': 'synced',
        'total': 160000,
        'created_at': '2026-10-10T10:00:00-05:00',
        'seller': 'NELLY CHACON',
      },
    ],
  });
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Lista paginada, filtra por vendedor y abre el detalle', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ClientsScreen(
            api: api,
            company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz', canClients: true),
            user: const {'name': 'Admin', 'role': 'admin'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('80 sucursales'), findsOneWidget);
    expect(find.text('CLIENTE 0'), findsOneWidget);

    await tester.fling(find.byType(CustomScrollView), const Offset(0, -6000), 3000);
    await tester.pumpAndSettle();
    expect(api.pages, [1, 2]);

    await tester.fling(find.byType(CustomScrollView), const Offset(0, 8000), 3000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos los vendedores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JERONIMO FARAH'));
    await tester.pumpAndSettle();
    expect(api.lastSeller, '011');
    expect(find.text('CLIENTE 99'), findsOneWidget);
    expect(find.text('Vendedor 011'), findsOneWidget);

    await tester.tap(find.text('CLIENTE 99'));
    await tester.pumpAndSettle();
    expect(find.text('Lunes a viernes de 7 a. m. a 5 p. m.'), findsOneWidget);
    expect(find.text('Calle 43B # 9-65'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('#8597'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('#8597'), findsOneWidget);
    expect(find.text('Ver cartera'), findsOneWidget);
  });
}
