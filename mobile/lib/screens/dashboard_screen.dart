import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/range_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    required this.company,
    required this.user,
    this.national = false,
  });

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  /// Tablero de Negocios Nacionales: vendedor fijo y presupuesto por tienda.
  final bool national;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _from;
  late DateTime _to;
  SellerRef? _seller;
  DashboardData? _data;
  bool _loading = false;
  String? _error;
  int _request = 0;

  bool get _isSeller => widget.user['role'] == 'seller';

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _from = DateTime(today.year, today.month);
    _to = today;
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.dashboard(
        company: widget.company.id,
        from: _from,
        to: _to,
        sellerId: _seller?.id,
        national: widget.national,
      );
      if (mounted && request == _request) setState(() => _data = data);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _pickSeller() async {
    final sellers = _data?.sellers ?? const <SellerRef>[];
    final choice = await showModalBottomSheet<_SellerChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _SellerSheet(sellers: sellers, selectedId: _seller?.id),
    );
    if (choice == null) return;
    setState(() => _seller = choice.seller);
    _load();
  }

  Future<void> _pickRange() async {
    final range = await showRangeSheet(context, DateTimeRange(start: _from, end: _to));
    if (range == null) return;
    setState(() {
      _from = range.start;
      _to = range.end;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Stack(
      children: [
        const BrandBackground(),
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Hero(
                title: widget.national ? 'Negocios Nacionales' : 'Tablero de Gestión Comercial',
                sellerLabel: widget.national
                    ? data?.seller?.name
                    : _seller?.name ?? (_isSeller ? widget.user['name'] as String? ?? '' : null),
                generatedAt: data?.generatedAt,
                from: _from,
                to: _to,
                showSellerFilter: !_isSeller && !widget.national,
                loading: _loading,
                onPickSeller: _pickSeller,
                onPickRange: _pickRange,
                onRefresh: _load,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[_ErrorCard(message: _error!, onRetry: _load), const SizedBox(height: 16)],
              if (data == null)
                _loading ? const _SkeletonGrid() : const SizedBox.shrink()
              else
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _loading ? 0.55 : 1,
                  child: _DashboardBody(data: data, showProfitability: !_isSeller),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data, required this.showProfitability});

  final DashboardData data;
  final bool showProfitability;

  @override
  Widget build(BuildContext context) {
    final sales = data.sales;
    final projection = data.projection;
    final profitability = data.profitability;
    final daysNote = data.workingDaysTotal > 0
        ? 'Base: ${data.workingDaysElapsed} de ${data.workingDaysTotal} días hábiles'
        : null;
    final missingSales = sales == null ? (data.salesError != null ? 'Error SIESA' : 'Pendiente SIESA') : null;

    final cards = <Widget>[
      _KpiCard(
        title: 'Ppto mes',
        value: formatMoney(data.budget.revenue ?? 0),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF3B82F6),
        metrics: [_Metric(data.unit.label, data.unit.format(data.budget.kilos ?? 0))],
      ),
      _KpiCard(
        title: 'Proyección',
        value: projection?.revenue == null ? null : formatMoney(projection!.revenue!),
        emptyLabel: missingSales ?? 'No aplica',
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF8B5CF6),
        metrics: [_Metric(data.unit.label, projection?.kilos == null ? null : data.unit.format(projection!.kilos!))],
        footnote: daysNote,
      ),
      _KpiCard(
        title: 'Pedidos',
        value: formatInt(data.ordersCount),
        icon: Icons.assignment_outlined,
        color: const Color(0xFF6366F1),
        metrics: [
          _Metric('Pesos', formatMoney(data.ordersRevenue)),
          _Metric(data.unit.label, data.unit.format(data.ordersKilos)),
        ],
      ),
      _KpiCard(
        title: 'Ticket promedio',
        value: formatMoney(data.ordersAvgTicket),
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF0891B2),
        metrics: [_Metric('Clientes atendidos', formatInt(data.ordersCustomers))],
      ),
      if (showProfitability)
        _KpiCard(
          title: 'Rentabilidad',
          value: profitability == null ? null : formatMoney(profitability.margin),
          emptyLabel: missingSales ?? 'Sin costos',
          icon: Icons.savings_outlined,
          color: const Color(0xFF14B8A6),
          metrics: [
            _Metric('Margen', profitability?.marginPct == null ? null : formatPercent(profitability!.marginPct!)),
            _Metric('Costo', profitability == null ? null : formatMoney(profitability.cost)),
          ],
        ),
    ];

    final sections = <Widget>[
      if (data.salesError != null) _NoticeCard(message: data.salesError!),
      _SalesCard(data: data, missingLabel: missingSales),
      _ComplianceCard(data: data, missingLabel: missingSales),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 3 : (constraints.maxWidth >= 340 ? 2 : 1);
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (i, card) in cards.indexed)
                SizedBox(
                  width: columns > 1 && i == cards.length - 1 && cards.length % columns == 1
                      ? constraints.maxWidth
                      : width,
                  child: card,
                ),
            ],
          );
        },
      ),
      if (data.trend.isNotEmpty) _TrendCard(data: data),
      if (data.categories.isNotEmpty) _CategoriesCard(categories: data.categories, unit: data.unit),
      if (data.clientBudgets != null)
        _ClientBudgetsCard(rows: data.clientBudgets!)
      else
        _CustomersCard(buying: data.topCustomers, notBuying: data.customersNotBuying),
    ];

    return Column(
      children: [
        for (final (i, section) in sections.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FadeSlideIn(
              delay: Duration(milliseconds: 50 * i),
              child: section,
            ),
          ),
      ],
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.data, required this.missingLabel});

  final DashboardData data;
  final String? missingLabel;

  @override
  Widget build(BuildContext context) {
    final sales = data.sales;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBadge(icon: Icons.attach_money_rounded, color: Color(0xFF10B981)),
              const SizedBox(width: 12),
              const Expanded(child: _SectionLabel('Ventas acumuladas')),
              if (missingLabel != null) _PendingChip(label: missingLabel!),
            ],
          ),
          if (data.salesFromOrders)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Según los pedidos tomados en la app (sin facturación de Siesa para esta compañía).',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSoft),
              ),
            ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              sales?.revenue == null ? '—' : formatMoney(sales!.revenue!),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: sales == null ? AppColors.textSoft : AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: data.unit.soldLabel,
                  child: _StatText(sales?.kilos == null ? '—' : data.unit.format(sales!.kilos!)),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Crec. pesos',
                  child: _GrowthChip(ratio: data.growth?.revenue),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Crec. ${data.unit.word}',
                  child: _GrowthChip(ratio: data.growth?.kilos),
                ),
              ),
            ],
          ),
          if (data.growth != null) ...[
            const SizedBox(height: 10),
            const Text(
              'Crecimiento vs. periodo anterior de igual duración',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSoft,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text),
      ),
    );
  }
}

class _GrowthChip extends StatelessWidget {
  const _GrowthChip({required this.ratio});

  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final value = ratio;
    if (value == null) return const _StatText('—');
    final up = value >= 0;
    final color = up ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: color),
            const SizedBox(width: 2),
            Text(
              formatPercent(value.abs()),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textMuted),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$message Se muestran solo los datos de pedidos.',
              style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.data});

  final DashboardData data;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _selected;

  @override
  void didUpdateWidget(covariant _TrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _selected = null;
  }

  void _select(double dx, double width) {
    final count = widget.data.trend.length;
    if (count == 0) return;
    final index = count == 1 ? 0 : (dx / width * (count - 1)).round().clamp(0, count - 1);
    if (index != _selected) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.data.trend;
    final budget = widget.data.budget.revenue ?? 0;
    final days = widget.data.workingDaysTotal;
    final goal = budget > 0 && days > 0 ? budget / days : null;
    final lastWithSales = points.lastIndexWhere((p) => p.revenue != 0);
    final selected = _selected ?? (lastWithSales >= 0 ? lastWithSales : points.length - 1);
    final point = points[selected];
    final total = points.fold<double>(0, (sum, p) => sum + p.revenue);
    final activeDays = points.where((p) => p.revenue != 0).length;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _IconBadge(icon: Icons.show_chart_rounded, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(child: _SectionLabel('Tendencia de ventas diarias')),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            formatDayLabel(point.date),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatMoney(point.revenue),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                ),
              ),
              if (goal != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${formatPercent(point.revenue / goal)} de la meta',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: point.revenue >= goal ? AppColors.primary : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _select(d.localPosition.dx, constraints.maxWidth),
                onHorizontalDragUpdate: (d) => _select(d.localPosition.dx, constraints.maxWidth),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(
                    size: Size.infinite,
                    painter: TrendChartPainter(
                      values: [for (final p in points) p.revenue],
                      selected: selected,
                      goal: goal,
                      progress: t,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(formatShortDate(points.first.date), style: const TextStyle(fontSize: 11, color: AppColors.textSoft)),
              const Spacer(),
              Text(formatShortDate(points.last.date), style: const TextStyle(fontSize: 11, color: AppColors.textSoft)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              const _Legend(color: AppColors.primary, label: 'Venta diaria'),
              if (goal != null)
                _Legend(color: const Color(0xFFF59E0B), label: 'Meta diaria ${formatMoneyShort(goal)}', dashed: true),
              _Legend(
                color: AppColors.textSoft,
                label: 'Promedio ${formatMoneyShort(activeDays > 0 ? total / activeDays : 0)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Container(width: 4, height: 3, margin: const EdgeInsets.only(right: 2), color: color),
            ],
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

const _categoryColors = {'Cortes': AppColors.primary, 'Canales': Color(0xFFB91C1C), 'Subproductos': Color(0xFFF59E0B)};

Color _categoryColor(String name) => _categoryColors[name] ?? const Color(0xFF64748B);

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.categories, required this.unit});

  final List<SalesCategory> categories;
  final QtyUnit unit;

  @override
  Widget build(BuildContext context) {
    final total = categories.fold<double>(0, (sum, c) => sum + c.revenue);
    final totalKilos = categories.fold<double>(0, (sum, c) => sum + c.kilos);
    final withSales = categories.where((c) => c.revenue > 0).toList();

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _IconBadge(icon: Icons.donut_small_rounded, color: Color(0xFFB91C1C)),
              SizedBox(width: 12),
              Expanded(child: _SectionLabel('Ventas por categoría')),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: total <= 0
                  ? Container(color: AppColors.field)
                  : Row(
                      children: [
                        for (final c in withSales)
                          Expanded(
                            flex: (c.revenue / total * 1000).round().clamp(1, 1000),
                            child: Container(color: _categoryColor(c.name)),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          for (final c in categories)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: c.items.isEmpty ? null : () => _openCategory(context, c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _categoryColor(c.name),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(
                              '${c.items.length} ítem${c.items.length == 1 ? '' : 's'} · ${unit.format(c.kilos)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMoney(c.revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                            total > 0 ? formatPercent(c.revenue / total) : '—',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: c.items.isEmpty ? Colors.transparent : AppColors.textSoft,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Divider(height: 16, color: AppColors.border),
          Row(
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(unit.format(totalKilos), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
              ),
              Text(formatMoney(total), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 28),
            ],
          ),
        ],
      ),
    );
  }

  void _openCategory(BuildContext context, SalesCategory category) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _CategorySheet(category: category, unit: unit),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.category, required this.unit});

  final SalesCategory category;
  final QtyUnit unit;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final color = _categoryColor(category.name);
    final query = _query.toLowerCase();
    final items = category.items
        .where((i) => i.name.toLowerCase().contains(query) || (i.ref ?? '').contains(query))
        .toList();
    final top = category.items.isEmpty ? 0.0 : category.items.first.revenue;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(category.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '${formatMoney(category.revenue)} · ${widget.unit.format(category.kilos)} · ${category.items.length} ítems',
              style: const TextStyle(color: AppColors.textSoft, fontWeight: FontWeight.w600),
            ),
          ),
          if (category.items.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Buscar producto', prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final item = items[i];
                final share = category.revenue != 0 ? item.revenue / category.revenue : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  'Ref. ${item.ref ?? '—'} · ${widget.unit.format(item.kilos)}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatMoney(item.revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(
                                formatPercent(share),
                                style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: top > 0 ? (item.revenue / top).clamp(0, 1) : 0,
                          minHeight: 5,
                          backgroundColor: AppColors.field,
                          color: color,
                        ),
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

/// Meta vs. venta por cliente/tienda (negocios nacionales), como en la web.
class _ClientBudgetsCard extends StatelessWidget {
  const _ClientBudgetsCard({required this.rows});

  final List<ClientBudget> rows;

  /// Mismos umbrales de color que la web: ≥100 %, ≥70 %, ≥40 % y menor.
  static Color _complianceColor(double ratio) => ratio >= 1
      ? AppColors.primary
      : ratio >= 0.7
      ? const Color(0xFF059669)
      : ratio >= 0.4
      ? const Color(0xFFD97706)
      : const Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a, b) => b.revenue.compareTo(a.revenue));
    final target = rows.fold<double>(0, (s, r) => s + r.targetRevenue);
    final revenue = rows.fold<double>(0, (s, r) => s + r.revenue);

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _IconBadge(icon: Icons.storefront_rounded, color: Color(0xFF3B82F6)),
              SizedBox(width: 12),
              Expanded(child: _SectionLabel('Presupuesto por tienda / cliente')),
            ],
          ),
          const SizedBox(height: 12),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Sin clientes asignados.', style: TextStyle(color: AppColors.textSoft)),
              ),
            ),
          for (final r in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              [r.code, if (r.branch != null && r.branch != r.name) r.branch!].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.compliance == null ? '—' : formatPercent(r.compliance!),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: r.compliance == null ? AppColors.textSoft : _complianceColor(r.compliance!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Venta ${formatMoney(r.revenue)}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        r.targetRevenue > 0 ? 'Meta ${formatMoney(r.targetRevenue)}' : 'Sin meta',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                      ),
                    ],
                  ),
                  if (r.compliance != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: r.compliance!.clamp(0, 1).toDouble(),
                        minHeight: 6,
                        backgroundColor: AppColors.field,
                        color: _complianceColor(r.compliance!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const Divider(height: 20, color: AppColors.border),
          Row(
            children: [
              const Expanded(
                child: Text('Total (aparte del general)', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMoney(revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('Meta ${formatMoney(target)}', style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomersCard extends StatefulWidget {
  const _CustomersCard({required this.buying, required this.notBuying});

  final List<CustomerSummary> buying;
  final List<CustomerSummary> notBuying;

  @override
  State<_CustomersCard> createState() => _CustomersCardState();
}

class _CustomersCardState extends State<_CustomersCard> {
  static const _pageSize = 20;

  bool _showBuying = true;
  String _query = '';
  int _visible = _pageSize;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _showBuying ? widget.buying : widget.notBuying;
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty ? source : source.where((c) => c.matches(query)).toList();
    final shown = filtered.take(_visible).toList();
    final accent = _showBuying ? AppColors.primary : const Color(0xFFB45309);

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _IconBadge(icon: Icons.storefront_rounded, color: Color(0xFF6366F1)),
              SizedBox(width: 12),
              Expanded(child: _SectionLabel('Mis clientes / tiendas')),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: accent,
                selectedForegroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              segments: [
                ButtonSegment(value: true, label: Text('Compran (${widget.buying.length})')),
                ButtonSegment(value: false, label: Text('No compran (${widget.notBuying.length})')),
              ],
              selected: {_showBuying},
              onSelectionChanged: (v) => setState(() {
                _showBuying = v.first;
                _visible = _pageSize;
              }),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar cliente, tienda, NIT o ciudad',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                        _visible = _pageSize;
                        FocusScope.of(context).unfocus();
                      }),
                    ),
            ),
            controller: _search,
            onChanged: (v) => setState(() {
              _query = v;
              _visible = _pageSize;
            }),
          ),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  query.isNotEmpty
                      ? 'Sin coincidencias para la búsqueda.'
                      : (_showBuying ? 'Sin ventas en el periodo.' : 'Todos tus clientes compraron.'),
                  style: const TextStyle(color: AppColors.textSoft),
                ),
              ),
            ),
          for (final (i, c) in shown.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: accent.withValues(alpha: 0.1),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            c.branch ?? c.city ?? 'Sin tienda',
                            if (_showBuying) '${c.orders} pedido${c.orders == 1 ? '' : 's'}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _showBuying
                        ? [
                            Text(formatMoney(c.revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                            if (c.lastPurchase != null)
                              Text(
                                formatShortDate(c.lastPurchase!),
                                style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                              ),
                          ]
                        : [
                            const Text('Última compra', style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
                            Text(
                              c.lastPurchase == null ? 'Nunca' : formatShortDate(c.lastPurchase!),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          if (filtered.length > shown.length)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _visible += _pageSize),
                icon: const Icon(Icons.expand_more_rounded),
                label: Text('Ver más (${filtered.length - shown.length} restantes)'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.title,
    required this.sellerLabel,
    required this.generatedAt,
    required this.from,
    required this.to,
    required this.showSellerFilter,
    required this.loading,
    required this.onPickSeller,
    required this.onPickRange,
    required this.onRefresh,
  });

  final String title;
  final String? sellerLabel;
  final DateTime? generatedAt;
  final DateTime from;
  final DateTime to;
  final bool showSellerFilter;
  final bool loading;
  final VoidCallback onPickSeller;
  final VoidCallback onPickRange;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final sameYear = from.year == to.year;
    final rangeLabel = from == to
        ? formatShortDate(from)
        : '${formatShortDate(from)} – ${formatShortDate(to)}${sameYear ? '' : ' ${to.year}'}';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F6B35), AppColors.primary, Color(0xFF34B868)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          Positioned(
            right: 50,
            bottom: -70,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: loading ? null : onRefresh,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        disabledBackgroundColor: Colors.white.withValues(alpha: 0.16),
                      ),
                      icon: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  sellerLabel == null ? 'Vendedor: General · Todos los vendedores' : 'Vendedor: $sellerLabel',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontWeight: FontWeight.w600),
                ),
                if (generatedAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Última actualización: ${formatDateTime(generatedAt!)}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (showSellerFilter)
                      _HeroChip(
                        icon: Icons.person_outline_rounded,
                        label: sellerLabel ?? 'Todos (general)',
                        onTap: onPickSeller,
                      ),
                    _HeroChip(icon: Icons.calendar_today_rounded, label: rangeLabel, onTap: onPickRange),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 13),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComplianceCard extends StatelessWidget {
  const _ComplianceCard({required this.data, required this.missingLabel});

  final DashboardData data;
  final String? missingLabel;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFF59E0B);
    final pace = data.workingDaysTotal > 0 ? data.workingDaysElapsed / data.workingDaysTotal : null;
    final compliance = data.compliance;
    final sales = data.sales;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBadge(icon: Icons.speed_rounded, color: color),
              const SizedBox(width: 12),
              const Expanded(child: _SectionLabel('Cumplimiento')),
              if (missingLabel != null) _PendingChip(label: missingLabel!),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ComplianceRing(
                  label: 'Pesos',
                  ratio: compliance?.revenue,
                  pace: pace,
                  detail: sales?.revenue == null ? null : formatMoneyShort(sales!.revenue!),
                  target: formatMoneyShort(data.budget.revenue ?? 0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ComplianceRing(
                  label: data.unit.label,
                  ratio: compliance?.kilos,
                  pace: pace,
                  detail: sales?.kilos == null ? null : data.unit.format(sales!.kilos!.roundToDouble()),
                  target: data.unit.format(data.budget.kilos ?? 0),
                ),
              ),
            ],
          ),
          if (pace != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Container(width: 3, height: 14, color: AppColors.text),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Meta a la fecha: ${formatPercent(pace)} · día hábil ${data.workingDaysElapsed} de ${data.workingDaysTotal}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComplianceRing extends StatelessWidget {
  const _ComplianceRing({
    required this.label,
    required this.ratio,
    required this.pace,
    required this.detail,
    required this.target,
  });

  final String label;
  final double? ratio;
  final double? pace;
  final String? detail;
  final String target;

  @override
  Widget build(BuildContext context) {
    final value = ratio;
    final onTrack = value != null && (pace == null || value >= pace!);
    final color = value == null ? AppColors.border : (onTrack ? AppColors.primary : const Color(0xFFF59E0B));

    return Column(
      children: [
        SizedBox(
          width: 124,
          height: 124,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value ?? 0),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(
              painter: RingGaugePainter(progress: t, pace: pace, color: color, track: AppColors.field),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value == null ? '—' : formatPercent(t),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: value == null ? AppColors.textSoft : AppColors.text,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(detail ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('de $target', style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String? value;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.metrics = const [],
    this.footnote,
    this.emptyLabel = 'Pendiente SIESA',
  });

  final String title;
  final String? value;
  final IconData icon;
  final Color color;
  final List<_Metric> metrics;
  final String? footnote;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final pending = value == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (pending)
            _PendingChip(label: emptyLabel)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.text,
                ),
              ),
            ),
          for (final metric in metrics) ...[
            const SizedBox(height: 8),
            Text(
              metric.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.textSoft,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                metric.value ?? '—',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: metric.value == null ? AppColors.textSoft : AppColors.text,
                ),
              ),
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Text(footnote!, style: const TextStyle(fontSize: 10.5, color: AppColors.textSoft)),
          ],
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip({this.label = 'Pendiente SIESA'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync_problem_rounded, size: 13, color: Color(0xFFB45309)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return _CardShell(
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: error, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid();

  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(8)),
    );

    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_controller),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _CardShell(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bar(120, 12),
                          const SizedBox(height: 12),
                          bar(200, 24),
                          const SizedBox(height: 16),
                          bar(160, 12),
                        ],
                      ),
                    ),
                    bar(46, 46),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SellerChoice {
  const _SellerChoice(this.seller);

  final SellerRef? seller;
}

class _SellerSheet extends StatefulWidget {
  const _SellerSheet({required this.sellers, required this.selectedId});

  final List<SellerRef> sellers;
  final String? selectedId;

  @override
  State<_SellerSheet> createState() => _SellerSheetState();
}

class _SellerSheetState extends State<_SellerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final filtered = widget.sellers.where((s) => s.name.toLowerCase().contains(query)).toList();

    Widget option(SellerRef? seller) {
      final selected = seller?.id == widget.selectedId;
      return ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
        selectedColor: AppColors.primary,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: seller == null
              ? const Icon(Icons.groups_rounded, size: 20, color: AppColors.primary)
              : Text(
                  seller.name[0],
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
        ),
        title: Text(seller?.name ?? 'Todos (general)', style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
        onTap: () => Navigator.pop(context, _SellerChoice(seller)),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Vendedor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar vendedor', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [if (query.isEmpty) option(null), for (final seller in filtered) option(seller)],
            ),
          ),
        ],
      ),
    );
  }
}
