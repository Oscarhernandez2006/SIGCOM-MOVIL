import 'package:flutter/material.dart';

import '../models/report.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/email_sheet.dart';
import '../widgets/quote_actions.dart';
import '../widgets/range_sheet.dart';
import '../widgets/web_session.dart';

const _icons = {
  'inventory': Icons.inventory_rounded,
  'product-sales': Icons.shopping_bag_outlined,
  'sales-summary': Icons.people_alt_outlined,
  'seller-ranking': Icons.emoji_events_outlined,
  'seller-product': Icons.person_search_outlined,
  'product-seller': Icons.workspace_premium_outlined,
  'seller-sales': Icons.flag_outlined,
  'vendor-product-sales': Icons.stacked_bar_chart_rounded,
};

/// Catálogo de reportes (General → Reportes de la web).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const BrandBackground(),
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                'Consulta los reportes en el celular y compártelos en PDF o Excel.',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
              ),
            ),
            for (final def in reportCatalog)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReportViewerScreen(api: api, company: company, user: user, def: def),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(_icons[def.key] ?? Icons.description_outlined, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(def.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(
                                  def.description,
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textSoft),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ReportViewerScreen extends StatefulWidget {
  const ReportViewerScreen({
    super.key,
    required this.api,
    required this.company,
    required this.user,
    required this.def,
  });

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;
  final ReportDef def;

  @override
  State<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<ReportViewerScreen> {
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTimeRange _range = DateTimeRange(start: _today, end: _today);
  late DateTime _date = _today;
  late DateTime _month = DateTime(_today.year, _today.month);
  DateTime? _periodDay;
  String _groupBy = 'customer';
  ({String id, String name})? _seller;
  ({String id, String name})? _product;
  List<({String id, String name})> _sellerOptions = const [];
  List<({String id, String name})> _productOptions = const [];

  ReportData? _data;
  String? _error;
  bool _loading = false;
  String _query = '';
  int _visible = 100;
  int _request = 0;

  ReportDef get _def => widget.def;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ReportQuery get _reportQuery => switch (_def.filter) {
    ReportFilter.day => ReportQuery(date: _date),
    ReportFilter.range => ReportQuery(
      from: _range.start,
      to: _range.end,
      groupBy: _def.key == 'sales-summary' ? _groupBy : null,
      sellerId: _def.key == 'seller-product' ? _seller?.id : null,
      sku: _product?.id,
    ),
    ReportFilter.month => ReportQuery(month: _month),
    ReportFilter.period => _periodDay == null ? ReportQuery(month: _month) : ReportQuery(date: _periodDay),
  };

  String get _periodLabel => switch (_def.filter) {
    ReportFilter.day => formatDayLabel(_date),
    ReportFilter.range => formatRangeLabel(_range),
    ReportFilter.month => formatMonth(_month),
    ReportFilter.period => _periodDay == null ? formatMonth(_month) : formatDayLabel(_periodDay!),
  };

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
        () => widget.api.report(_def.key, widget.company.id, _reportQuery),
      );
      if (!mounted || request != _request || data == null) return;
      setState(() {
        _data = data;
        _visible = 100;
        // Las opciones solo traen vendedores/productos con ventas; se conservan al filtrar.
        if (_seller == null && data.sellers.isNotEmpty) _sellerOptions = data.sellers;
        if (_product == null && data.products.isNotEmpty) _productOptions = data.products;
      });
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _resetOptions() {
    _seller = null;
    _product = null;
    _sellerOptions = const [];
    _productOptions = const [];
  }

  Future<void> _pickPeriod() async {
    switch (_def.filter) {
      case ReportFilter.range:
        final range = await showRangeSheet(context, _range);
        if (range == null) return;
        setState(() {
          _range = range;
          _resetOptions();
        });
      case ReportFilter.day:
        final day = await _pickDay(_date);
        if (day == null) return;
        setState(() => _date = day);
      case ReportFilter.month:
      case ReportFilter.period:
        return;
    }
    _load();
  }

  Future<DateTime?> _pickDay(DateTime initial) =>
      showDatePicker(context: context, firstDate: DateTime(_today.year - 3), lastDate: _today, initialDate: initial);

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _periodDay = null;
    });
    _load();
  }

  Future<void> _pickOption(bool seller) async {
    final options = seller ? _sellerOptions : _productOptions;
    final current = seller ? _seller : _product;
    final choice = await showModalBottomSheet<({({String id, String name})? value})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _OptionSheet(title: seller ? 'Vendedor' : 'Producto', options: options, selected: current),
    );
    if (choice == null || choice.value?.id == current?.id) return;
    setState(() => seller ? _seller = choice.value : _product = choice.value);
    _load();
  }

  String _fileName(bool excel) =>
      '${_def.key}-${_periodLabel.replaceAll(RegExp(r'[^0-9A-Za-záéíóúñ]+'), '-')}.${excel ? 'xlsx' : 'pdf'}';

  void _share(bool excel) {
    sharePdf(
      context,
      load: () => withWebSession(
        context,
        widget.api,
        () => widget.api.reportFile(_def.key, widget.company.id, _reportQuery, excel: excel),
      ),
      fileName: _fileName(excel),
      subject: '${_def.title} · $_periodLabel',
      mimeType: excel ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : 'application/pdf',
    );
  }

  Future<void> _email() async {
    final excel = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Adjuntar como', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626)),
              title: const Text('PDF'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_rounded, color: AppColors.primary),
              title: const Text('Excel'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (excel == null || !mounted) return;
    final query = _reportQuery;
    final period = _periodLabel;
    await showEmailSheet(
      context,
      title: 'Enviar reporte',
      customerName: null,
      userEmail: widget.user['email'] as String?,
      defaultMessage: 'Cordial saludo.\n\nAdjuntamos el reporte "${_def.title}" ($period).',
      onSend: (sheetContext, to, cc, message) => withWebSession(
        sheetContext,
        widget.api,
        () => widget.api.sendReport(
          _def.key,
          widget.company.id,
          query,
          excel: excel,
          to: to,
          cc: cc,
          message: message,
          subtitle: period,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final query = _query.trim().toLowerCase();
    final rows = data == null
        ? const <ReportRow>[]
        : data.rows.where((r) => query.isEmpty || r.matches(query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_def.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      bottomNavigationBar: data == null
          ? null
          : SafeArea(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _share(false),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('PDF'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _share(true),
                        icon: const Icon(Icons.table_chart_rounded),
                        label: const Text('Excel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        onPressed: _email,
                        icon: const Icon(Icons.forward_to_inbox_rounded, size: 18),
                        label: const Text('Correo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _filters(),
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
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _loading ? 0.5 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          data.subtitle!,
                          style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ),
                    _Kpis(kpis: data.kpis),
                    const SizedBox(height: 12),
                    if (data.rows.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Buscar en el reporte',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text('Sin datos para este período.', style: TextStyle(color: AppColors.textSoft)),
                        ),
                      ),
                    for (final row in rows.take(_visible)) _RowTile(row: row),
                    if (rows.length > _visible)
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() => _visible += 100),
                          child: Text('Ver más (${rows.length - _visible} restantes)'),
                        ),
                      ),
                    if (data.totalRow != null) _RowTile(row: data.totalRow!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    final chips = <Widget>[];
    if (_def.filter == ReportFilter.month || _def.filter == ReportFilter.period) {
      final isCurrent = _month.year == _today.year && _month.month == _today.month;
      chips.add(
        Row(
          children: [
            IconButton(
              onPressed: _loading ? null : () => _shiftMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                formatMonth(_month),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            IconButton(
              onPressed: _loading || isCurrent ? null : () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...chips,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_def.filter == ReportFilter.day || _def.filter == ReportFilter.range)
                ActionChip(
                  avatar: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(_periodLabel),
                  onPressed: _loading ? null : _pickPeriod,
                ),
              if (_def.filter == ReportFilter.period) ...[
                ActionChip(
                  avatar: const Icon(Icons.event_rounded, size: 16),
                  label: Text(_periodDay == null ? 'Elegir un día' : formatDayLabel(_periodDay!)),
                  onPressed: _loading
                      ? null
                      : () async {
                          final day = await _pickDay(_periodDay ?? _today);
                          if (day == null) return;
                          setState(() {
                            _periodDay = day;
                            _month = DateTime(day.year, day.month);
                          });
                          _load();
                        },
                ),
                if (_periodDay != null)
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month_rounded, size: 16),
                    label: const Text('Mes completo'),
                    onPressed: () {
                      setState(() => _periodDay = null);
                      _load();
                    },
                  ),
              ],
              if (_def.key == 'seller-product')
                ActionChip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 16),
                  label: Text(_seller?.name ?? 'Todos los vendedores'),
                  onPressed: _sellerOptions.isEmpty ? null : () => _pickOption(true),
                ),
              if (_def.key == 'seller-product' || _def.key == 'product-seller')
                ActionChip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(_product?.name ?? 'Todos los productos'),
                  onPressed: _productOptions.isEmpty ? null : () => _pickOption(false),
                ),
            ],
          ),
          if (_def.key == 'sales-summary') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'customer', label: Text('Por cliente')),
                  ButtonSegment(value: 'product', label: Text('Por producto')),
                ],
                selected: {_groupBy},
                onSelectionChanged: (v) {
                  setState(() => _groupBy = v.first);
                  _load();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.kpis});

  final List<ReportValue> kpis;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, k) in kpis.indexed)
              SizedBox(
                width: kpis.length.isOdd && i == kpis.length - 1 ? constraints.maxWidth : width,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.label.toUpperCase(),
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textSoft),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(k.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final ReportRow row;

  @override
  Widget build(BuildContext context) {
    final expandable = row.items.isNotEmpty || row.details.length > 2;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (row.highlight) const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
        if (row.highlight) const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              if (row.subtitle != null)
                Text(row.subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
              if (!expandable && row.details.isNotEmpty)
                Text(
                  row.details.map((d) => '${d.label}: ${d.text}').join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(row.valueText, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: row.highlight ? AppColors.primary.withValues(alpha: 0.06) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: expandable
            ? Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: header,
                  children: [
                    for (final d in row.details)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(d.label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                            ),
                            Text(d.text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ],
                        ),
                      ),
                    for (final item in row.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            if (item.highlight) const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(
                                    [?item.subtitle, ...item.details.map((d) => '${d.label}: ${d.text}')].join(' · '),
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft),
                                  ),
                                ],
                              ),
                            ),
                            Text(item.valueText, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            : Padding(padding: const EdgeInsets.all(12), child: header),
      ),
    );
  }
}

class _OptionSheet extends StatefulWidget {
  const _OptionSheet({required this.title, required this.options, required this.selected});

  final String title;
  final List<({String id, String name})> options;
  final ({String id, String name})? selected;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final options = widget.options.where((o) => o.name.toLowerCase().contains(query)).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                if (query.isEmpty)
                  ListTile(
                    title: const Text('Todos', style: TextStyle(fontWeight: FontWeight.w700)),
                    trailing: widget.selected == null ? const Icon(Icons.check_circle_rounded) : null,
                    onTap: () => Navigator.pop(context, (value: null)),
                  ),
                for (final o in options)
                  ListTile(
                    title: Text(o.name),
                    selected: o.id == widget.selected?.id,
                    selectedColor: AppColors.primary,
                    trailing: o.id == widget.selected?.id ? const Icon(Icons.check_circle_rounded) : null,
                    onTap: () => Navigator.pop(context, (value: o)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
