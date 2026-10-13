import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/portfolio.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/portfolio_pdf.dart';
import '../widgets/brand_background.dart';
import '../widgets/email_sheet.dart';
import '../widgets/order_widgets.dart';
import '../widgets/status_pill.dart';

const _red = Color(0xFFDC2626);
const _amber = Color(0xFFB45309);

enum _Filter { all, withBalance, overdue }

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  static const _batch = 30;

  List<PortfolioClient>? _clients;
  bool _limited = false;
  final Map<String, PortfolioSummary?> _summaries = {};
  String? _error;
  String _query = '';
  _Filter _filter = _Filter.all;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _error = null;
      _summaries.clear();
    });
    try {
      final result = await widget.api.portfolioClients(widget.company.id);
      if (!mounted || request != _request) return;
      setState(() {
        _clients = result.clients;
        _limited = result.limited;
      });
      await _loadBalances(request, result.clients.map((c) => c.nit).toList());
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    }
  }

  /// El ERP solo entrega cartera por NIT: se piden por lotes y la lista se va completando.
  Future<void> _loadBalances(int request, List<String> nits) async {
    for (var i = 0; i < nits.length; i += _batch) {
      final chunk = nits.sublist(i, (i + _batch).clamp(0, nits.length));
      try {
        final result = await widget.api.portfolioBalances(widget.company.id, chunk);
        if (!mounted || request != _request) return;
        setState(() {
          for (final nit in chunk) {
            _summaries[nit] = result[nit];
          }
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          for (final nit in chunk) {
            _summaries[nit] = null;
          }
        });
      }
    }
  }

  void _open(PortfolioClient client) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PortfolioDetailScreen(api: widget.api, company: widget.company, user: widget.user, client: client),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clients = _clients;
    final loaded = _summaries.length;
    final total = clients?.length ?? 0;
    final summaries = _summaries.values.whereType<PortfolioSummary>();
    final totalBalance = summaries.fold<double>(0, (s, x) => s + x.total);
    final totalOverdue = summaries.fold<double>(0, (s, x) => s + x.overdue);
    final withBalance = summaries.where((x) => x.total > 0).length;

    final query = _query.trim().toLowerCase();
    final visible =
        (clients ?? const <PortfolioClient>[]).where((c) {
          if (query.isNotEmpty && !c.name.toLowerCase().contains(query) && !c.nit.contains(query)) return false;
          final s = _summaries[c.nit];
          return switch (_filter) {
            _Filter.all => true,
            _Filter.withBalance => s != null && s.total > 0,
            _Filter.overdue => s != null && s.hasOverdue,
          };
        }).toList()..sort((a, b) {
          final sa = _summaries[a.nit]?.total ?? -1;
          final sb = _summaries[b.nit]?.total ?? -1;
          return sb.compareTo(sa);
        });

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
                totalBalance: totalBalance,
                totalOverdue: totalOverdue,
                withBalance: withBalance,
                loaded: loaded,
                total: total,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar cliente o NIT',
                  prefixIcon: Icon(Icons.search_rounded),
                  fillColor: Colors.white,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final (f, label) in [
                    (_Filter.all, 'Todos'),
                    (_Filter.withBalance, 'Con saldo'),
                    (_Filter.overdue, 'Con vencido'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      TextButton(onPressed: _load, child: const Text('Reintentar')),
                    ],
                  ),
                )
              else if (clients == null)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'No hay clientes con este filtro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSoft),
                  ),
                )
              else
                for (final c in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ClientCard(
                      client: c,
                      summary: _summaries[c.nit],
                      loading: !_summaries.containsKey(c.nit),
                      onTap: () => _open(c),
                    ),
                  ),
              if (_limited)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Se muestran los primeros 1.000 clientes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textSoft),
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
    required this.totalBalance,
    required this.totalOverdue,
    required this.withBalance,
    required this.loaded,
    required this.total,
  });

  final double totalBalance;
  final double totalOverdue;
  final int withBalance;
  final int loaded;
  final int total;

  @override
  Widget build(BuildContext context) {
    final loading = total > 0 && loaded < total;
    return Container(
      padding: const EdgeInsets.all(18),
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
          const Text(
            'Cartera de clientes',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _HeaderStat(label: 'Saldo total', value: formatMoneyShort(totalBalance)),
              ),
              Expanded(
                child: _HeaderStat(label: 'Vencido', value: formatMoneyShort(totalOverdue)),
              ),
              Expanded(
                child: _HeaderStat(label: 'Con saldo', value: formatInt(withBalance)),
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: loaded / total,
                minHeight: 5,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Consultando saldos en Siesa · $loaded de $total clientes',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.summary, required this.loading, required this.onTap});

  final PortfolioClient client;
  final PortfolioSummary? summary;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: s?.hasOverdue == true ? _red.withValues(alpha: 0.35) : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      [
                        'NIT ${client.nit}',
                        if (client.city != null) client.city!,
                        if (client.branches > 1) '${client.branches} sucursales',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                    ),
                    if (s != null && s.hasOverdue) ...[
                      const SizedBox(height: 6),
                      StatusPill(
                        label: 'Vencido ${formatMoneyShort(s.overdue)} · ${s.maxDaysOverdue} días',
                        color: _red,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (loading)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else if (s == null)
                const Tooltip(
                  message: 'No se pudo consultar el saldo',
                  child: Icon(Icons.sync_problem_rounded, color: _amber),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(s.total),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: s.total > 0 ? AppColors.text : AppColors.primary,
                      ),
                    ),
                    Text(
                      s.total > 0 ? '${s.documentsCount} doc.' : 'Al día',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PortfolioDetailScreen extends StatefulWidget {
  const PortfolioDetailScreen({
    super.key,
    required this.api,
    required this.company,
    required this.user,
    required this.client,
  });

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;
  final PortfolioClient client;

  @override
  State<PortfolioDetailScreen> createState() => _PortfolioDetailScreenState();
}

class _PortfolioDetailScreenState extends State<PortfolioDetailScreen> {
  late Future<PortfolioDetail> _future = widget.api.portfolio(widget.company.id, widget.client.nit);
  bool _onlyOverdue = false;
  bool _busy = false;

  Future<List<int>> _pdf(PortfolioDetail detail) =>
      buildPortfolioPdf(detail: detail, company: widget.company, sellerName: widget.user['name'] as String?);

  Future<void> _share(PortfolioDetail detail) async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdf(detail);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/estado-cartera-${detail.nit}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Estado de cartera ${detail.name}',
          title: 'Estado de cartera ${detail.name}',
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _email(PortfolioDetail detail) {
    showEmailSheet(
      context,
      title: 'Enviar estado de cartera',
      customerName: detail.name,
      recipients: detail.emails,
      userEmail: widget.user['email'] as String?,
      defaultMessage:
          'Cordial saludo.\n\nCompartimos el estado de su cartera con nosotros con corte al '
          '${formatDate(detail.summary.asOf)}. Quedamos atentos a cualquier inquietud.',
      onSend: (_, to, cc, message) async => widget.api.sendPortfolio(
        widget.company.id,
        detail.nit,
        pdf: await _pdf(detail),
        to: to,
        cc: cc,
        message: message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.client.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<PortfolioDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _future = widget.api.portfolio(widget.company.id, widget.client.nit)),
                child: Text('${snapshot.error}\nReintentar', textAlign: TextAlign.center),
              ),
            );
          }
          final detail = snapshot.data;
          if (detail == null) return const Center(child: CircularProgressIndicator());
          return _body(detail);
        },
      ),
      bottomNavigationBar: FutureBuilder<PortfolioDetail>(
        future: _future,
        builder: (context, snapshot) {
          final detail = snapshot.data;
          if (detail == null) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: _busy ? null : () => _share(detail),
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('PDF / Compartir'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: () => _email(detail),
                      icon: const Icon(Icons.forward_to_inbox_rounded),
                      label: const Text('Enviar correo'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(PortfolioDetail detail) {
    final s = detail.summary;
    final docs = _onlyOverdue ? detail.documents.where((d) => d.overdue).toList() : detail.documents;
    final maxAging = s.aging.values.fold<double>(0, (m, v) => v > m ? v : m);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        FormSection(
          title: 'Saldo al ${formatDate(s.asOf)}',
          icon: Icons.account_balance_wallet_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatMoney(s.total),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Stat(label: 'Vencido', value: formatMoney(s.overdue), color: s.hasOverdue ? _red : null),
                  ),
                  Expanded(
                    child: _Stat(label: 'Por vencer', value: formatMoney(s.current)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Mora máxima',
                      value: '${s.maxDaysOverdue} días',
                      color: s.maxDaysOverdue > 0 ? _red : null,
                    ),
                  ),
                  Expanded(
                    child: _Stat(label: 'Cupo', value: s.creditLimit == null ? '—' : formatMoney(s.creditLimit!)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FormSection(
          title: 'Antigüedad de saldos',
          icon: Icons.stacked_bar_chart_rounded,
          child: Column(
            children: [
              for (final (i, e) in PortfolioSummary.agingLabels.entries.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(
                            formatMoney(s.aging[e.key] ?? 0),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxAging <= 0 ? 0 : ((s.aging[e.key] ?? 0) / maxAging).clamp(0, 1),
                          minHeight: 6,
                          backgroundColor: AppColors.field,
                          color: i == 0 ? AppColors.primary : Color.lerp(const Color(0xFFF59E0B), _red, (i - 1) / 3),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FormSection(
          title: 'Cliente',
          icon: Icons.storefront_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${detail.name} · NIT ${detail.nit}', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (detail.paymentTerm != null) Text('Condición de pago: ${detail.paymentTerm}'),
              Text(
                detail.emails.isEmpty ? 'Sin correo registrado' : detail.emails.join(', '),
                style: TextStyle(color: detail.emails.isEmpty ? _amber : AppColors.text),
              ),
              if (detail.phones.isNotEmpty) Text('Tel. ${detail.phones.join(', ')}'),
              if (detail.branches.length > 1)
                Text('${detail.branches.length} sucursales', style: const TextStyle(color: AppColors.textSoft)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FormSection(
          title: 'Documentos (${docs.length})',
          icon: Icons.receipt_long_outlined,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text('Todos (${detail.documents.length})')),
                    ButtonSegment(
                      value: true,
                      label: Text('Vencidos (${detail.documents.where((d) => d.overdue).length})'),
                    ),
                  ],
                  selected: {_onlyOverdue},
                  onSelectionChanged: (v) => setState(() => _onlyOverdue = v.first),
                ),
              ),
              const SizedBox(height: 6),
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Sin documentos.', style: TextStyle(color: AppColors.textSoft)),
                ),
              for (final (i, d) in docs.take(300).indexed) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.number, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              '${d.type} · ${detail.branchName(d.branch)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                            ),
                            Text(
                              'Vence ${d.dueDate == null ? '—' : formatDate(d.dueDate!)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMoney(d.balance), style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (d.overdue)
                            Text(
                              '${d.daysOverdue} días vencido',
                              style: const TextStyle(fontSize: 12, color: _red, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (docs.length > 300)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Se muestran 300 de ${docs.length} documentos. El PDF los incluye todos.',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color ?? AppColors.text),
          ),
        ),
      ],
    );
  }
}
