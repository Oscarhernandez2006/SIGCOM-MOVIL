import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/settings.dart';
import 'package:sigcom_movil/screens/schedule_screen.dart';
import 'package:sigcom_movil/screens/users_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/theme.dart';
import 'package:sigcom_movil/utils/format.dart';

const _company = Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz', canSchedule: true, canUsers: true);

Map<String, dynamic> _user(String id, String name, String role, {bool active = true, List<String> perms = const []}) =>
    {
      'id': id,
      'document_id': '100$id',
      'email': null,
      'name': name,
      'role': role,
      'active': active,
      'client_budget': false,
      'must_change_password': false,
      'password_changed_at': null,
      'created_at': '2026-06-16T10:34:52-05:00',
      'companies': [
        {'id': '3', 'name': 'AGROPECUARIA', 'siesa_seller_code': role == 'seller' ? '017' : null, 'permissions': perms},
      ],
    };

class _FakeApi extends ApiService {
  Map<String, Object?>? savedSchedule;
  bool? active;
  List<String>? permissions;
  String? sellerCode;

  @override
  Future<OrderScheduleSetting> orderSchedule() async => OrderScheduleSetting.fromJson({
    'enabled': true,
    'open': '07:00',
    'close': '16:10',
    'is_open': false,
    'updated_at': '2026-10-11T14:38:53-05:00',
  });

  @override
  Future<OrderScheduleSetting> saveOrderSchedule(
    String company, {
    required bool enabled,
    required String open,
    required String close,
  }) async {
    savedSchedule = {'enabled': enabled, 'open': open, 'close': close};
    return OrderScheduleSetting.fromJson({'enabled': enabled, 'open': open, 'close': close, 'is_open': true});
  }

  @override
  Future<AdminUsersResult> adminUsers(String company) async => AdminUsersResult.fromJson({
    'users': [_user('1', 'JOEL PAVA', 'seller'), _user('2', 'JOHANNA CORREA', 'cartera', active: false)],
    'companies': [
      {'id': '3', 'name': 'AGROPECUARIA'},
      {'id': '8', 'name': 'CARNES FRIAS'},
    ],
  });

  @override
  Future<AdminUser> setUserActive(String company, String id, bool active) async {
    this.active = active;
    return AdminUser.fromJson(_user(id, 'JOEL PAVA', 'seller', active: active));
  }

  @override
  Future<AdminUser> assignUserCompany(String company, String id, String companyId, String? sellerCode) async {
    this.sellerCode = sellerCode;
    return AdminUser.fromJson(_user(id, 'JOEL PAVA', 'seller'));
  }

  @override
  Future<AdminUser> saveUserPermissions(String company, String id, String companyId, List<String> permissions) async {
    this.permissions = permissions;
    return AdminUser.fromJson(_user(id, 'JOEL PAVA', 'seller', perms: permissions));
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Horario: desactiva la restricción y guarda', (tester) async {
    final api = _FakeApi();
    await _pump(tester, ScheduleScreen(api: api, company: _company));

    expect(find.text('De 7 a. m. a 4:10 p. m.'), findsOneWidget);
    expect(find.text('Cerrado ahora'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Guardar horario'));
    await tester.pumpAndSettle();
    expect(api.savedSchedule, {'enabled': false, 'open': '07:00', 'close': '16:10'});
    expect(find.text('Sin restricción de horario'), findsOneWidget);
  });

  testWidgets('Usuarios: filtra, desactiva y asigna módulos', (tester) async {
    final api = _FakeApi();
    await _pump(tester, UsersScreen(api: api, company: _company, user: const {'id': 'admin', 'role': 'admin'}));

    expect(find.text('2 usuarios · 1 inactivos'), findsOneWidget);
    await tester.tap(find.text('Vendedor (1)'));
    await tester.pump();
    expect(find.text('JOHANNA CORREA'), findsNothing);
    await tester.tap(find.text('Todos'));
    await tester.pump();

    await tester.tap(find.text('JOEL PAVA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
    await tester.pumpAndSettle();
    expect(api.active, isFalse);

    await tester.tap(find.text('AGROPECUARIA'));
    await tester.pumpAndSettle();
    expect(find.text('017'), findsOneWidget);
    await tester.tap(find.text('Cotizaciones'));
    await tester.pump();
    await tester.tap(find.text('Guardar acceso'));
    await tester.pumpAndSettle();
    expect(api.sellerCode, '017');
    expect(api.permissions, ['/cotizaciones']);
    expect(find.textContaining('1 módulos'), findsOneWidget);
  });
}
