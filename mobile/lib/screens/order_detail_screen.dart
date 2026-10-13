import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/status_pill.dart';
import '../widgets/web_session.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.api,
    required this.company,
    required this.summary,
    this.tracking = false,
  });

  final ApiService api;
  final Company company;
  final OrderSummary summary;

  /// Vista de seguimiento: muestra la trazabilidad y no permite anular (como la web).
  final bool tracking;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

/// Motivos frecuentes, iguales a los de la web.
const _cancelReasons = [
  'El cliente canceló el pedido',
  'Error al digitar el pedido',
  'Producto sin disponibilidad',
  'El cliente no recibe en este momento',
  'Pedido duplicado',
  'Cambio en la lista de precios',
];

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<OrderDetail> _future = widget.api.order(widget.summary.id);
  bool _changed = false;
  bool _cancelling = false;

  bool _canCancel(String status) => !widget.tracking && status != 'cancelled' && status != 'synced';

  Future<void> _cancel() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => const _CancelSheet(),
    );
    if (reason == null || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final result = await withWebSession(
        context,
        widget.api,
        () => widget.api.cancelOrder(widget.company.id, widget.summary.id, reason),
      );
      if (result == null || !mounted) return;
      _changed = true;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido anulado.')));
      setState(() => _future = widget.api.order(widget.summary.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Pedido ${summary.numberLabel}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        bottomNavigationBar: FutureBuilder<OrderDetail>(
          future: _future,
          builder: (context, snapshot) {
            final status = snapshot.data?.summary.status;
            if (status == null || !_canCancel(status)) return const SizedBox.shrink();
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _cancelling ? null : _cancel,
                  icon: _cancelling
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.block_rounded),
                  label: const Text('Anular pedido', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            );
          },
        ),
        body: FutureBuilder<OrderDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(snapshot.error.toString(), textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () => setState(() => _future = widget.api.order(summary.id)),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final detail = snapshot.data;
            if (detail == null) return const Center(child: CircularProgressIndicator());
            return _DetailBody(detail: detail, tracking: widget.tracking);
          },
        ),
      ),
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  String? _selected;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _reason => _selected == 'Otro' ? (_other.text.trim().isEmpty ? null : _other.text.trim()) : _selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('Motivo de la anulación', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v),
              child: Column(
                children: [
                  for (final r in [..._cancelReasons, 'Otro'])
                    RadioListTile<String>(value: r, title: Text(r), dense: true),
                ],
              ),
            ),
            if (_selected == 'Otro')
              TextField(
                controller: _other,
                autofocus: true,
                maxLength: 500,
                decoration: const InputDecoration(hintText: 'Describe el motivo'),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: _reason == null ? null : () => Navigator.pop(context, _reason),
              child: const Text('Anular pedido'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, required this.tracking});

  final OrderDetail detail;
  final bool tracking;

  @override
  Widget build(BuildContext context) {
    final order = detail.summary;
    final customer = order.customer;
    final status = OrderStatusStyle.of(order.status);
    final siesa = OrderStatusStyle.siesa(order.siesaStatus);
    final t = detail.tracking;
    String? when(DateTime? d) => d == null ? null : '${formatDate(d)} · ${formatTime(d)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusPill(label: status.label, color: status.color),
                  if (siesa != null) StatusPill(label: siesa.label, color: siesa.color, outlined: true),
                  if (order.type == 'subproducto') const StatusPill(label: 'Subproducto', color: Color(0xFF7C3AED)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                formatMoney(order.total),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6),
              ),
              Text(
                'Creado el ${formatDate(order.createdAt)} a las ${formatTime(order.createdAt)}'
                '${order.seller == null ? '' : ' · ${order.seller}'}',
                style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
              ),
              if (order.note != null && order.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    order.note!,
                    style: TextStyle(color: status.color, fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (tracking && t != null) ...[
          _Card(
            title: 'Generación del pedido',
            icon: Icons.person_outline_rounded,
            child: Column(
              children: [
                _Field('Vendedor', order.seller),
                _Field('Documento', t.sellerDocument),
                _Field('Código vendedor', t.sellerCode),
                _Field('Creado', when(order.createdAt)),
                _Field('Asociado al pedido', t.linkedNumber),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Cartera (aprobación)',
            icon: Icons.account_balance_wallet_outlined,
            child: Column(
              children: [
                _Field(
                  'Saldo al crear',
                  t.carteraBalance == null ? 'Sin cartera pendiente' : formatMoney(t.carteraBalance!),
                ),
                _Field('Límite de aprobación', when(order.approvalDeadline)),
                _Field('Aprobado por', t.approvedBy),
                _Field('Aprobado el', when(t.approvedAt)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Estado en Siesa',
            icon: Icons.sync_alt_rounded,
            child: Column(
              children: [
                _Field('Estado actual', order.siesaStatus),
                _Field('Estado anterior', t.siesaPreviousStatus),
                _Field('Enviado a Siesa', when(detail.syncedAt)),
                _Field('Documento Siesa', t.siesaDocument),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Descargas del documento',
            icon: Icons.download_rounded,
            child: Column(
              children: [
                _Field('Veces descargado', '${t.downloadCount}'),
                _Field('Última descarga', when(t.downloadedAt)),
                _Field('Descargado por', t.downloadedBy),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _Card(
          title: 'Cliente',
          icon: Icons.storefront_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 8),
              _Field('NIT / código', customer.code),
              _Field('Tienda', customer.branch),
              _Field('Lista de precios', customer.priceList),
              _Field('Condición de pago', customer.paymentTerm),
              _Field('Dirección', [customer.address, customer.city].whereType<String>().join(', ')),
              _Field('Teléfono', customer.phone),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Entrega',
          icon: Icons.local_shipping_outlined,
          child: Column(
            children: [
              _Field('Modalidad', detail.deliveryType == 'recoge_en_planta' ? 'Recoge en planta' : 'Despacho'),
              _Field('Fecha de entrega', order.deliveryDate == null ? null : formatDate(order.deliveryDate!)),
              _Field('Horario de recibido', detail.deliverySchedule),
              _Field('Nota logística', detail.logisticsNote),
              _Field('Notas del pedido', detail.notes),
              _Field(
                'Enviado a Siesa',
                detail.syncedAt == null ? null : '${formatDate(detail.syncedAt!)} · ${formatTime(detail.syncedAt!)}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: 'Productos (${detail.items.length})',
          icon: Icons.inventory_2_outlined,
          child: Column(
            children: [
              for (final (i, item) in detail.items.indexed) ...[
                if (i > 0) const Divider(height: 20, color: AppColors.border),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            'Ref. ${item.sku} · ${formatQuantity(item.quantity)} ${item.unit ?? ''}'
                            ' × ${formatMoney(item.unitPrice)}'
                            '${item.discountPct > 0 ? ' · Dto. ${formatPercent(item.discountPct / 100)}' : ''}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(formatMoney(item.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
              const Divider(height: 24, color: AppColors.border),
              _TotalRow('Subtotal', detail.subtotal),
              _TotalRow('Impuestos', detail.taxes),
              _TotalRow('Total', order.total, bold: true),
            ],
          ),
        ),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
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
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: bold ? 16 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(formatMoney(value), style: style),
        ],
      ),
    );
  }
}
