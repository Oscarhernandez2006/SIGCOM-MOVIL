import 'dart:async';

import 'package:flutter/material.dart';

import '../models/approval.dart';
import '../models/portfolio.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/status_pill.dart';
import '../widgets/web_session.dart';
import 'portfolio_screen.dart';

const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);
const _amber = Color(0xFFCA8A04);

/// Aprobación de cartera: pedidos retenidos por saldo del cliente (2 horas para decidir).
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  ApprovalsResult? _result;
  String? _error;
  bool _loading = false;
  final Set<String> _busy = {};
  Timer? _refresh;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // Igual que la web: refresca cada 30 s; el reloj avanza cada segundo para la cuenta regresiva.
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_result?.orders.isNotEmpty ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.approvals(widget.company.id);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime get _now => DateTime.now().add(_result?.clockOffset ?? Duration.zero);

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _approve(PendingApproval order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aprobar pedido ${order.numberLabel}'),
        content: Text(
          '${order.customer.name}\nTotal ${formatMoney(order.total)}\n\n'
          'El pedido se enviará a Siesa de inmediato.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _decide(order, () => widget.api.approveOrder(widget.company.id, order.id), (d) {
      if (d.status == 'failed') {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: _red, size: 36),
            title: const Text('Aprobado, pero Siesa no lo recibió'),
            content: Text(
              '${d.syncError ?? 'Siesa respondió con un error.'}\n\nEl pedido queda con estado Error; '
              'revísalo en Seguimiento de pedidos.',
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          ),
        );
      } else {
        _snack('Pedido ${order.numberLabel} aprobado y enviado a Siesa.');
      }
    });
  }

  Future<void> _disapprove(PendingApproval order) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _DisapproveSheet(order: order),
    );
    if (reason == null || !mounted) return;
    await _decide(
      order,
      () => widget.api.disapproveOrder(widget.company.id, order.id, reason.isEmpty ? null : reason),
      (_) => _snack('Pedido ${order.numberLabel} desaprobado. Se liberó el inventario reservado.'),
    );
  }

  Future<void> _decide(
    PendingApproval order,
    Future<ApprovalDecision> Function() action,
    void Function(ApprovalDecision) onDone,
  ) async {
    setState(() => _busy.add(order.id));
    try {
      final decision = await withWebSession(context, widget.api, action);
      if (decision == null || !mounted) return;
      setState(() => _result?.orders.removeWhere((o) => o.id == order.id));
      onDone(decision);
    } catch (e) {
      if (mounted) _snack(e.toString());
      _load();
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
    }
  }

  void _portfolio(PendingApproval order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PortfolioDetailScreen(
          api: widget.api,
          company: widget.company,
          user: widget.user,
          client: PortfolioClient(nit: order.customer.code, name: order.customer.name, branches: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final orders = result?.orders ?? const <PendingApproval>[];
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
                      count: result == null ? null : orders.length,
                      total: orders.fold<double>(0, (s, o) => s + o.total),
                      loading: _loading,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _Message(icon: Icons.cloud_off_rounded, text: _error!, onRetry: _load),
                    ],
                  ],
                ),
              ),
              if (result == null && _error == null)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (result != null && orders.isEmpty)
                const SliverToBoxAdapter(
                  child: _Message(
                    icon: Icons.verified_rounded,
                    text: 'No hay pedidos pendientes de aprobación.\nLa lista se actualiza sola cada 30 segundos.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final order = orders[i];
                      return _ApprovalCard(
                        order: order,
                        now: _now,
                        busy: _busy.contains(order.id),
                        onApprove: () => _approve(order),
                        onDisapprove: () => _disapprove(order),
                        onPortfolio: () => _portfolio(order),
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
  const _Header({required this.count, required this.total, required this.loading});

  final int? count;
  final double total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
                  'Aprobación de cartera',
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
            'Pedidos retenidos por saldo del cliente. Si no se deciden en 2 horas, vencen solos.',
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeaderStat(label: 'Pendientes', value: count == null ? '—' : formatInt(count!)),
              const SizedBox(width: 10),
              _HeaderStat(label: 'Valor retenido', value: count == null ? '—' : formatMoneyShort(total)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatefulWidget {
  const _ApprovalCard({
    required this.order,
    required this.now,
    required this.busy,
    required this.onApprove,
    required this.onDisapprove,
    required this.onPortfolio,
  });

  final PendingApproval order;
  final DateTime now;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDisapprove;
  final VoidCallback onPortfolio;

  @override
  State<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<_ApprovalCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final customer = order.customer;
    final balance = order.carteraBalance;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(order.numberLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if (order.type == 'subproducto') ...[
                      const SizedBox(width: 6),
                      const StatusPill(label: 'Subproducto', color: Color(0xFF7C3AED)),
                    ],
                    const Spacer(),
                    _Countdown(deadline: order.deadline, now: widget.now),
                  ],
                ),
                const SizedBox(height: 10),
                Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  [
                    'NIT ${customer.code}',
                    if (customer.branch != null) customer.branch!,
                    if (customer.paymentTerm != null) customer.paymentTerm!,
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.seller ?? 'Sin vendedor'} · ${formatTime(order.createdAt)}'
                  '${order.deliveryDate == null ? '' : ' · Entrega ${formatShortDate(order.deliveryDate!)}'}',
                  style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Amount(
                        label: 'Saldo en cartera',
                        value: balance == null || balance <= 0 ? 'Sin saldo' : formatMoney(balance),
                        color: balance != null && balance > 0 ? _red : AppColors.textSoft,
                      ),
                    ),
                    Expanded(
                      child: _Amount(label: 'Total del pedido', value: formatMoney(order.total), color: AppColors.text),
                    ),
                  ],
                ),
                if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    order.notes!,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${order.items.length} ${order.items.length == 1 ? 'producto' : 'productos'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
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
                ],
              ),
            ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: widget.busy
                ? const SizedBox(height: 44, child: Center(child: CircularProgressIndicator()))
                : Row(
                    children: [
                      IconButton.outlined(
                        tooltip: 'Ver cartera',
                        onPressed: widget.onPortfolio,
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _red,
                            side: const BorderSide(color: _red),
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: widget.onDisapprove,
                          child: const Text('Desaprobar', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: widget.onApprove,
                          child: const Text('Aprobar', style: TextStyle(fontWeight: FontWeight.w800)),
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

class _Countdown extends StatelessWidget {
  const _Countdown({required this.deadline, required this.now});

  final DateTime? deadline;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (deadline == null) return const SizedBox.shrink();
    final left = deadline!.difference(now);
    final expired = left.isNegative;
    final color = expired || left.inMinutes < 15 ? _red : (left.inMinutes < 45 ? _amber : _green);
    final mm = left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = left.inSeconds.remainder(60).toString().padLeft(2, '0');
    final text = expired ? 'Vencido' : '${left.inHours}:$mm:$ss';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSoft, fontSize: 12)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _DisapproveSheet extends StatefulWidget {
  const _DisapproveSheet({required this.order});

  final PendingApproval order;

  @override
  State<_DisapproveSheet> createState() => _DisapproveSheetState();
}

class _DisapproveSheetState extends State<_DisapproveSheet> {
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
            'Desaprobar pedido ${widget.order.numberLabel}',
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
              hintText: 'Ej.: el cliente tiene facturas vencidas',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'El vendedor será notificado y se liberará el inventario reservado.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red, minimumSize: const Size.fromHeight(50)),
            onPressed: () => Navigator.pop(context, _reason.text.trim()),
            child: const Text('Desaprobar pedido', style: TextStyle(fontWeight: FontWeight.w800)),
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
