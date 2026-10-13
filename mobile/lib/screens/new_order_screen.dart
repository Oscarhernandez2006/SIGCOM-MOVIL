import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/order.dart';
import '../models/ordering.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/order_widgets.dart';
import '../widgets/status_pill.dart';
import '../widgets/web_session.dart';

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key, required this.api, required this.company});

  final ApiService api;
  final Company company;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  int _step = 0;
  OrderingContext? _context;
  String? _contextError;

  OrderClient? _client;
  List<Product>? _products;
  String? _productsError;
  final Map<String, int> _cart = {};

  String _deliveryType = 'despacho';
  DateTime? _deliveryDate;
  DeliverySchedule? _schedule;
  final _notes = TextEditingController();
  final _logisticsNote = TextEditingController();

  /// Misma clave en reintentos: la web devuelve el pedido ya creado en vez de duplicarlo.
  String _idempotencyKey = _newKey();
  bool _submitting = false;

  ApiService get _api => widget.api;
  String get _company => widget.company.id;

  static String _newKey() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContext());
  }

  @override
  void dispose() {
    _notes.dispose();
    _logisticsNote.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() => _contextError = null);
    try {
      final ctx = await withWebSession(context, _api, () => _api.orderingContext(_company));
      if (!mounted) return;
      if (ctx == null) {
        Navigator.pop(context);
        return;
      }
      setState(() => _context = ctx);
    } catch (e) {
      if (mounted) setState(() => _contextError = e.toString());
    }
  }

  Future<void> _selectClient(OrderClient client) async {
    if (client.priceList == null || client.priceList!.trim().isEmpty) {
      _snack('Este cliente no tiene lista de precios asignada; no se le puede vender.');
      return;
    }
    final changed = _client?.id != client.id;
    setState(() {
      _client = client;
      _step = 1;
      if (changed) {
        _cart.clear();
        _products = null;
        _schedule = client.deliverySchedule;
        _idempotencyKey = _newKey();
      }
    });
    if (changed || _products == null) await _loadProducts();
  }

  Future<void> _loadProducts() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _products = null;
      _productsError = null;
    });
    try {
      final products = await withWebSession(context, _api, () => _api.products(_company, client.priceList!));
      if (mounted && _client?.id == client.id) setState(() => _products = products ?? []);
    } catch (e) {
      if (mounted) setState(() => _productsError = e.toString());
    }
  }

  void _setQty(Product product, int qty) {
    setState(() {
      if (qty <= 0) {
        _cart.remove(product.sku);
      } else {
        _cart[product.sku] = qty;
      }
    });
  }

  List<(Product, int)> get _lines {
    final bySku = {for (final p in _products ?? const <Product>[]) p.sku: p};
    return [
      for (final e in _cart.entries)
        if (bySku[e.key] != null) (bySku[e.key]!, e.value),
    ];
  }

  ({double subtotal, double taxes, double total}) get _totals {
    var subtotal = 0.0;
    var taxes = 0.0;
    for (final (p, qty) in _lines) {
      final line = p.price * qty;
      subtotal += line;
      taxes += line * p.taxRate / 100;
    }
    return (subtotal: subtotal, taxes: taxes, total: subtotal + taxes);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final client = _client;
    final ctx = _context;
    if (client == null || ctx == null || _cart.isEmpty) return;
    if (!ctx.isOpen) {
      _snack('Fuera del horario de toma de pedidos (${ctx.open} a ${ctx.close}).');
      return;
    }
    if (_deliveryDate == null) {
      _snack('Selecciona la fecha de entrega del pedido.');
      return;
    }

    setState(() => _submitting = true);
    try {
      // 1. Segundo pedido del día: preguntar si se asocia al anterior (igual que la web).
      final today = await withWebSession(context, _api, () => _api.clientTodayOrders(_company, client.id));
      if (today == null || !mounted) return;
      String? linkedOrderId;
      if (today.isNotEmpty) {
        final choice = await showDialog<_LinkChoice>(
          context: context,
          builder: (_) => _LinkDialog(orders: today),
        );
        if (choice == null) return;
        linkedOrderId = choice.orderId;
      }

      // 2. Aviso de productos estrella no incluidos (se puede continuar).
      final missing = ctx.featured.where((f) => !_cart.containsKey(f.sku)).toList();
      if (missing.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => _FeaturedDialog(missing: missing),
        );
        if (proceed != true) return;
      }

      // 3. Ubicación del cliente digitada por el vendedor (obligatoria en Agropecuaria y Carnes Frías).
      if (ctx.requiresLocation && mounted) {
        final location = await withWebSession(context, _api, () => _api.clientLocation(_company, client.id));
        if (!mounted) return;
        if (location == null) {
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            backgroundColor: Colors.white,
            builder: (_) => _LocationSheet(api: _api, company: _company, client: client),
          );
          if (saved != true) return;
        }
      }

      // 4. Confirmación final.
      if (!mounted) return;
      final totals = _totals;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('¿Enviar el pedido?'),
          content: Text(
            '${client.name}\n${_cart.length} producto${_cart.length == 1 ? '' : 's'} · ${formatMoney(totals.total)}\n'
            'Entrega: ${formatDate(_deliveryDate!)}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final draft = OrderDraft(
        customerId: client.id,
        deliveryDate: _deliveryDate!,
        deliveryType: _deliveryType,
        items: Map.of(_cart),
        idempotencyKey: _idempotencyKey,
        schedule: _schedule,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        logisticsNote: _logisticsNote.text.trim().isEmpty ? null : _logisticsNote.text.trim(),
        linkedOrderId: linkedOrderId,
      );
      final result = await withWebSession(context, _api, () => _api.createOrder(_company, draft));
      if (result == null || !mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ResultDialog(result: result),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 36),
            title: const Text('No se pudo crear el pedido'),
            content: Text('$e\n\nSi reintentas no se duplicará: el sistema reconoce este mismo pedido.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmExit() async {
    if (_cart.isEmpty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Salir sin enviar?'),
        content: const Text('Se perderán los productos agregados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _context;
    return PopScope(
      canPop: _cart.isEmpty && _step == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _submitting) return;
        if (_step > 0) {
          setState(() => _step--);
          return;
        }
        if (await _confirmExit() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nuevo pedido', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: _StepBar(step: _step),
          ),
        ),
        body: ctx == null
            ? Center(
                child: _contextError == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_contextError!, textAlign: TextAlign.center),
                            TextButton(onPressed: _loadContext, child: const Text('Reintentar')),
                          ],
                        ),
                      ),
              )
            : Column(
                children: [
                  if (!ctx.isOpen) _ClosedBanner(ctx: ctx),
                  Expanded(
                    child: switch (_step) {
                      0 => ClientPicker(api: _api, company: _company, selected: _client, onSelect: _selectClient),
                      1 => _ProductsStep(
                        client: _client!,
                        products: _products,
                        error: _productsError,
                        cart: _cart,
                        onRetry: _loadProducts,
                        onChangeClient: () => setState(() => _step = 0),
                        onQty: _setQty,
                      ),
                      _ => _DeliveryStep(
                        client: _client!,
                        lines: _lines,
                        totals: _totals,
                        minTotal: ctx.minTotal,
                        deliveryType: _deliveryType,
                        deliveryDate: _deliveryDate,
                        schedule: _schedule,
                        notes: _notes,
                        logisticsNote: _logisticsNote,
                        onQty: _setQty,
                        onDeliveryType: (v) => setState(() => _deliveryType = v),
                        onDeliveryDate: (v) => setState(() => _deliveryDate = v),
                        onSchedule: (v) => setState(() => _schedule = v),
                      ),
                    },
                  ),
                ],
              ),
        bottomNavigationBar: ctx != null && _step > 0 ? _bottomBar(ctx) : null,
      ),
    );
  }

  Widget _bottomBar(OrderingContext ctx) {
    final totals = _totals;
    final count = _cart.length;
    final isLast = _step == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count producto${count == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(totals.total),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(150, 50)),
              onPressed: count == 0 || _submitting || (isLast && !ctx.isOpen)
                  ? null
                  : (isLast ? _submit : () => setState(() => _step = 2)),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(isLast ? Icons.send_rounded : Icons.arrow_forward_rounded),
              label: Text(_submitting ? 'Enviando…' : (isLast ? 'Enviar pedido' : 'Continuar')),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Cliente', 'Productos', 'Entrega'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed) ...[
            if (i > 0) Expanded(child: Container(height: 2, color: i <= step ? AppColors.primary : AppColors.border)),
            CircleAvatar(
              radius: 12,
              backgroundColor: i <= step ? AppColors.primary : AppColors.field,
              child: i < step
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: i <= step ? Colors.white : AppColors.textSoft,
                      ),
                    ),
            ),
            if (i == step) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.text),
              ),
            ],
            if (i < labels.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.ctx});

  final OrderingContext ctx;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF3C7),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fuera del horario de toma de pedidos (${DeliverySchedule.hour12(ctx.open)} a ${DeliverySchedule.hour12(ctx.close)}). '
              'Puedes armar el pedido pero no enviarlo.',
              style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Paso 2

class _ProductsStep extends StatefulWidget {
  const _ProductsStep({
    required this.client,
    required this.products,
    required this.error,
    required this.cart,
    required this.onRetry,
    required this.onChangeClient,
    required this.onQty,
  });

  final OrderClient client;
  final List<Product>? products;
  final String? error;
  final Map<String, int> cart;
  final VoidCallback onRetry;
  final VoidCallback onChangeClient;
  final void Function(Product, int) onQty;

  @override
  State<_ProductsStep> createState() => _ProductsStepState();
}

class _ProductsStepState extends State<_ProductsStep> {
  bool _pork = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    final query = _query.trim().toLowerCase();
    final visible = (products ?? const <Product>[])
        .where((p) => p.isPork == _pork)
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query))
        .toList();
    final porkCount = widget.cart.keys.where((sku) => products?.any((p) => p.sku == sku && p.isPork) ?? false).length;
    // Carnes Frías no maneja cerdo/res: sin productos de cerdo no se muestra el selector.
    final hasPork = products?.any((p) => p.isPork) ?? false;

    return Column(
      children: [
        Material(
          color: Colors.white,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.storefront_rounded, color: AppColors.primary),
            title: Text(
              widget.client.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('Lista ${widget.client.priceListName ?? widget.client.priceList}'),
            trailing: TextButton(onPressed: widget.onChangeClient, child: const Text('Cambiar')),
          ),
        ),
        if (hasPork)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text('Res (${widget.cart.length - porkCount})')),
                  ButtonSegment(value: true, label: Text('Cerdo ($porkCount)')),
                ],
                selected: {_pork},
                onSelectionChanged: (v) => setState(() => _pork = v.first),
              ),
            ),
          )
        else
          const SizedBox(height: 6),
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
          child: widget.error != null
              ? Center(
                  child: TextButton(
                    onPressed: widget.onRetry,
                    child: Text('${widget.error}\nReintentar', textAlign: TextAlign.center),
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
                  itemBuilder: (context, i) => _ProductRow(
                    product: visible[i],
                    qty: widget.cart[visible[i].sku] ?? 0,
                    onQty: (q) => widget.onQty(visible[i], q),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.qty, required this.onQty});

  final Product product;
  final int qty;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final noStock = product.stock <= 0;
    final overStock = qty > product.stock && !noStock;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'Ref. ${product.sku} · ${formatMoney(product.price)}${product.unit == null ? '' : ' / ${product.unit}'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  noStock
                      ? 'Sin stock'
                      : 'Stock ${formatQuantity(product.stock)}${overStock ? ' · supera el disponible' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: noStock || overStock ? const Color(0xFFDC2626) : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          QtyControl(qty: qty, enabled: !noStock || qty > 0, onQty: onQty, unit: product.unit),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Paso 3

class _DeliveryStep extends StatelessWidget {
  const _DeliveryStep({
    required this.client,
    required this.lines,
    required this.totals,
    required this.minTotal,
    required this.deliveryType,
    required this.deliveryDate,
    required this.schedule,
    required this.notes,
    required this.logisticsNote,
    required this.onQty,
    required this.onDeliveryType,
    required this.onDeliveryDate,
    required this.onSchedule,
  });

  final OrderClient client;
  final List<(Product, int)> lines;
  final ({double subtotal, double taxes, double total}) totals;
  final double minTotal;
  final String deliveryType;
  final DateTime? deliveryDate;
  final DeliverySchedule? schedule;
  final TextEditingController notes;
  final TextEditingController logisticsNote;
  final void Function(Product, int) onQty;
  final ValueChanged<String> onDeliveryType;
  final ValueChanged<DateTime> onDeliveryDate;
  final ValueChanged<DeliverySchedule?> onSchedule;

  Future<void> _pickDate(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 60)),
      initialDate: deliveryDate ?? today.add(const Duration(days: 1)),
      helpText: 'Fecha de entrega',
    );
    if (picked != null) onDeliveryDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final belowMin = minTotal > 0 && totals.total < minTotal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        FormSection(
          title: 'Resumen · ${client.name}',
          icon: Icons.shopping_basket_outlined,
          child: Column(
            children: [
              for (final (p, qty) in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            Text(
                              formatMoney(p.price * qty),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                            ),
                          ],
                        ),
                      ),
                      QtyControl(qty: qty, enabled: true, unit: p.unit, onQty: (q) => onQty(p, q)),
                    ],
                  ),
                ),
              const Divider(height: 20, color: AppColors.border),
              AmountRow('Subtotal', totals.subtotal),
              if (totals.taxes > 0) AmountRow('Impuestos', totals.taxes),
              AmountRow('Total', totals.total, bold: true),
              if (belowMin) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    'El pedido mínimo es ${formatMoney(minTotal)}. Si el cliente ya tiene un pedido hoy, no aplica.',
                    style: const TextStyle(color: Color(0xFF92400E), fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        FormSection(
          title: 'Entrega',
          icon: Icons.local_shipping_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'despacho', label: Text('Despacho'), icon: Icon(Icons.local_shipping_rounded)),
                    ButtonSegment(
                      value: 'recoge_en_planta',
                      label: Text('Recoge en planta'),
                      icon: Icon(Icons.factory_rounded),
                    ),
                  ],
                  selected: {deliveryType},
                  onSelectionChanged: (v) => onDeliveryType(v.first),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded, color: AppColors.primary),
                title: const Text('Fecha de entrega *', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  deliveryDate == null ? 'Selecciona una fecha' : formatDayLabel(deliveryDate!),
                  style: TextStyle(color: deliveryDate == null ? const Color(0xFFDC2626) : AppColors.text),
                ),
                trailing: const Icon(Icons.edit_calendar_rounded),
                onTap: () => _pickDate(context),
              ),
              const Divider(color: AppColors.border),
              _ScheduleEditor(schedule: schedule, onChanged: onSchedule),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FormSection(
          title: 'Notas',
          icon: Icons.sticky_note_2_outlined,
          child: Column(
            children: [
              TextField(
                controller: notes,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(hintText: 'Nota del pedido (opcional)'),
              ),
              TextField(
                controller: logisticsNote,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Nota logística: ruta, instrucciones de entrega… (opcional)',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleEditor extends StatelessWidget {
  const _ScheduleEditor({required this.schedule, required this.onChanged});

  final DeliverySchedule? schedule;
  final ValueChanged<DeliverySchedule?> onChanged;

  static const _short = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  Future<void> _pickHour(BuildContext context, bool from) async {
    final current = schedule ?? const DeliverySchedule(days: {}, hourFrom: '07:00', hourTo: '17:00');
    final value = from ? current.hourFrom : current.hourTo;
    final parts = value.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    onChanged(from ? current.copyWith(hourFrom: text) : current.copyWith(hourTo: text));
  }

  @override
  Widget build(BuildContext context) {
    final current = schedule ?? const DeliverySchedule(days: {}, hourFrom: '07:00', hourTo: '17:00');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Horario de recibido del cliente', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          current.isComplete ? current.label : 'Opcional · queda guardado para los próximos pedidos',
          style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          children: [
            for (var d = 0; d < 7; d++)
              FilterChip(
                label: Text(_short[d]),
                showCheckmark: false,
                selected: current.days.contains(d),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: current.days.contains(d) ? Colors.white : AppColors.text,
                ),
                onSelected: (on) {
                  final days = {...current.days};
                  on ? days.add(d) : days.remove(d);
                  onChanged(days.isEmpty ? null : current.copyWith(days: days));
                },
              ),
          ],
        ),
        if (current.isComplete)
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _pickHour(context, true),
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text('Desde ${DeliverySchedule.hour12(current.hourFrom)}'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _pickHour(context, false),
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text('Hasta ${DeliverySchedule.hour12(current.hourTo)}'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Diálogos

class _LinkChoice {
  const _LinkChoice(this.orderId);

  final String? orderId;
}

class _LinkDialog extends StatelessWidget {
  const _LinkDialog({required this.orders});

  final List<TodayOrder> orders;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('El cliente ya pidió hoy'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Este pedido completa uno anterior (p. ej. un producto que faltó)? Elige el pedido para asociarlo.',
          ),
          const SizedBox(height: 8),
          for (final o in orders)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_rounded, color: AppColors.primary),
              title: Text('Pedido #${o.number}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(formatMoney(o.total)),
              onTap: () => Navigator.pop(context, _LinkChoice(o.id)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, const _LinkChoice(null)), child: const Text('No asociar')),
      ],
    );
  }
}

class _FeaturedDialog extends StatelessWidget {
  const _FeaturedDialog({required this.missing});

  final List<({String sku, String name})> missing;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 36),
      title: const Text('Productos estrella sin incluir'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recuerda ofrecerle al cliente:'),
          const SizedBox(height: 8),
          for (final f in missing.take(8)) Text('• ${f.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Agregar productos')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar así')),
      ],
    );
  }
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.api, required this.company, required this.client});

  final ApiService api;
  final String company;
  final OrderClient client;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  final _form = GlobalKey<FormState>();
  late final _direccion = TextEditingController(text: widget.client.address);
  final _barrio = TextEditingController();
  late final _ciudad = TextEditingController(text: widget.client.city);
  final _referencia = TextEditingController();
  late final _telefono = TextEditingController(text: widget.client.phone);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_direccion, _barrio, _ciudad, _referencia, _telefono]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final location = ClientLocation(
        direccion: _direccion.text.trim(),
        barrio: _barrio.text.trim(),
        ciudad: _ciudad.text.trim(),
        referencia: opt(_referencia),
        telefono: opt(_telefono),
      );
      final ok = await withWebSession(
        context,
        widget.api,
        () => widget.api.saveClientLocation(widget.company, widget.client.id, location).then((_) => true),
      );
      if (ok == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ubicación del cliente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Antes del primer pedido de ${widget.client.name} debes registrar dónde se entrega. Solo se pide una vez.',
                style: const TextStyle(color: AppColors.textSoft),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _direccion,
                validator: required,
                decoration: const InputDecoration(labelText: 'Dirección *'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _barrio,
                validator: required,
                decoration: const InputDecoration(labelText: 'Barrio *'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ciudad,
                validator: required,
                decoration: const InputDecoration(labelText: 'Ciudad *'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _referencia,
                decoration: const InputDecoration(labelText: 'Punto de referencia'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar y continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.result});

  final OrderResult result;

  @override
  Widget build(BuildContext context) {
    final style = OrderStatusStyle.of(result.status);
    final failed = result.status == 'failed';
    final number = result.secondNumber == null ? '#${result.number}' : '#${result.number} / #${result.secondNumber}';
    final message = switch (result.status) {
      'synced' => 'El pedido se envió a Siesa correctamente.',
      'pending_approval' =>
        'Quedó pendiente de aprobación de cartera (tiene hasta 2 horas). Se enviará a Siesa al aprobarse.',
      'pending_control' => 'Quedó esperando la aprobación del controlador.',
      'failed' =>
        'El pedido se creó pero Siesa lo rechazó: ${result.syncError ?? 'sin detalle'}. Revísalo en la web para reintentarlo.',
      _ => 'El pedido quedó registrado.',
    };
    return AlertDialog(
      icon: Icon(
        failed ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
        color: failed ? const Color(0xFFDC2626) : AppColors.primary,
        size: 44,
      ),
      title: Text('Pedido $number'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(label: style.label, color: style.color),
          const SizedBox(height: 12),
          Text(formatMoney(result.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
    );
  }
}
