import 'package:flutter/material.dart';

import '../models/ordering.dart';
import '../models/quote.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/order_widgets.dart';
import '../widgets/web_session.dart';
import 'quotes_screen.dart';

class NewQuoteScreen extends StatefulWidget {
  const NewQuoteScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  State<NewQuoteScreen> createState() => _NewQuoteScreenState();
}

class _NewQuoteScreenState extends State<NewQuoteScreen> {
  int _step = 0;
  OrderClient? _client;
  List<Product>? _products;
  String? _productsError;
  final Map<String, QuoteDraftLine> _lines = {};
  int _validityDays = 15;
  final _notes = TextEditingController();
  bool _saving = false;

  ApiService get _api => widget.api;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _selectClient(OrderClient client) async {
    if (client.priceList == null || client.priceList!.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Este cliente no tiene lista de precios; no se le puede cotizar.')));
      return;
    }
    final changed = _client?.id != client.id;
    setState(() {
      _client = client;
      _step = 1;
      if (changed) {
        _lines.clear();
        _products = null;
      }
    });
    if (changed || _products == null) await _loadProducts();
  }

  Future<void> _loadProducts() async {
    final client = _client;
    if (client == null) return;
    setState(() => _productsError = null);
    try {
      final products = await withWebSession(context, _api, () => _api.products(widget.company.id, client.priceList!));
      if (mounted && _client?.id == client.id) setState(() => _products = products ?? []);
    } catch (e) {
      if (mounted) setState(() => _productsError = e.toString());
    }
  }

  void _setQty(Product p, int qty) {
    setState(() {
      if (qty <= 0) {
        _lines.remove(p.sku);
      } else {
        (_lines[p.sku] ??= QuoteDraftLine(quantity: qty)).quantity = qty;
      }
    });
  }

  List<(Product, QuoteDraftLine)> get _selected {
    final bySku = {for (final p in _products ?? const <Product>[]) p.sku: p};
    return [
      for (final e in _lines.entries)
        if (bySku[e.key] != null) (bySku[e.key]!, e.value),
    ];
  }

  /// Igual que la web: descuento sobre el precio y el impuesto sobre el neto.
  ({double subtotal, double taxes, double total}) get _totals {
    var subtotal = 0.0;
    var taxes = 0.0;
    for (final (p, line) in _selected) {
      final net = p.price * line.quantity * (1 - line.discountPct / 100);
      subtotal += net;
      taxes += net * p.taxRate / 100;
    }
    return (subtotal: subtotal, taxes: taxes, total: subtotal + taxes);
  }

  Future<void> _editDiscount(Product p, QuoteDraftLine line) async {
    final text = await showNumberDialog(
      context,
      title: 'Descuento · ${p.name}',
      initial: line.discountPct == 0 ? '' : formatQuantity(line.discountPct),
      decimal: true,
      suffix: '%',
      confirmLabel: 'Aplicar',
    );
    if (text == null) return;
    final value = (double.tryParse(text.replaceAll(',', '.')) ?? 0).clamp(0, 100).toDouble();
    setState(() => line.discountPct = value);
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null || _lines.isEmpty) return;
    setState(() => _saving = true);
    try {
      final created = await withWebSession(
        context,
        _api,
        () => _api.createQuote(
          company: widget.company.id,
          customerId: client.id,
          lines: Map.of(_lines),
          validityDays: _validityDays,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ),
      );
      if (created == null || !mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 44),
          title: Text('Cotización ${created.number}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatMoney(created.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Para ${client.name}', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              QuoteActionsBar(
                api: _api,
                id: created.id,
                number: created.number,
                customerName: client.name,
                customerEmail: client.email,
                userEmail: widget.user['email'] as String?,
              ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Listo'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0 && _lines.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        if (_step > 0) {
          setState(() => _step--);
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            ['Cotizar a…', 'Productos', 'Resumen'][_step],
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: switch (_step) {
          0 => ClientPicker(api: _api, company: widget.company.id, selected: _client, onSelect: _selectClient),
          1 => _ProductsList(
            client: _client!,
            products: _products,
            error: _productsError,
            lines: _lines,
            onRetry: _loadProducts,
            onChangeClient: () => setState(() => _step = 0),
            onQty: _setQty,
          ),
          _ => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              FormSection(
                title: _client!.name,
                icon: Icons.request_quote_outlined,
                child: Column(
                  children: [
                    for (final (p, line) in _selected)
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
                                    formatMoney(p.price * line.quantity * (1 - line.discountPct / 100)),
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                                  ),
                                  InkWell(
                                    onTap: () => _editDiscount(p, line),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Text(
                                        line.discountPct > 0
                                            ? 'Dto. ${formatPercent(line.discountPct / 100)} · cambiar'
                                            : '+ Agregar descuento',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            QtyControl(qty: line.quantity, enabled: true, unit: p.unit, onQty: (q) => _setQty(p, q)),
                          ],
                        ),
                      ),
                    const Divider(height: 20, color: AppColors.border),
                    AmountRow('Subtotal', _totals.subtotal),
                    if (_totals.taxes > 0) AmountRow('Impuestos', _totals.taxes),
                    AmountRow('Total', _totals.total, bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FormSection(
                title: 'Vigencia y notas',
                icon: Icons.event_available_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final days in const [8, 15, 30])
                          ChoiceChip(
                            label: Text('$days días'),
                            selected: _validityDays == days,
                            onSelected: (_) => setState(() => _validityDays = days),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Válida hasta el ${formatDate(DateTime.now().add(Duration(days: _validityDays)))}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notes,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(hintText: 'Notas para el cliente (opcional)'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        },
        bottomNavigationBar: _step == 0 ? null : _bottomBar(),
      ),
    );
  }

  Widget _bottomBar() {
    final last = _step == 2;
    final count = _lines.length;
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
                      formatMoney(_totals.total),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(160, 50)),
              onPressed: count == 0 || _saving ? null : (last ? _save : () => setState(() => _step = 2)),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
              label: Text(_saving ? 'Creando…' : (last ? 'Crear cotización' : 'Continuar')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductsList extends StatefulWidget {
  const _ProductsList({
    required this.client,
    required this.products,
    required this.error,
    required this.lines,
    required this.onRetry,
    required this.onChangeClient,
    required this.onQty,
  });

  final OrderClient client;
  final List<Product>? products;
  final String? error;
  final Map<String, QuoteDraftLine> lines;
  final VoidCallback onRetry;
  final VoidCallback onChangeClient;
  final void Function(Product, int) onQty;

  @override
  State<_ProductsList> createState() => _ProductsListState();
}

class _ProductsListState extends State<_ProductsList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    final query = _query.trim().toLowerCase();
    final visible = (products ?? const <Product>[])
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query))
        .toList();

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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final p = visible[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  'Ref. ${p.sku} · ${formatMoney(p.price)}${p.unit == null ? '' : ' / ${p.unit}'}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          QtyControl(
                            qty: widget.lines[p.sku]?.quantity ?? 0,
                            enabled: true,
                            unit: p.unit,
                            onQty: (q) => widget.onQty(p, q),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
