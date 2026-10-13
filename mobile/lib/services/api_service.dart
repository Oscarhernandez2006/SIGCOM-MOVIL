import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/approval.dart';
import '../models/availability.dart';
import '../models/client.dart';
import '../models/dashboard.dart';
import '../models/featured.dart';
import '../models/managerial.dart';
import '../models/order.dart';
import '../models/ordering.dart';
import '../models/portfolio.dart';
import '../models/price_list.dart';
import '../models/quote.dart';
import '../models/report.dart';
import '../models/settings.dart';
import '../models/subproduct_control.dart';
import '../utils/format.dart';

/// En el emulador Android, 10.0.2.2 apunta al localhost del PC.
/// Cambiar con: flutter run --dart-define=API_URL=https://mi-servidor/api
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000/api');

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// La API web (SIGCOM) pide reconfirmar la contraseña para escribir pedidos.
class WebSessionRequired extends ApiException {
  WebSessionRequired(super.message);
}

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.logo,
    this.canApprove = false,
    this.canControlSubproducts = false,
    this.canPriceLists = false,
    this.canFeaturedProducts = false,
    this.canClients = false,
    this.canSchedule = false,
    this.canUsers = false,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
    id: json['id'] as String,
    name: json['name'] as String,
    logo: json['logo'] as String,
    canApprove: json['can_approve'] as bool? ?? false,
    canControlSubproducts: json['can_control_subproducts'] as bool? ?? false,
    canPriceLists: json['can_price_lists'] as bool? ?? false,
    canFeaturedProducts: json['can_featured_products'] as bool? ?? false,
    canClients: json['can_clients'] as bool? ?? false,
    canSchedule: json['can_schedule'] as bool? ?? false,
    canUsers: json['can_users'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String logo;

  /// Admin, rol cartera o permiso /admin/cartera en esta compañía.
  final bool canApprove;

  /// Admin o permiso /admin/controlador-subproductos (solo en Agropecuaria).
  final bool canControlSubproducts;

  /// Admin o permiso /admin/listas-precios en esta compañía.
  final bool canPriceLists;

  /// Admin o permiso /admin/productos-estrella en esta compañía.
  final bool canFeaturedProducts;

  /// Admin o permiso /admin/clientes en esta compañía.
  final bool canClients;

  /// Admin o permiso /admin/horario-pedidos (global o en alguna compañía).
  final bool canSchedule;

  /// Solo administradores, como en la web.
  final bool canUsers;

  String get logoAsset => 'assets/images/logo_$logo.png';

  /// Igual que en la web: solo los códigos numéricos muestran "COMPAÑÍA N".
  String? get codeLabel => int.tryParse(id) != null ? 'COMPAÑÍA $id' : null;
}

class ApiService {
  ApiService({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<String?> get token => _storage.read(key: _tokenKey);

  Future<Map<String, String>> _headers() async {
    final t = await token;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  Future<dynamic> _send(Future<http.Response> request, {Duration timeout = _timeout}) async {
    final res = await _raw(request, timeout: timeout);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  /// Respuesta cruda si fue exitosa; si no, lanza el error con el mensaje de la API.
  Future<http.Response> _raw(Future<http.Response> request, {Duration timeout = _timeout}) async {
    final http.Response res;
    try {
      res = await request.timeout(timeout);
    } catch (_) {
      throw ApiException('No se pudo conectar con el servidor ($apiUrl).');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    if (res.statusCode == 401) await _storage.delete(key: _tokenKey);
    Object? body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      body = null;
    }
    final message = body is Map ? body['message'] : null;
    if (res.statusCode == 428) throw WebSessionRequired(message?.toString() ?? 'Confirma tu contraseña.');
    throw ApiException(message?.toString() ?? 'Error ${res.statusCode}');
  }

  Future<Map<String, dynamic>> health() async {
    final uri = Uri.parse('$apiUrl/health');
    try {
      final res = await _client.get(uri, headers: await _headers()).timeout(_timeout);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('No se pudo conectar con el servidor ($apiUrl).');
    }
  }

  Future<Map<String, dynamic>> login(String document, String password) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/login'),
        headers: await _headers(),
        body: jsonEncode({'document': document, 'password': password, 'device_name': 'sigcom_movil'}),
      ),
    ) as Map<String, dynamic>;
    await _storage.write(key: _tokenKey, value: data['token'] as String);
    return data['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async {
    return await _send(_client.get(Uri.parse('$apiUrl/user'), headers: await _headers())) as Map<String, dynamic>;
  }

  Future<List<Company>> companies() async {
    final data = await _send(_client.get(Uri.parse('$apiUrl/companies'), headers: await _headers())) as List<dynamic>;
    return data.map((e) => Company.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DashboardData> dashboard({
    required String company,
    required DateTime from,
    required DateTime to,
    String? sellerId,
    bool national = false,
  }) async {
    final uri = Uri.parse('$apiUrl/dashboard').replace(
      queryParameters: {
        'company': company,
        'from': formatApiDate(from),
        'to': formatApiDate(to),
        'seller': ?sellerId,
        if (national) 'national': '1',
      },
    );
    // Incluye consultas al ERP (Siesa), que pueden tardar más que el resto.
    final data = await _send(
      _client.get(uri, headers: await _headers()),
      timeout: const Duration(seconds: 60),
    ) as Map<String, dynamic>;
    return DashboardData.fromJson(data);
  }

  Future<OrdersResult> orders({
    required String company,
    required DateTime from,
    required DateTime to,
    OrderGroup? group,
    String? search,
    String? status,
    String? type,
  }) async {
    final uri = Uri.parse('$apiUrl/orders').replace(
      queryParameters: {
        'company': company,
        'from': formatApiDate(from),
        'to': formatApiDate(to),
        'group': ?group?.key,
        'status': ?status,
        'type': ?type,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    final data = await _send(_client.get(uri, headers: await _headers())) as Map<String, dynamic>;
    return OrdersResult.fromJson(data);
  }

  Future<OrderDetail> order(String id) async {
    final data =
        await _send(_client.get(Uri.parse('$apiUrl/orders/$id'), headers: await _headers())) as Map<String, dynamic>;
    return OrderDetail.fromJson(data);
  }

  Uri _ordering(String path, String company, [Map<String, String> query = const {}]) =>
      Uri.parse('$apiUrl/ordering$path').replace(queryParameters: {'company': company, ...query});

  Future<void> confirmWebSession(String password) async {
    await _send(
      _client.post(
        Uri.parse('$apiUrl/web-session'),
        headers: await _headers(),
        body: jsonEncode({'password': password}),
      ),
    );
  }

  Future<OrderingContext> orderingContext(String company) async {
    final data = await _send(_client.get(_ordering('/context', company), headers: await _headers()));
    return OrderingContext.fromJson(data as Map<String, dynamic>);
  }

  Future<List<OrderClient>> orderClients(String company, String search) async {
    final data = await _send(
      _client.get(
        _ordering('/clients', company, {if (search.trim().isNotEmpty) 'search': search.trim()}),
        headers: await _headers(),
      ),
    ) as List<dynamic>;
    return data.map((e) => OrderClient.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> products(String company, String priceList, {String? type}) async {
    final data = await _send(
      _client.get(_ordering('/products', company, {'price_list': priceList, 'type': ?type}), headers: await _headers()),
    ) as List<dynamic>;
    return data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<TodayOrder>> clientTodayOrders(String company, String clientId) async {
    final data = await _send(
      _client.get(_ordering('/clients/$clientId/today', company), headers: await _headers()),
    ) as Map<String, dynamic>;
    return (data['orders'] as List<dynamic>).map((e) => TodayOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ClientLocation?> clientLocation(String company, String clientId) async {
    final data = await _send(
      _client.get(_ordering('/clients/$clientId/location', company), headers: await _headers()),
    ) as Map<String, dynamic>;
    return ClientLocation.fromJson(data['location']);
  }

  Future<void> saveClientLocation(String company, String clientId, ClientLocation location) async {
    await _send(
      _client.put(
        _ordering('/clients/$clientId/location', company),
        headers: await _headers(),
        body: jsonEncode(location.toJson()),
      ),
    );
  }

  /// Crea el pedido a través del SIGCOM web; puede tardar porque sube a Siesa.
  Future<OrderResult> createOrder(String company, OrderDraft draft) async {
    final data = await _send(
      _client.post(
        _ordering('/orders', company),
        headers: await _headers(),
        body: jsonEncode({
          'customer_id': draft.customerId,
          'delivery_date': formatApiDate(draft.deliveryDate),
          'delivery_type': draft.deliveryType,
          'notes': ?draft.notes,
          'logistics_note': ?draft.logisticsNote,
          if (draft.schedule != null && draft.schedule!.isComplete) ...{
            'delivery_schedule': draft.schedule!.toJson(),
            'delivery_schedule_text': draft.schedule!.label,
          },
          'items': [
            for (final e in draft.items.entries) {'sku': e.key, 'quantity': e.value},
          ],
          'idempotency_key': draft.idempotencyKey,
          'linked_order_id': ?draft.linkedOrderId,
        }),
      ),
      timeout: const Duration(seconds: 120),
    ) as Map<String, dynamic>;
    return OrderResult.fromJson(data);
  }

  Future<OrderResult> cancelOrder(String company, String orderId, String reason) async {
    final data = await _send(
      _client.post(
        _ordering('/orders/$orderId/cancel', company),
        headers: await _headers(),
        body: jsonEncode({'reason': reason}),
      ),
    ) as Map<String, dynamic>;
    return OrderResult.fromJson(data);
  }

  Future<ApprovalsResult> approvals(String company) async {
    final uri = Uri.parse('$apiUrl/approvals').replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as Map<String, dynamic>;
    return ApprovalsResult.fromJson(data);
  }

  /// Aprueba en la web, que sube el pedido a Siesa (puede tardar).
  Future<ApprovalDecision> approveOrder(String company, String orderId) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/approvals/$orderId/approve'),
        headers: await _headers(),
        body: jsonEncode({'company': company}),
      ),
      timeout: const Duration(seconds: 120),
    ) as Map<String, dynamic>;
    return ApprovalDecision.fromJson(data);
  }

  Future<ApprovalDecision> disapproveOrder(String company, String orderId, String? reason) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/approvals/$orderId/disapprove'),
        headers: await _headers(),
        body: jsonEncode({'company': company, 'reason': ?reason}),
      ),
    ) as Map<String, dynamic>;
    return ApprovalDecision.fromJson(data);
  }

  Future<List<ControlOrder>> subproductControl(String company) async {
    final uri = Uri.parse('$apiUrl/subproduct-control').replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as List<dynamic>;
    return data.map((e) => ControlOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Reemplaza las líneas del pedido; la web devuelve el stock anterior y reserva el nuevo.
  Future<ApprovalDecision> updateControlOrder(String company, ControlOrder order, Map<String, int> items) async {
    final discounts = {for (final i in order.items) i.sku: i.discountPct};
    final data = await _send(
      _client.patch(
        Uri.parse('$apiUrl/subproduct-control/${order.id}'),
        headers: await _headers(),
        body: jsonEncode({
          'company': company,
          'items': [
            for (final e in items.entries) {'sku': e.key, 'quantity': e.value, 'discount_pct': discounts[e.key] ?? 0},
          ],
          'notes': ?order.notes,
          'logistics_note': ?order.logisticsNote,
          if (order.deliveryDate != null) 'delivery_date': formatApiDate(order.deliveryDate!),
        }),
      ),
      timeout: const Duration(seconds: 60),
    ) as Map<String, dynamic>;
    return ApprovalDecision.fromJson(data);
  }

  /// Aprueba y sube a Siesa; puede quedar en cartera si el cliente tiene saldo.
  Future<ApprovalDecision> approveControlOrder(String company, String orderId) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/subproduct-control/$orderId/approve'),
        headers: await _headers(),
        body: jsonEncode({'company': company}),
      ),
      timeout: const Duration(seconds: 120),
    ) as Map<String, dynamic>;
    return ApprovalDecision.fromJson(data);
  }

  Future<ApprovalDecision> rejectControlOrder(String company, String orderId, String? reason) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/subproduct-control/$orderId/reject'),
        headers: await _headers(),
        body: jsonEncode({'company': company, 'reason': ?reason}),
      ),
    ) as Map<String, dynamic>;
    return ApprovalDecision.fromJson(data);
  }

  Future<List<QuoteSummary>> quotes(String company, {String? search}) async {
    final uri = Uri.parse('$apiUrl/quotes').replace(
      queryParameters: {'company': company, if (search != null && search.trim().isNotEmpty) 'search': search.trim()},
    );
    final data = await _send(_client.get(uri, headers: await _headers())) as List<dynamic>;
    return data.map((e) => QuoteSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<QuoteDetail> quote(String id) async {
    final data = await _send(_client.get(Uri.parse('$apiUrl/quotes/$id'), headers: await _headers()));
    return QuoteDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<CreatedQuote> createQuote({
    required String company,
    required String customerId,
    required Map<String, QuoteDraftLine> lines,
    required int validityDays,
    String? notes,
  }) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/quotes'),
        headers: await _headers(),
        body: jsonEncode({
          'company': company,
          'customer_id': customerId,
          'validity_days': validityDays,
          'notes': ?notes,
          'items': [
            for (final e in lines.entries)
              {'sku': e.key, 'quantity': e.value.quantity, 'discount_pct': e.value.discountPct},
          ],
        }),
      ),
      timeout: const Duration(seconds: 60),
    );
    return CreatedQuote.fromJson(data as Map<String, dynamic>);
  }

  Future<List<int>> quotePdf(String id) async {
    final res = await _raw(
      _client.get(Uri.parse('$apiUrl/quotes/$id/pdf'), headers: await _headers()),
      timeout: const Duration(seconds: 60),
    );
    return res.bodyBytes;
  }

  Future<String> sendQuote(String id, {required List<String> to, List<String> cc = const [], String? message}) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/quotes/$id/send'),
        headers: await _headers(),
        body: jsonEncode({'to': to, 'cc': cc, 'message': ?message}),
      ),
      timeout: const Duration(seconds: 90),
    );
    return (data as Map<String, dynamic>)['message'] as String;
  }

  Future<({List<PortfolioClient> clients, bool limited})> portfolioClients(String company) async {
    final uri = Uri.parse('$apiUrl/portfolio').replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as Map<String, dynamic>;
    return (
      clients: (data['clients'] as List<dynamic>)
          .map((e) => PortfolioClient.fromJson(e as Map<String, dynamic>))
          .toList(),
      limited: data['limited'] as bool? ?? false,
    );
  }

  /// Saldos del ERP por NIT (máx. 30 por llamada); null si el ERP falló para ese NIT.
  Future<Map<String, PortfolioSummary?>> portfolioBalances(String company, List<String> nits) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/portfolio/balances'),
        headers: await _headers(),
        body: jsonEncode({'company': company, 'nits': nits}),
      ),
      timeout: const Duration(seconds: 60),
    );
    if (data is! Map<String, dynamic>) return {};
    return data.map((nit, v) => MapEntry(nit, v is Map<String, dynamic> ? PortfolioSummary.fromJson(v) : null));
  }

  Future<PortfolioDetail> portfolio(String company, String nit) async {
    final uri = Uri.parse('$apiUrl/portfolio/${Uri.encodeComponent(nit)}')
        .replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers()), timeout: const Duration(seconds: 60));
    return PortfolioDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<String> sendPortfolio(
    String company,
    String nit, {
    required List<int> pdf,
    required List<String> to,
    List<String> cc = const [],
    String? message,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$apiUrl/portfolio/${Uri.encodeComponent(nit)}/send'))
      ..headers.addAll(await _headers())
      ..fields['company'] = company
      ..files.add(http.MultipartFile.fromBytes('pdf', pdf, filename: 'estado-cartera-$nit.pdf'));
    request.headers.remove('Content-Type');
    for (final (i, email) in to.indexed) {
      request.fields['to[$i]'] = email;
    }
    for (final (i, email) in cc.indexed) {
      request.fields['cc[$i]'] = email;
    }
    if (message != null) request.fields['message'] = message;

    final data = await _send(
      _client.send(request).then(http.Response.fromStream),
      timeout: const Duration(seconds: 90),
    );
    return (data as Map<String, dynamic>)['message'] as String;
  }

  Uri _availability(String path, String company, String? priceList) =>
      Uri.parse('$apiUrl/availability$path').replace(queryParameters: {'company': company, 'price_list': ?priceList});

  Future<List<AvailableProduct>> availability(String company, {String? priceList}) async {
    final data = await _send(
      _client.get(_availability('', company, priceList), headers: await _headers()),
      timeout: const Duration(seconds: 45),
    ) as List<dynamic>;
    return data.map((e) => AvailableProduct.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PriceListRef>> priceLists(String company) async {
    final data = await _send(
      _client.get(_availability('/price-lists', company, null), headers: await _headers()),
    ) as List<dynamic>;
    return data.map((e) => PriceListRef.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrderScheduleSetting> orderSchedule() async {
    final data = await _send(
      _client.get(Uri.parse('$apiUrl/settings/order-schedule'), headers: await _headers()),
    ) as Map<String, dynamic>;
    return OrderScheduleSetting.fromJson(data);
  }

  Future<OrderScheduleSetting> saveOrderSchedule(
    String company, {
    required bool enabled,
    required String open,
    required String close,
  }) async {
    final data = await _send(
      _client.patch(
        Uri.parse('$apiUrl/settings/order-schedule'),
        headers: await _headers(),
        body: jsonEncode({'company': company, 'enabled': enabled, 'open': open, 'close': close}),
      ),
    ) as Map<String, dynamic>;
    return OrderScheduleSetting.fromJson(data);
  }

  Uri _users(String company, [String path = '']) =>
      Uri.parse('$apiUrl/admin/users$path').replace(queryParameters: {'company': company});

  Future<AdminUsersResult> adminUsers(String company) async {
    final data = await _send(_client.get(_users(company), headers: await _headers())) as Map<String, dynamic>;
    return AdminUsersResult.fromJson(data);
  }

  Future<AdminUser> _userWrite(Future<http.Response> request) async =>
      AdminUser.fromJson(await _send(request) as Map<String, dynamic>);

  /// [fields] usa las claves de la API móvil: document_id, name, password, email, role, client_budget.
  Future<AdminUser> createUser(String company, Map<String, Object?> fields) async =>
      _userWrite(_client.post(_users(company), headers: await _headers(), body: jsonEncode(fields)));

  Future<AdminUser> updateUser(String company, String id, Map<String, Object?> fields) async =>
      _userWrite(_client.patch(_users(company, '/$id'), headers: await _headers(), body: jsonEncode(fields)));

  Future<AdminUser> setUserActive(String company, String id, bool active) async => _userWrite(
    _client.patch(_users(company, '/$id/active'), headers: await _headers(), body: jsonEncode({'active': active})),
  );

  Future<void> deleteUser(String company, String id) async {
    await _send(_client.delete(_users(company, '/$id'), headers: await _headers()));
  }

  Future<AdminUser> assignUserCompany(String company, String id, String companyId, String? sellerCode) async =>
      _userWrite(
        _client.post(
          _users(company, '/$id/companies'),
          headers: await _headers(),
          body: jsonEncode({'company_id': companyId, 'siesa_seller_code': ?sellerCode}),
        ),
      );

  Future<AdminUser> removeUserCompany(String company, String id, String companyId) async =>
      _userWrite(_client.delete(_users(company, '/$id/companies/$companyId'), headers: await _headers()));

  Future<AdminUser> saveUserPermissions(String company, String id, String companyId, List<String> permissions) async =>
      _userWrite(
        _client.patch(
          _users(company, '/$id/companies/$companyId/permissions'),
          headers: await _headers(),
          body: jsonEncode({'permissions': permissions}),
        ),
      );

  Future<ClientsPage> clientsCatalog(String company, {String? search, String? seller, int page = 1}) async {
    final uri = Uri.parse('$apiUrl/clients').replace(
      queryParameters: {
        'company': company,
        'page': '$page',
        'seller': ?seller,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    final data = await _send(_client.get(uri, headers: await _headers())) as Map<String, dynamic>;
    return ClientsPage.fromJson(data);
  }

  Future<List<ClientSeller>> clientSellers(String company) async {
    final uri = Uri.parse('$apiUrl/clients/sellers').replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as List<dynamic>;
    return data.map((e) => ClientSeller.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ClientDetail> clientDetail(String company, String id) async {
    final uri = Uri.parse('$apiUrl/clients/$id').replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as Map<String, dynamic>;
    return ClientDetail.fromJson(data);
  }

  /// Trae los clientes desde Siesa a través de la web (solo administradores).
  Future<ClientSyncResult> syncClients(String company) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/clients/sync'),
        headers: await _headers(),
        body: jsonEncode({'company': company}),
      ),
      timeout: const Duration(seconds: 180),
    ) as Map<String, dynamic>;
    return ClientSyncResult.fromJson(data);
  }

  Future<List<FeaturedProduct>> featuredProducts(String company, {bool catalog = false}) async {
    final uri = Uri.parse('$apiUrl/featured-products${catalog ? '/catalog' : ''}')
        .replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as List<dynamic>;
    return data.map((e) => FeaturedProduct.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addFeaturedProduct(String company, String sku, String name) async {
    await _send(
      _client.post(
        Uri.parse('$apiUrl/featured-products'),
        headers: await _headers(),
        body: jsonEncode({'company': company, 'sku': sku, 'name': name}),
      ),
    );
  }

  Future<void> removeFeaturedProduct(String company, String sku) async {
    final uri = Uri.parse('$apiUrl/featured-products/${Uri.encodeComponent(sku)}')
        .replace(queryParameters: {'company': company});
    await _send(_client.delete(uri, headers: await _headers()));
  }

  Future<PriceListsResult> priceListsCatalog(String company) async {
    final uri = Uri.parse('$apiUrl/price-lists').replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as Map<String, dynamic>;
    return PriceListsResult.fromJson(data);
  }

  Future<List<PriceListItem>> priceListItems(String company, String code) async {
    final uri = Uri.parse('$apiUrl/price-lists/${Uri.encodeComponent(code)}')
        .replace(queryParameters: {'company': company});
    final data = await _send(_client.get(uri, headers: await _headers())) as List<dynamic>;
    return data.map((e) => PriceListItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<int>> priceListPdf(String company, String code) async {
    final uri = Uri.parse('$apiUrl/price-lists/${Uri.encodeComponent(code)}/pdf')
        .replace(queryParameters: {'company': company});
    final res = await _raw(_client.get(uri, headers: await _headers()), timeout: const Duration(seconds: 60));
    return res.bodyBytes;
  }

  /// Trae las listas desde Siesa a través de la web (solo administradores).
  Future<PriceListSyncResult> syncPriceLists(String company) async {
    final data = await _send(
      _client.post(
        Uri.parse('$apiUrl/price-lists/sync'),
        headers: await _headers(),
        body: jsonEncode({'company': company}),
      ),
      timeout: const Duration(seconds: 120),
    ) as Map<String, dynamic>;
    return PriceListSyncResult.fromJson(data);
  }

  Future<List<int>> availabilityPdf(String company, {String? priceList}) async {
    final res = await _raw(
      _client.get(_availability('/pdf', company, priceList), headers: await _headers()),
      timeout: const Duration(seconds: 60),
    );
    return res.bodyBytes;
  }

  Future<String> sendAvailability(
    String company, {
    PriceListRef? priceList,
    required List<String> to,
    List<String> cc = const [],
    String? message,
  }) async {
    final data = await _send(
      _client.post(
        _availability('/send', company, priceList?.code),
        headers: await _headers(),
        body: jsonEncode({'price_list_name': ?priceList?.label, 'to': to, 'cc': cc, 'message': ?message}),
      ),
      timeout: const Duration(seconds: 90),
    );
    return (data as Map<String, dynamic>)['message'] as String;
  }

  Future<List<CompanyStats>> managerial(String company, DateTime from, DateTime to) async {
    final uri = Uri.parse('$apiUrl/managerial')
        .replace(queryParameters: {'company': company, 'from': formatApiDate(from), 'to': formatApiDate(to)});
    final data = await _send(
      _client.get(uri, headers: await _headers()),
      timeout: const Duration(seconds: 90),
    ) as Map<String, dynamic>;
    return (data['companies'] as List<dynamic>).map((e) => CompanyStats.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// [month] es cualquier fecha del mes; con [day] se consulta solo ese día.
  Future<SellersRanking> sellersRanking(String company, DateTime month, {DateTime? day}) async {
    final ref = day ?? month;
    final uri = Uri.parse('$apiUrl/managerial/sellers').replace(
      queryParameters: {
        'company': company,
        'period': '${ref.year}${ref.month.toString().padLeft(2, '0')}',
        if (day != null) 'date': formatApiDate(day),
      },
    );
    final data = await _send(_client.get(uri, headers: await _headers()), timeout: const Duration(seconds: 90));
    return SellersRanking.fromJson(data as Map<String, dynamic>);
  }

  Uri _report(String key, String path, String company, ReportQuery query, [Map<String, String> extra = const {}]) =>
      Uri.parse('$apiUrl/reports/$key$path')
          .replace(queryParameters: {'company': company, ...query.toParams(), ...extra});

  Future<ReportData> report(String key, String company, ReportQuery query) async {
    final data = await _send(
      _client.get(_report(key, '', company, query), headers: await _headers()),
      timeout: const Duration(seconds: 90),
    );
    return ReportData.fromJson(data as Map<String, dynamic>);
  }

  /// [excel] = true descarga el .xlsx; si no, el PDF.
  Future<List<int>> reportFile(String key, String company, ReportQuery query, {bool excel = false}) async {
    final res = await _raw(
      _client.get(_report(key, '/file', company, query, {'format': excel ? 'xlsx' : 'pdf'}), headers: await _headers()),
      timeout: const Duration(seconds: 90),
    );
    return res.bodyBytes;
  }

  Future<String> sendReport(
    String key,
    String company,
    ReportQuery query, {
    required bool excel,
    required List<String> to,
    List<String> cc = const [],
    String? message,
    String? subtitle,
  }) async {
    final data = await _send(
      _client.post(
        _report(key, '/send', company, query, {'format': excel ? 'xlsx' : 'pdf'}),
        headers: await _headers(),
        body: jsonEncode({'to': to, 'cc': cc, 'message': ?message, 'subtitle': ?subtitle}),
      ),
      timeout: const Duration(seconds: 120),
    );
    return (data as Map<String, dynamic>)['message'] as String;
  }

  Future<void> logout() async {
    try {
      await _send(_client.post(Uri.parse('$apiUrl/logout'), headers: await _headers()));
    } finally {
      await _storage.delete(key: _tokenKey);
    }
  }
}
