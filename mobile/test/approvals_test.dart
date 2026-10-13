import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sigcom_movil/models/approval.dart';
import 'package:sigcom_movil/screens/approvals_screen.dart';
import 'package:sigcom_movil/services/api_service.dart';
import 'package:sigcom_movil/theme.dart';
import 'package:sigcom_movil/utils/format.dart';

Map<String, dynamic> _pending(String id, String number, {required Duration left}) {
  final now = DateTime.now();
  return {
    'id': id,
    'number': number,
    'second_number': null,
    'type': 'corte',
    'total': 1250000,
    'cartera_balance': 3400000,
    'created_at': now.subtract(const Duration(minutes: 30)).toIso8601String(),
    'approval_deadline': now.add(left).toIso8601String(),
    'delivery_date': '2026-10-13',
    'notes': null,
    'seller': 'JOEL PAVA',
    'customer': {'name': 'CLIENTE $number', 'code': '900$number', 'branch': 'PRINCIPAL', 'payment_term': '30 DIAS'},
    'items': [
      {
        'sku': '2027',
        'name': 'PATICAS DE CERDO',
        'unit': 'KG',
        'quantity': 25,
        'unit_price': 50000,
        'discount_pct': 0,
        'total': 1250000,
      },
    ],
  };
}

class _FakeApi extends ApiService {
  final approved = <String>[];
  final disapproved = <String, String?>{};

  @override
  Future<ApprovalsResult> approvals(String company) async => ApprovalsResult.fromJson({
    'server_time': DateTime.now().toIso8601String(),
    'orders': [
      _pending('a', '9001', left: const Duration(minutes: 10)),
      _pending('b', '9002', left: const Duration(hours: 1, minutes: 30)),
    ],
  });

  @override
  Future<ApprovalDecision> approveOrder(String company, String orderId) async {
    approved.add(orderId);
    return const ApprovalDecision(status: 'synced');
  }

  @override
  Future<ApprovalDecision> disapproveOrder(String company, String orderId, String? reason) async {
    disapproved[orderId] = reason;
    return const ApprovalDecision(status: 'disapproved');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(appLocale));

  testWidgets('Aprueba y desaprueba pedidos retenidos por cartera', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ApprovalsScreen(
            api: api,
            company: const Company(id: '3', name: 'AGROPECUARIA', logo: 'santacruz', canApprove: true),
            user: const {'name': 'Johanna', 'role': 'cartera'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('CLIENTE 9001'), findsOneWidget);
    expect(find.text('CLIENTE 9002'), findsOneWidget);
    expect(find.textContaining('0:09:'), findsOneWidget);
    expect(find.textContaining('1:29:'), findsOneWidget);

    await tester.tap(find.text('1 producto').first);
    await tester.pump();
    expect(find.text('PATICAS DE CERDO'), findsOneWidget);

    await tester.tap(find.text('Aprobar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aprobar').last);
    await tester.pump();
    await tester.pump();
    expect(api.approved, ['a']);
    expect(find.text('CLIENTE 9001'), findsNothing);
    expect(find.text('Pedido #9001 aprobado y enviado a Siesa.'), findsOneWidget);

    await tester.tap(find.text('Desaprobar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Facturas vencidas');
    await tester.tap(find.text('Desaprobar pedido'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.disapproved, {'b': 'Facturas vencidas'});
    expect(find.textContaining('No hay pedidos pendientes'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
