import 'dart:async';

import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/range_sheet.dart';
import '../widgets/status_pill.dart';
import 'new_order_screen.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.api, required this.company, required this.user, this.tracking = false});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  /// Seguimiento de pedidos (Aprobación y control): todos los pedidos, solo consulta.
  final bool tracking;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

/// Mismos estados del filtro de la web (Administración de pedidos).
const _statusOptions = [
  'pending_approval',
  'pending_control',
  'confirmed',
  'synced',
  'bounced',
  'cancelled',
  'disapproved',
  'expired',
  'failed',
];

class _OrdersScreenState extends State<OrdersScreen> {
  late DateTimeRange _range;
  OrderGroup? _group;
  String? _status;
  String? _type;
  String _search = '';
  Timer? _debounce;
  OrdersResult? _result;
  bool _loading = false;
  String? _error;
  int _request = 0;

  bool get _isSeller => widget.user['role'] == 'seller';

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _range = DateTimeRange(start: DateTime(today.year, today.month), end: today);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.orders(
        company: widget.company.id,
        from: _range.start,
        to: _range.end,
        group: _group,
        search: _search,
        status: _status,
        type: _type,
      );
      if (mounted && request == _request) setState(() => _result = result);
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
      _load();
    });
  }

  Future<void> _pickRange() async {
    final range = await showRangeSheet(context, _range);
    if (range == null) return;
    setState(() => _range = range);
    _load();
  }

  void _selectGroup(OrderGroup? group) {
    if (group == _group && _status == null) return;
    setState(() {
      _group = group;
      _status = null;
    });
    _load();
  }

  Future<void> _pickStatus() async {
    final choice = await showModalBottomSheet<({String? status})>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text('Estado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final status in [null, ..._statusOptions])
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: status == null
                    ? const Icon(Icons.all_inclusive_rounded)
                    : Icon(Icons.circle, size: 14, color: OrderStatusStyle.of(status).color),
                title: Text(
                  status == null ? 'Todos los estados' : OrderStatusStyle.of(status).label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                selected: status == _status,
                selectedColor: AppColors.primary,
                selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                trailing: status == _status ? const Icon(Icons.check_circle_rounded) : null,
                onTap: () => Navigator.pop(context, (status: status)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice.status == _status) return;
    setState(() {
      _status = choice.status;
      _group = null;
    });
    _load();
  }

  void _selectType(String? type) {
    if (type == _type) return;
    setState(() => _type = type);
    _load();
  }

  void _open(OrderSummary order) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            OrderDetailScreen(api: widget.api, company: widget.company, summary: order, tracking: widget.tracking),
      ),
    );
    if (changed == true) _load();
  }

  void _newOrder() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewOrderScreen(api: widget.api, company: widget.company),
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.tracking
          ? null
          : FloatingActionButton.extended(
              onPressed: _newOrder,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Nuevo pedido', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: _buildList(result),
    );
  }

  Widget _buildList(OrdersResult? result) {
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList.list(
                  children: [
                    _Header(
                      title: widget.tracking ? 'Seguimiento de pedidos' : (_isSeller ? 'Mis pedidos' : 'Pedidos'),
                      rangeLabel: formatRangeLabel(_range),
                      loading: _loading,
                      onPickRange: _pickRange,
                      onSearch: _onSearch,
                    ),
                    const SizedBox(height: 14),
                    _GroupFilter(
                      summary: result?.summary,
                      selected: _status == null ? _group : null,
                      onSelect: _selectGroup,
                    ),
                    if (widget.tracking) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ActionChip(
                            avatar: Icon(
                              Icons.filter_list_rounded,
                              size: 18,
                              color: _status == null ? AppColors.textSoft : OrderStatusStyle.of(_status!).color,
                            ),
                            label: Text(_status == null ? 'Estado' : OrderStatusStyle.of(_status!).label),
                            backgroundColor: Colors.white,
                            onPressed: _pickStatus,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SegmentedButton<String?>(
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                backgroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: const [
                                ButtonSegment(value: null, label: Text('Todos')),
                                ButtonSegment(value: 'corte', label: Text('Cortes')),
                                ButtonSegment(value: 'subproducto', label: Text('Subprod.')),
                              ],
                              selected: {_type},
                              onSelectionChanged: (v) => _selectType(v.first),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_error != null) _Message(icon: Icons.cloud_off_rounded, text: _error!, onRetry: _load),
                  ],
                ),
              ),
              if (result == null && _loading)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (result != null && result.orders.isEmpty)
                const SliverToBoxAdapter(
                  child: _Message(icon: Icons.inbox_rounded, text: 'No hay pedidos con estos filtros.'),
                )
              else if (result != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: result.orders.length + (result.limited ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == result.orders.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Se muestran los pedidos más recientes. Acota el periodo o busca para ver otros.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSoft, fontSize: 12),
                          ),
                        );
                      }
                      final order = result.orders[i];
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _loading ? 0.55 : 1,
                        child: OrderCard(
                          order: order,
                          showSeller: !_isSeller,
                          showTracking: widget.tracking,
                          onTap: () => _open(order),
                        ),
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
  const _Header({
    required this.title,
    required this.rangeLabel,
    required this.loading,
    required this.onPickRange,
    required this.onSearch,
  });

  final String title;
  final String rangeLabel;
  final bool loading;
  final VoidCallback onPickRange;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onPickRange,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(rangeLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSoft),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  onChanged: onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cliente, NIT o # pedido',
                    isDense: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search_rounded),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupFilter extends StatelessWidget {
  const _GroupFilter({required this.summary, required this.selected, required this.onSelect});

  final Map<OrderGroup, OrderGroupTotals>? summary;
  final OrderGroup? selected;
  final ValueChanged<OrderGroup?> onSelect;

  static const _colors = {
    OrderGroup.inProgress: Color(0xFFEA580C),
    OrderGroup.synced: Color(0xFF16A34A),
    OrderGroup.issues: Color(0xFFDC2626),
    OrderGroup.cancelled: Color(0xFF64748B),
  };

  @override
  Widget build(BuildContext context) {
    final totals = summary;
    final allCount = totals?.values.fold<int>(0, (s, g) => s + g.count);
    final allTotal = totals?.values.fold<double>(0, (s, g) => s + g.total);

    Widget tile(OrderGroup? group, String label, Color color, int? count, double? total) {
      final active = group == selected;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSelect(group),
            child: Container(
              width: 128,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? color : AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: active ? Colors.white : color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    count == null ? '—' : formatInt(count),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : AppColors.text,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      total == null ? ' ' : formatMoneyShort(total),
                      style: TextStyle(fontSize: 12, color: active ? Colors.white70 : AppColors.textSoft),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          tile(null, 'Todos', AppColors.text, allCount, allTotal),
          for (final g in OrderGroup.values) tile(g, g.label, _colors[g]!, totals?[g]?.count, totals?[g]?.total),
        ],
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.showSeller,
    required this.onTap,
    this.showTracking = false,
  });

  final OrderSummary order;
  final bool showSeller;
  final bool showTracking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = OrderStatusStyle.of(order.status);
    final siesa = OrderStatusStyle.siesa(order.siesaStatus);
    final pendingApproval = order.status == 'pending_approval' && order.approvalDeadline != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: status.color,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(order.numberLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            if (order.type == 'subproducto') ...[
                              const SizedBox(width: 6),
                              const StatusPill(label: 'Subproducto', color: Color(0xFF7C3AED)),
                            ],
                            const Spacer(),
                            Text(
                              '${formatShortDate(order.createdAt)} · ${formatTime(order.createdAt)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          order.customer.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        Text(
                          [
                            order.customer.branch ?? order.customer.code,
                            if (showSeller && order.seller != null) order.seller!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  StatusPill(label: status.label, color: status.color),
                                  if (siesa != null) StatusPill(label: siesa.label, color: siesa.color, outlined: true),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatMoney(order.total),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                ),
                                Text(
                                  '${order.itemsCount} producto${order.itemsCount == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (pendingApproval) ...[
                          const SizedBox(height: 8),
                          _InlineNote(
                            icon: Icons.timer_outlined,
                            color: const Color(0xFFCA8A04),
                            text: 'Cartera decide antes de las ${formatTime(order.approvalDeadline!)}',
                          ),
                        ] else if (order.note != null && order.note!.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _InlineNote(icon: Icons.info_outline_rounded, color: status.color, text: order.note!),
                        ],
                        if (showTracking) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 14,
                            runSpacing: 4,
                            children: [
                              _TrackingTag(
                                icon: Icons.download_rounded,
                                active: order.downloadCount > 0,
                                text: order.downloadCount > 0
                                    ? 'Descargado ${order.downloadCount} ${order.downloadCount == 1 ? 'vez' : 'veces'}'
                                    : 'Sin descargar',
                              ),
                              if (order.linkedNumber != null)
                                _TrackingTag(
                                  icon: Icons.link_rounded,
                                  active: true,
                                  text: 'Asociado a ${order.linkedNumber}',
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingTag extends StatelessWidget {
  const _TrackingTag({required this.icon, required this.active, required this.text});

  final IconData icon;
  final bool active;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSoft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 44, color: AppColors.textSoft),
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
