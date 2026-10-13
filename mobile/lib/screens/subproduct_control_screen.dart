import 'dart:async';

import 'package:flutter/material.dart';

import '../models/approval.dart';
import '../models/ordering.dart';
import '../models/subproduct_control.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/order_widgets.dart';
import '../widgets/status_pill.dart';
import '../widgets/web_session.dart';

const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);
const _blue = Color(0xFF2563EB);

/// Controlador de subproductos: revisa, ajusta y sube a Siesa los pedidos de subproducto.
class SubproductControlScreen extends StatefulWidget {
  const SubproductControlScreen({super.key, required this.api, required this.company});

  final ApiService api;
  final Company company;

  @override
  State<SubproductControlScreen> createState() => _SubproductControlScreenState();
}

class _SubproductControlScreenState extends State<SubproductControlScreen> {
  List<ControlOrder>? _orders;
  String? _error;
  bool _loading = false;
  final Set<String> _busy = {};
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await widget.api.subproductControl(widget.company.id);
      if (mounted) setState(() => _orders = orders);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(
    ControlOrder order,
    Future<ApprovalDecision> Function() action,
    void Function(ApprovalDecision) done,
  ) async {
    setState(() => _busy.add(order.id));
    try {
      final decision = await withWebSession(context, widget.api, action);
      if (decision == null || !mounted) return;
      done(decision);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
      _load();
    }
  }

  Future<void> _approve(ControlOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aprobar pedido ${order.numberLabel}'),
        content: Text(
          '${order.customer.name}\nTotal ${formatMoney(order.total)}\n\n'
          'Se sube a Siesa. Si el cliente tiene saldo en cartera, pasa primero a Aprobación de cartera.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aprobar y subir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(order, () => widget.api.approveControlOrder(widget.company.id, order.id), (d) {
      switch (d.status) {
        case 'pending_approval':
          _snack('Pedido ${order.numberLabel} pasó a Aprobación de cartera: el cliente tiene saldo pendiente.');
        case 'failed':
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded, color: _red, size: 36),
              title: const Text('Siesa no recibió el pedido'),
              content: Text(
                '${d.syncError ?? 'Siesa respondió con un error.'}\n\n'
                'El pedido sigue en la lista con estado Error: puedes ajustarlo y reintentar.',
              ),
              actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
            ),
          );
        default:
          _snack('Pedido ${order.numberLabel} aprobado y enviado a Siesa.');
      }
    });
  }

  Future<void> _reject(ControlOrder order) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _RejectSheet(order: order),
    );
    if (reason == null || !mounted) return;
    await _run(
      order,
      () => widget.api.rejectControlOrder(widget.company.id, order.id, reason.isEmpty ? null : reason),
      (_) => _snack('Pedido ${order.numberLabel} rechazado. Se devolvió el inventario.'),
    );
  }

  Future<void> _edit(ControlOrder order) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SubproductEditScreen(api: widget.api, company: widget.company, order: order),
      ),
    );
    if (saved == true && mounted) {
      _snack('Pedido ${order.numberLabel} actualizado.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    final pending = orders?.where((o) => !o.failed).length;
    final failed = orders?.where((o) => o.failed).length;
    return Stack(
      children: [
        const BrandBackground(),
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                sliver: SliverList.list(
                  children: [
                    _Header(
                      pending: pending,
                      failed: failed,
                      total: orders?.fold<double>(0, (s, o) => s + o.total),
                      loading: _loading,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _Message(icon: Icons.cloud_off_rounded, text: _error!, onRetry: _load),
                    ],
                  ],
                ),
              ),
              if (orders == null && _error == null)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (orders != null && orders.isEmpty)
                const SliverToBoxAdapter(
                  child: _Message(
                    icon: Icons.task_alt_rounded,
                    text: 'No hay pedidos de subproductos por controlar.\nLa lista se actualiza sola cada 30 segundos.',
                  ),
                )
              else if (orders != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final order = orders[i];
                      return _ControlCard(
                        order: order,
                        busy: _busy.contains(order.id),
                        onEdit: () => _edit(order),
                        onReject: () => _reject(order),
                        onApprove: () => _approve(order),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pending, required this.failed, required this.total, required this.loading});

  final int? pending;
  final int? failed;
  final double? total;
  final bool loading;

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
                  'Control de subproductos',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Revisa y ajusta los pedidos de subproductos antes de subirlos a Siesa.',
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeaderStat(label: 'Por controlar', value: pending == null ? '—' : formatInt(pending!)),
              const SizedBox(width: 8),
              _HeaderStat(label: 'Con error', value: failed == null ? '—' : formatInt(failed!)),
              const SizedBox(width: 8),
              _HeaderStat(label: 'Valor', value: total == null ? '—' : formatMoneyShort(total!)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.order,
    required this.busy,
    required this.onEdit,
    required this.onReject,
    required this.onApprove,
  });

  final ControlOrder order;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onReject;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final customer = order.customer;
    final age = DateTime.now().difference(order.createdAt);
    final ageLabel = age.inMinutes < 60
        ? 'hace ${age.inMinutes} min'
        : age.inHours < 24
        ? 'hace ${age.inHours} h'
        : formatShortDate(order.createdAt);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: order.failed ? _red.withValues(alpha: 0.4) : AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(order.numberLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          order.failed
                              ? const StatusPill(label: 'Error al subir', color: _red)
                              : const StatusPill(label: 'Por controlar', color: _blue),
                        ],
                      ),
                    ),
                    Text(ageLabel, style: const TextStyle(color: AppColors.textSoft, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  ['NIT ${customer.code}', if (customer.branch != null) customer.branch!].join(' · '),
                  style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                ),
                Text(
                  '${order.seller ?? 'Sin vendedor'}'
                  '${order.deliveryDate == null ? '' : ' · Entrega ${formatShortDate(order.deliveryDate!)}'}',
                  style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                ),
                if (order.company != null)
                  Text(
                    order.company!,
                    style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                if (order.failed && order.syncError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      order.syncError!,
                      style: const TextStyle(color: _red, fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(
                                '${formatQuantity(item.quantity)} ${item.unit ?? ''} × ${formatMoney(item.unitPrice)}',
                                style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatMoney(item.total),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 18, color: AppColors.border),
                Row(
                  children: [
                    Text(
                      '${order.items.length} ${order.items.length == 1 ? 'producto' : 'productos'}',
                      style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                    ),
                    const Spacer(),
                    Text(formatMoney(order.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: busy
                ? const SizedBox(height: 44, child: Center(child: CircularProgressIndicator()))
                : Row(
                    children: [
                      IconButton.outlined(tooltip: 'Editar', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _red,
                            side: const BorderSide(color: _red),
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: onReject,
                          child: const Text('Rechazar', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: onApprove,
                          child: Text(
                            order.failed ? 'Reintentar' : 'Aprobar',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.order});

  final ControlOrder order;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rechazar pedido ${widget.order.numberLabel}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.order.customer.name} · ${formatMoney(widget.order.total)}',
            style: const TextStyle(color: AppColors.textSoft),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              hintText: 'Ej.: no hay producto para despachar',
              alignLabelWithHint: true,
            ),
          ),
          const Text(
            'Se devuelve el inventario reservado y se notifica al vendedor.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red, minimumSize: const Size.fromHeight(50)),
            onPressed: () => Navigator.pop(context, _reason.text.trim()),
            child: const Text('Rechazar pedido', style: TextStyle(fontWeight: FontWeight.w800)),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
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

/// Ajusta las líneas del pedido con el catálogo de subproductos de la lista del cliente.
class SubproductEditScreen extends StatefulWidget {
  const SubproductEditScreen({super.key, required this.api, required this.company, required this.order});

  final ApiService api;
  final Company company;
  final ControlOrder order;

  @override
  State<SubproductEditScreen> createState() => _SubproductEditScreenState();
}

class _SubproductEditScreenState extends State<SubproductEditScreen> {
  late final Map<String, int> _cart = {for (final i in widget.order.items) i.sku: i.quantity.round()};
  late final Map<String, int> _original = Map.of(_cart);
  List<Product>? _products;
  String? _error;
  bool _pork = false;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _error = null);
    final priceList = widget.order.customer.priceList;
    if (priceList == null) {
      setState(() => _error = 'El cliente no tiene lista de precios.');
      return;
    }
    try {
      final products = await withWebSession(
        context,
        widget.api,
        () => widget.api.products(widget.company.id, priceList, type: 'subproducto'),
      );
      if (!mounted) return;
      if (products == null) {
        setState(() => _error = 'Se necesita confirmar la sesión para ver el catálogo.');
        return;
      }
      // Las líneas del pedido que ya no estén en el catálogo se conservan para poder ajustarlas.
      final missing = widget.order.items
          .where((i) => !products.any((p) => p.sku == i.sku))
          .map(
            (i) => Product(
              sku: i.sku,
              name: i.name,
              price: i.unitPrice,
              unit: i.unit,
              stock: 0,
              taxRate: 0,
              category: null,
            ),
          );
      setState(() => _products = [...products, ...missing]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Al editar, la web devuelve primero lo reservado por el pedido, así que también cuenta como disponible.
  double _available(Product p) => p.stock + (_original[p.sku] ?? 0);

  double get _total {
    final products = _products ?? const <Product>[];
    final lines = {for (final i in widget.order.items) i.sku: i};
    return _cart.entries.fold(0, (sum, e) {
      final price = products.where((p) => p.sku == e.key).firstOrNull?.price ?? lines[e.key]?.unitPrice ?? 0;
      return sum + price * e.value;
    });
  }

  bool get _changed => _cart.length != _original.length || _cart.entries.any((e) => _original[e.key] != e.value);

  String? get _problem {
    if (_cart.isEmpty) return 'El pedido debe tener al menos un producto.';
    final products = _products ?? const <Product>[];
    for (final e in _cart.entries) {
      final p = products.where((p) => p.sku == e.key).firstOrNull;
      if (p != null && e.value > _available(p)) return '${p.name} supera el disponible.';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final result = await withWebSession(
        context,
        widget.api,
        () => widget.api.updateControlOrder(widget.company.id, widget.order, Map.of(_cart)),
      );
      if (result != null && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final query = _query.trim().toLowerCase();
    final visible =
        (products ?? const <Product>[])
            .where((p) => p.isPork == _pork)
            .where((p) => query.isEmpty || p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query))
            .toList()
          ..sort((a, b) {
            final inA = _cart.containsKey(a.sku) ? 0 : 1;
            final inB = _cart.containsKey(b.sku) ? 0 : 1;
            return inA != inB ? inA - inB : a.name.compareTo(b.name);
          });
    final porkCount = _cart.keys.where((sku) => products?.any((p) => p.sku == sku && p.isPork) ?? false).length;
    final problem = _problem;

    return Scaffold(
      appBar: AppBar(
        title: Text('Editar ${widget.order.numberLabel}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_cart.length} ${_cart.length == 1 ? 'producto' : 'productos'} · total estimado',
                      style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                    ),
                  ),
                  Text(formatMoney(_total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ],
              ),
              if (problem != null && _changed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    problem,
                    style: const TextStyle(color: _red, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _saving || !_changed || problem != null ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.storefront_rounded, color: AppColors.primary),
              title: Text(
                widget.order.customer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Lista ${widget.order.customer.priceList ?? '—'} · precios según la lista del cliente'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text('Res (${_cart.length - porkCount})')),
                  ButtonSegment(value: true, label: Text('Cerdo ($porkCount)')),
                ],
                selected: {_pork},
                onSelectionChanged: (v) => setState(() => _pork = v.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar producto o referencia',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: TextButton(
                      onPressed: _loadProducts,
                      child: Text('$_error\nReintentar', textAlign: TextAlign.center),
                    ),
                  )
                : products == null
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                ? const Center(
                    child: Text('Sin productos.', style: TextStyle(color: AppColors.textSoft)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, i) {
                      final p = visible[i];
                      final qty = _cart[p.sku] ?? 0;
                      final available = _available(p);
                      final over = qty > available;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ref. ${p.sku} · ${formatMoney(p.price)}${p.unit == null ? '' : ' / ${p.unit}'}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                                  ),
                                  Text(
                                    available <= 0
                                        ? 'Sin stock'
                                        : 'Disponible ${formatQuantity(available)}${over ? ' · supera el disponible' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: available <= 0 || over ? _red : AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            QtyControl(
                              qty: qty,
                              enabled: available > 0 || qty > 0,
                              unit: p.unit,
                              onQty: (q) => setState(() => q <= 0 ? _cart.remove(p.sku) : _cart[p.sku] = q),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
