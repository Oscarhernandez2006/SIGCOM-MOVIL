import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/order.dart';
import '../models/portfolio.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/status_pill.dart';
import '../widgets/web_session.dart';
import 'portfolio_screen.dart';

/// Catálogo › Clientes: maestro de clientes de Siesa por sucursal (web /admin/clientes).
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final List<ClientRow> _clients = [];
  int? _total;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _canSync = false;
  bool _syncing = false;
  String? _error;
  String _search = '';
  ClientSeller? _seller;
  List<ClientSeller>? _sellers;
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() {
    _clients.clear();
    _page = 0;
    _hasMore = true;
    _total = null;
    return _more();
  }

  Future<void> _more() async {
    if (!_hasMore) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.clientsCatalog(
        widget.company.id,
        search: _search,
        seller: _seller?.code,
        page: _page + 1,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _clients.addAll(page.clients);
        _page = page.page;
        _hasMore = page.hasMore;
        _total = page.total;
        _canSync = page.canSync;
      });
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _search = value;
      _reload();
    });
  }

  Future<void> _pickSeller() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      _sellers ??= await widget.api.clientSellers(widget.company.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }
    if (!mounted) return;
    final choice = await showModalBottomSheet<({ClientSeller? seller})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _SellerSheet(sellers: _sellers!, selected: _seller),
    );
    if (choice == null || choice.seller?.code == _seller?.code) return;
    setState(() => _seller = choice.seller);
    _reload();
  }

  Future<void> _sync() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizar con Siesa'),
        content: Text(
          'Se actualizan los clientes de ${widget.company.name} desde Siesa: datos, lista de precios, '
          'condición de pago y vendedor. Puede tardar un poco.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sincronizar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await withWebSession(context, widget.api, () => widget.api.syncClients(widget.company.id));
      if (r == null || !mounted) return;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            '${formatInt(r.total)} clientes. Nuevos ${formatInt(r.created)}, '
            'actualizados ${formatInt(r.updated)}, eliminados ${formatInt(r.removed)}.',
          ),
        ),
      );
      _sellers = null;
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _open(ClientRow client) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientDetailScreen(api: widget.api, company: widget.company, user: widget.user, client: client),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const BrandBackground(),
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _reload,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400 && !_loading && _hasMore && _error == null) _more();
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  sliver: SliverList.list(
                    children: [
                      _Header(total: _total, canSync: _canSync, syncing: _syncing, onSync: _sync, onSearch: _onSearch),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          avatar: Icon(
                            Icons.badge_outlined,
                            size: 18,
                            color: _seller == null ? AppColors.textSoft : AppColors.primary,
                          ),
                          label: Text(_seller == null ? 'Todos los vendedores' : _seller!.name),
                          backgroundColor: Colors.white,
                          onPressed: _pickSeller,
                        ),
                      ),
                      if (_error != null) _Message(icon: Icons.cloud_off_rounded, text: _error!, onRetry: _more),
                    ],
                  ),
                ),
                if (_clients.isEmpty && _loading)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (_clients.isEmpty && _error == null)
                  const SliverToBoxAdapter(
                    child: _Message(icon: Icons.person_search_rounded, text: 'No hay clientes con estos filtros.'),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList.separated(
                      itemCount: _clients.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i == _clients.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _ClientCard(client: _clients[i], onTap: () => _open(_clients[i]));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.canSync,
    required this.syncing,
    required this.onSync,
    required this.onSearch,
  });

  final int? total;
  final bool canSync;
  final bool syncing;
  final VoidCallback onSync;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F6B35), AppColors.primary, Color(0xFF34B868)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Clientes',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
              ),
              if (canSync)
                syncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : IconButton(
                        tooltip: 'Sincronizar con Siesa',
                        onPressed: onSync,
                        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18)),
                        icon: const Icon(Icons.sync_rounded, color: Colors.white),
                      ),
            ],
          ),
          Text(
            total == null ? 'Clientes y sucursales de Siesa' : '${formatInt(total!)} sucursales',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Nombre, sucursal o NIT',
              isDense: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search_rounded),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onTap});

  final ClientRow client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final branch = client.branchName != null && client.branchName != client.name ? client.branchName : null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (branch != null)
                      Text(branch, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        'NIT ${client.code}',
                        if (client.branch != null) 'Suc. ${client.branch}',
                        if (client.city != null) client.city!,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        _Tag(icon: Icons.sell_outlined, text: client.priceListName ?? client.priceList ?? 'Sin lista'),
                        _Tag(icon: Icons.badge_outlined, text: client.sellerLabel ?? 'Sin vendedor'),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.primary),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SellerSheet extends StatefulWidget {
  const _SellerSheet({required this.sellers, required this.selected});

  final List<ClientSeller> sellers;
  final ClientSeller? selected;

  @override
  State<_SellerSheet> createState() => _SellerSheetState();
}

class _SellerSheetState extends State<_SellerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final sellers = widget.sellers.where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.code.contains(q));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar vendedor',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                if (q.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.groups_rounded),
                    title: const Text('Todos los vendedores', style: TextStyle(fontWeight: FontWeight.w700)),
                    selected: widget.selected == null,
                    onTap: () => Navigator.pop(context, (seller: null)),
                  ),
                for (final s in sellers)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text(
                        s.code == 'none' ? '—' : s.code,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${formatInt(s.clients)} sucursales'),
                    selected: widget.selected?.code == s.code,
                    onTap: () => Navigator.pop(context, (seller: s)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textSoft),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.api,
    required this.company,
    required this.user,
    required this.client,
  });

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;
  final ClientRow client;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Future<ClientDetail> _future = widget.api.clientDetail(widget.company.id, widget.client.id);

  void _portfolio() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PortfolioDetailScreen(
          api: widget.api,
          company: widget.company,
          user: widget.user,
          client: PortfolioClient(nit: widget.client.code, name: widget.client.name, branches: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cliente', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _portfolio,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Ver cartera', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ),
      body: FutureBuilder<ClientDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.cloud_off_rounded,
              text: snapshot.error.toString(),
              onRetry: () => setState(() => _future = widget.api.clientDetail(widget.company.id, widget.client.id)),
            );
          }
          final d = snapshot.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          return _DetailBody(detail: d);
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final ClientDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = detail.row;
    String? join(List<String?> parts) {
      final text = parts.whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
      return text.isEmpty ? null : text;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (c.branchName != null && c.branchName != c.name)
                Text(c.branchName!, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Text(
                'NIT ${c.code}${c.branch == null ? '' : ' · Sucursal ${c.branch}'}',
                style: const TextStyle(color: AppColors.textSoft, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Stat(label: 'Pedidos (90 días)', value: formatInt(detail.ordersCount)),
                  ),
                  Expanded(
                    child: _Stat(label: 'Valor (90 días)', value: formatMoneyShort(detail.ordersTotal)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Comercial',
          icon: Icons.storefront_outlined,
          child: Column(
            children: [
              _Field(
                'Lista de precios',
                c.priceList == null ? null : '${c.priceList}${c.priceListName == null ? '' : ' · ${c.priceListName}'}',
              ),
              _Field('Condición de pago', detail.paymentTerm),
              _Field('Vendedor', c.sellerLabel),
              _Field('Horario de recibido', detail.schedule?.label),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Contacto (Siesa)',
          icon: Icons.contact_phone_outlined,
          child: Column(
            children: [
              _Field('Dirección', detail.address),
              _Field('Barrio', detail.neighborhood),
              _Field('Ciudad', join([c.city, detail.department])),
              _Field('Teléfono', c.phone),
              _Field('Correo', detail.email),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Ubicación capturada por vendedores',
          icon: Icons.place_outlined,
          child: detail.locations.isEmpty
              ? const Text(
                  'Ningún vendedor ha registrado la ubicación de este cliente.',
                  style: TextStyle(color: AppColors.textSoft),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, l) in detail.locations.indexed) ...[
                      if (i > 0) const Divider(height: 20, color: AppColors.border),
                      Text(l.address ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (l.reference != null && l.reference!.trim().isNotEmpty)
                        Text(l.reference!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                      Text(
                        [
                          join([l.neighborhood, l.city, l.department]),
                          l.phone,
                        ].whereType<String>().join(' · '),
                        style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                      ),
                      Text(
                        '${l.seller ?? 'Vendedor'}${l.updatedAt == null ? '' : ' · ${formatShortDate(l.updatedAt!)}'}',
                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Últimos pedidos',
          icon: Icons.receipt_long_outlined,
          child: detail.recentOrders.isEmpty
              ? const Text('Sin pedidos en SIGCOM.', style: TextStyle(color: AppColors.textSoft))
              : Column(
                  children: [
                    for (final (i, o) in detail.recentOrders.indexed) ...[
                      if (i > 0) const Divider(height: 18, color: AppColors.border),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.numberLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(
                                  '${formatShortDate(o.createdAt)}${o.seller == null ? '' : ' · ${o.seller}'}',
                                  style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                StatusPill(
                                  label: OrderStatusStyle.of(o.status).label,
                                  color: OrderStatusStyle.of(o.status).color,
                                ),
                              ],
                            ),
                          ),
                          Text(formatMoney(o.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSoft, fontSize: 12)),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title, this.icon});

  final Widget child;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title!.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: AppColors.textSoft, fontSize: 13)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
