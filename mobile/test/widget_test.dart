import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sigcom_movil/screens/company_select_screen.dart';
import 'package:sigcom_movil/screens/login_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/services/credentials_store.dart';

class _FakeApi extends ApiService {
  @override
  Future<Map<String, dynamic>> health() async => {'database': 'ok'};

  @override
  Future<List<Company>> companies() async => const [
    Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz'),
    Company(id: 'MTAT', name: 'MONTERIA TAT AGROPECUARIA', logo: 'santacruz'),
  ];
}

void main() {
  testWidgets('Muestra las compañías y permite elegir una', (tester) async {
    Company? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: CompanySelectScreen(
          api: _FakeApi(),
          user: const {'name': 'Ana Pérez'},
          onSelected: (c) => selected = c,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('COMPAÑÍA 3'), findsOneWidget);
    expect(find.text('MONTERIA TAT AGROPECUARIA'), findsOneWidget);
    expect(find.text('COMPAÑÍA MTAT'), findsNothing);

    await tester.tap(find.text('AGROPECUARIA'));
    expect(selected?.id, '3');
  });
  testWidgets('Muestra el formulario de login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(api: _FakeApi(), onLoggedIn: (_) {}, credentials: _FakeCredentials()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('Cédula'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Recordar contraseña'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('Autocompleta las credenciales recordadas', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          api: _FakeApi(),
          onLoggedIn: (_) {},
          credentials: _FakeCredentials((document: '123456', password: 'secreta')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('123456'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });
}

class _FakeCredentials extends CredentialsStore {
  _FakeCredentials([this.saved]);

  final ({String document, String password})? saved;

  @override
  Future<({String document, String password})?> read() async => saved;
}
