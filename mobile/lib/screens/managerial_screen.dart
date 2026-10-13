import 'package:flutter/material.dart';

import '../models/managerial.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/range_sheet.dart';
import '../widgets/web_session.dart';

/// Mismos colores por compañía que el panel web.
Color companyAccent(String id) => switch (id) {
  '8' => const Color(0xFFF59E0B),
  '4' => const Color(0xFFF43F5E),
  _ => const Color(0xFF10B981),
};

const _ordersBlue = Color(0xFF3B82F6);

/// Panel de control gerencial (General → Dashboard en la web): comparativo de
/// compañías, detalle por compañía y venta vs. pedido por vendedor.
class ManagerialScreen extends StatefulWidget {
  const ManagerialScreen({super.key, required this.api, required this.company});

  final ApiService api;
  final Company company;

  @override
  State<ManagerialScreen> createState() => _ManagerialScreenState();
}

class _ManagerialScreenState extends State<ManagerialScreen> {
  late DateTimeRange _range;
  List<CompanyStats>? _companies;
  String? _selectedId;
  String? _error;
  bool _loading = false;
  int _request = 0;

  ApiService get _api => widget.api;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _range = DateTimeRange(start: DateTime(today.year, today.month), end: today);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companies = await withWebSession(
        context,
        _api,
        () => _api.managerial(widget.company.id, _range.start, _range.end),
      );
      if (!mounted || request != _request || companies == null) return;
      setState(() {
        _companies = companies;
        if (!companies.any((c) => c.id == _selectedId)) {
          _selectedId = companies.isEmpty ? null : companies.first.id;
        }
      });
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final range = await showRangeSheet(context, _range);
    if (range == null) return;
    setState(() => _range = range);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final companies = _companies;
    final selected = companies?.where((c) => c.id == _selectedId).firstOrNull;

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
              _Header(
                rangeLabel: formatRangeLabel(_range),
                loading: _loading,
                onPickRange: _pickRange,
                onRefresh: _load,
              ),
              const SizedBox(height: 14),
              if (_error != null)
                _Card(
                  child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      TextButton(onPressed: _load, child: const Text('Reintentar')),
                    ],
                  ),
                )
              else if (companies == null)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (companies.isEmpty)
                const _Card(child: Center(child: Text('Sin datos en el rango seleccionado.')))
              else
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _loading ? 0.55 : 1,
                  child: Column(
                    children: [
                      _RevenueByCompany(companies: companies),
                      const SizedBox(height: 14),
                      _CompanyTabs(
                        companies: companies,
                        selectedId: _selectedId,
                        onSelect: (id) => setState(() => _selectedId = id),
                      ),
                      if (selected != null) ...[const SizedBox(height: 12), _CompanyDetail(company: selected)],
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              _SellersRankingCard(api: _api, company: widget.company.id),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.rangeLabel, required this.loading, required this.onPickRange, required this.onRefresh});

  final String rangeLabel;
  final bool loading;
  final VoidCallback onPickRange;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F6B35), AppColors.primary, Color(0xFF34B868)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Panel de control',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
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
          Text(
            'Comparativa por compañía',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onPickRange,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(rangeLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSoft),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title, this.icon, this.iconColor});

  final Widget child;
  final String? title;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
                Icon(icon, size: 18, color: iconColor ?? AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title!.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
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

class _RevenueByCompany extends StatelessWidget {
  const _RevenueByCompany({required this.companies});

  final List<CompanyStats> companies;

  @override
  Widget build(BuildContext context) {
    final total = companies.fold<double>(0, (s, c) => s + c.sales);
    final max = companies.fold<double>(1, (m, c) => c.sales > m ? c.sales : m);
    return _Card(
      title: 'Ingresos por compañía',
      icon: Icons.bar_chart_rounded,
      child: Column(
        children: [
          for (final c in companies) ...[
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: companyAccent(c.id), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                Text(
                  formatMoney(c.sales),
                  style: TextStyle(fontWeight: FontWeight.w800, color: companyAccent(c.id)),
                ),
                const SizedBox(width: 6),
                Text(
                  total > 0 ? formatPercent(c.sales / total) : '—',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _Bar(value: c.sales / max, color: companyAccent(c.id), height: 9),
            const SizedBox(height: 14),
          ],
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Total general',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(formatMoney(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, this.height = 6});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.isFinite ? value.clamp(0, 1).toDouble() : 0,
        minHeight: height,
        backgroundColor: AppColors.field,
        color: color,
      ),
    );
  }
}

class _CompanyTabs extends StatelessWidget {
  const _CompanyTabs({required this.companies, required this.selectedId, required this.onSelect});

  final List<CompanyStats> companies;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in companies)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  Icons.apartment_rounded,
                  size: 18,
                  color: c.id == selectedId ? Colors.white : companyAccent(c.id),
                ),
                label: Text(c.name),
                selected: c.id == selectedId,
                showCheckmark: false,
                selectedColor: companyAccent(c.id),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: c.id == selectedId ? Colors.white : AppColors.text,
                ),
                onSelected: (_) => onSelect(c.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompanyDetail extends StatelessWidget {
  const _CompanyDetail({required this.company});

  final CompanyStats company;

  @override
  Widget build(BuildContext context) {
    final accent = companyAccent(company.id);
    final m = company.margin;
    final kpis = <(String, String, IconData)>[
      if (m != null) ('Margen ${formatPercent(m.marginPct / 100)}', formatMoney(m.profit), Icons.trending_up_rounded),
      ('Pedidos', formatInt(company.orders), Icons.shopping_cart_outlined),
      if (m != null)
        (company.unit.label, company.unit.format(m.kilos.roundToDouble()), Icons.scale_outlined)
      else ...[
        ('Ticket promedio', formatMoney(company.avgTicket), Icons.receipt_long_outlined),
        ('Unidades', formatQuantity(company.units), Icons.inventory_2_outlined),
      ],
      ('Clientes', formatInt(company.customers), Icons.people_outline_rounded),
    ];

    return Column(
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.apartment_rounded, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Compañía ${company.id}', style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
                        Text(company.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'VENTAS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSoft),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMoney(company.sales),
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: accent, letterSpacing: -0.6),
                ),
              ),
              if (m != null)
                const Text('Facturación real del ERP', style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.3,
                children: [
                  for (final (label, value, icon) in kpis)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 14, color: AppColors.textSoft),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSoft),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SellersCard(company: company),
        const SizedBox(height: 12),
        _ProductsCard(company: company),
        if (company.trend.isNotEmpty) ...[const SizedBox(height: 12), _TrendCard(company: company)],
        const SizedBox(height: 12),
        _Card(
          title: 'Clientes que más pidieron',
          icon: Icons.people_alt_outlined,
          iconColor: accent,
          child: _RankList(
            items: company.topCustomers,
            color: accent,
            showBar: false,
            subtitle: (c) => '${c.code ?? ''} · ${c.orders ?? 0} pedido(s)',
            empty: 'Sin ventas en el rango.',
          ),
        ),
      ],
    );
  }
}

class _SellersCard extends StatefulWidget {
  const _SellersCard({required this.company});

  final CompanyStats company;

  @override
  State<_SellersCard> createState() => _SellersCardState();
}

class _SellersCardState extends State<_SellersCard> {
  bool _billed = true;

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    final accent = companyAccent(company.id);
    final m = company.margin;
    if (m == null) {
      return _Card(
        title: 'Ventas por vendedor',
        icon: Icons.badge_outlined,
        iconColor: accent,
        child: _RankList(
          items: company.topSellers,
          color: accent,
          subtitle: (s) => '${s.orders ?? 0} pedido(s)',
          empty: 'Sin ventas en el rango.',
        ),
      );
    }
    return _Card(
      title: 'Facturado vs. pedido por vendedor',
      icon: Icons.badge_outlined,
      iconColor: accent,
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Facturado (ERP)')),
                ButtonSegment(value: false, label: Text('Pedido (app)')),
              ],
              selected: {_billed},
              onSelectionChanged: (v) => setState(() => _billed = v.first),
            ),
          ),
          const SizedBox(height: 12),
          _billed
              ? _RankList(
                  items: m.bySeller,
                  color: accent,
                  subtitle: (s) =>
                      'Margen ${formatMoney(s.profit ?? 0)} · ${formatPercent((s.marginPct ?? 0) / 100)} · '
                      '${company.unit.format((s.kilos ?? 0).roundToDouble())}',
                  empty: 'Sin ventas en el rango.',
                )
              : _RankList(
                  items: company.topSellers,
                  color: _ordersBlue,
                  subtitle: (s) => '${s.orders ?? 0} pedido(s)',
                  empty: 'Sin pedidos en el rango.',
                ),
        ],
      ),
    );
  }
}

class _ProductsCard extends StatelessWidget {
  const _ProductsCard({required this.company});

  final CompanyStats company;

  @override
  Widget build(BuildContext context) {
    final accent = companyAccent(company.id);
    final m = company.margin;
    if (m != null) {
      return _Card(
        title: 'Ventas y margen por producto',
        icon: Icons.emoji_events_outlined,
        iconColor: const Color(0xFFF59E0B),
        child: _RankList(
          items: m.byProduct,
          color: accent,
          subtitle: (p) => 'Margen ${formatMoney(p.profit ?? 0)} · ${formatPercent((p.marginPct ?? 0) / 100)}',
          empty: 'Sin ventas en el rango.',
        ),
      );
    }
    return _Card(
      title: 'Productos más vendidos',
      icon: Icons.emoji_events_outlined,
      iconColor: const Color(0xFFF59E0B),
      child: _RankList(
        items: company.topProducts,
        color: accent,
        barBy: (p) => p.quantity ?? 0,
        subtitle: (p) => '${formatQuantity(p.quantity ?? 0)} und.',
        empty: 'Sin ventas en el rango.',
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.company});

  final CompanyStats company;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _selected;

  @override
  void didUpdateWidget(covariant _TrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company != widget.company) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.company.trend;
    final accent = companyAccent(widget.company.id);
    final selected = (_selected ?? points.lastIndexWhere((p) => p.revenue != 0)).clamp(0, points.length - 1);
    final point = points[selected];
    final hourly = point.label != null;

    void select(double dx, double width) {
      final i = points.length == 1 ? 0 : (dx / width * (points.length - 1)).round().clamp(0, points.length - 1);
      if (i != _selected) setState(() => _selected = i);
    }

    return _Card(
      title: 'Tendencia de ventas',
      icon: Icons.show_chart_rounded,
      iconColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hourly ? 'A las ${point.label}' : formatDayLabel(point.date),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft, fontWeight: FontWeight.w600),
          ),
          Text(formatMoney(point.revenue), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => select(d.localPosition.dx, constraints.maxWidth),
                onHorizontalDragUpdate: (d) => select(d.localPosition.dx, constraints.maxWidth),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: TrendChartPainter(
                    values: [for (final p in points) p.revenue],
                    selected: selected,
                    goal: null,
                    progress: 1,
                    color: accent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                hourly ? points.first.label ?? '' : formatShortDate(points.first.date),
                style: const TextStyle(fontSize: 11, color: AppColors.textSoft),
              ),
              const Spacer(),
              Text(
                hourly ? points.last.label ?? '' : formatShortDate(points.last.date),
                style: const TextStyle(fontSize: 11, color: AppColors.textSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lista ordenada con barra proporcional; muestra 10 y permite ver el resto.
class _RankList extends StatefulWidget {
  const _RankList({
    super.key,
    required this.items,
    required this.color,
    required this.subtitle,
    required this.empty,
    this.barBy,
    this.showBar = true,
  });

  final List<RankItem> items;
  final Color color;
  final String Function(RankItem) subtitle;
  final String empty;
  final double Function(RankItem)? barBy;
  final bool showBar;

  @override
  State<_RankList> createState() => _RankListState();
}

class _RankListState extends State<_RankList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(widget.empty, style: const TextStyle(color: AppColors.textSoft)),
        ),
      );
    }
    final barValue = widget.barBy ?? (RankItem i) => i.revenue;
    final max = items.fold<double>(1, (m, i) => barValue(i) > m ? barValue(i) : m);
    final shown = _all ? items : items.take(10).toList();

    return Column(
      children: [
        for (final (i, item) in shown.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textSoft),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          Text(
                            widget.subtitle(item),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(item.revenue),
                      style: TextStyle(fontWeight: FontWeight.w800, color: widget.color, fontSize: 13.5),
                    ),
                  ],
                ),
                if (widget.showBar) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: _Bar(value: barValue(item) / max, color: widget.color),
                  ),
                ],
              ],
            ),
          ),
        if (items.length > 10)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Ver menos' : 'Ver todos (${items.length})'),
          ),
      ],
    );
  }
}

/// Venta (ERP) vs. pedido (app) del mes o de un día, por vendedor.
class _SellersRankingCard extends StatefulWidget {
  const _SellersRankingCard({required this.api, required this.company});

  final ApiService api;
  final String company;

  @override
  State<_SellersRankingCard> createState() => _SellersRankingCardState();
}

class _SellersRankingCardState extends State<_SellersRankingCard> with AutomaticKeepAliveClientMixin {
  late DateTime _month;
  DateTime? _day;
  SellersRanking? _data;
  String? _error;
  bool _loading = false;
  bool _billed = true;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await withWebSession(
        context,
        widget.api,
        () => widget.api.sellersRanking(widget.company, _month, day: _day),
      );
      if (mounted && request == _request && data != null) setState(() => _data = data);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _day = null;
    });
    _load();
  }

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      initialDate: _day ?? today,
      helpText: 'Día a consultar',
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      _month = DateTime(picked.year, picked.month);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;
    final data = _data;
    final monthLabel = formatMonth(_month);

    return _Card(
      title: _day == null ? 'Venta vs. pedido del mes por vendedor' : 'Venta vs. pedido del día por vendedor',
      icon: Icons.leaderboard_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _loading ? null : () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              IconButton(
                onPressed: _loading || isCurrentMonth ? null : () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.event_rounded, size: 18),
                label: Text(_day == null ? 'Elegir un día' : formatDayLabel(_day!)),
                onPressed: _loading ? null : _pickDay,
              ),
              if (_day != null)
                ActionChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: const Text('Mes completo'),
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() => _day = null);
                          _load();
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Center(
              child: TextButton(
                onPressed: _load,
                child: Text('$_error\nReintentar', textAlign: TextAlign.center),
              ),
            )
          else if (data == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _loading ? 0.5 : 1,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _TotalTile(
                          label: _day == null ? 'Venta del mes (facturado)' : 'Venta del día (facturado)',
                          value: data.salesTotal,
                          detail: '${data.sales.length} vendedor(es) · ERP',
                          color: AppColors.primary,
                          selected: _billed,
                          onTap: () => setState(() => _billed = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TotalTile(
                          label: _day == null ? 'Pedido del mes (app)' : 'Pedido del día (app)',
                          value: data.ordersTotal,
                          detail: '${data.orders.length} vendedor(es) · ${formatInt(data.ordersCount)} pedidos',
                          color: _ordersBlue,
                          selected: !_billed,
                          onTap: () => setState(() => _billed = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _billed
                      ? _RankList(
                          key: const ValueKey('ventas'),
                          items: data.sales,
                          color: AppColors.primary,
                          subtitle: (s) =>
                              data.salesTotal > 0 ? '${formatPercent(s.revenue / data.salesTotal)} del total' : '',
                          empty: 'Sin ventas registradas para este período.',
                        )
                      : _RankList(
                          key: const ValueKey('pedidos'),
                          items: data.orders,
                          color: _ordersBlue,
                          subtitle: (s) => '${s.orders ?? 0} pedido(s)',
                          empty: 'Sin pedidos registrados para este período.',
                        ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double value;
  final String detail;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: selected ? 0.12 : 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: color.withValues(alpha: selected ? 0.6 : 0.2),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMoney(value),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                ),
              ),
              Text(detail, style: const TextStyle(fontSize: 11, color: AppColors.textSoft)),
            ],
          ),
        ),
      ),
    );
  }
}
