import 'dart:async';

import 'package:flutter/material.dart';

import '../models/quote.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/order_widgets.dart';
import '../widgets/quote_actions.dart';
import '../widgets/status_pill.dart';
import 'new_quote_screen.dart';

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  List<QuoteSummary>? _quotes;
  String? _error;
  bool _loading = false;
  String _search = '';
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
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
      final quotes = await widget.api.quotes(widget.company.id, search: _search);
      if (mounted && request == _request) setState(() => _quotes = quotes);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewQuoteScreen(api: widget.api, company: widget.company, user: widget.user),
      ),
    );
    if (created == true) _load();
  }

  void _open(QuoteSummary quote) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuoteDetailScreen(api: widget.api, summary: quote, user: widget.user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quotes = _quotes;
    final showSeller = widget.user['role'] != 'seller';
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.request_quote_rounded),
        label: const Text('Nueva cotización', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Stack(
        children: [
          const BrandBackground(),
          RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por cliente, NIT o número',
                    prefixIcon: const Icon(Icons.search_rounded),
                    fillColor: Colors.white,
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      _search = v;
                      _load();
                    });
                  },
                ),
                const SizedBox(height: 12),
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
                else if (quotes == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (quotes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Column(
                      children: [
                        Icon(Icons.request_quote_outlined, size: 48, color: AppColors.textSoft),
                        SizedBox(height: 8),
                        Text('Aún no hay cotizaciones.', style: TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  )
                else
                  for (final q in quotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _QuoteCard(quote: q, showSeller: showSeller, onTap: () => _open(q)),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.showSeller, required this.onTap});

  final QuoteSummary quote;
  final bool showSeller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('N.º ${quote.number}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(width: 8),
                  _ValidityPill(quote: quote),
                  const Spacer(),
                  Text(
                    formatShortDate(quote.createdAt),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(quote.customer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                [
                  quote.customer.branch ?? quote.customer.code,
                  if (showSeller && quote.seller != null) quote.seller!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${quote.itemsCount} producto${quote.itemsCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                  ),
                  const Spacer(),
                  Text(formatMoney(quote.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValidityPill extends StatelessWidget {
  const _ValidityPill({required this.quote});

  final QuoteSummary quote;

  @override
  Widget build(BuildContext context) {
    final until = quote.validUntil;
    if (quote.expired) return const StatusPill(label: 'Vencida', color: Color(0xFFDC2626));
    return StatusPill(
      label: until == null ? 'Vigente' : 'Vigente hasta ${formatShortDate(until)}',
      color: AppColors.primary,
    );
  }
}

class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.api, required this.summary, required this.user});

  final ApiService api;
  final QuoteSummary summary;
  final Map<String, dynamic> user;

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  late Future<QuoteDetail> _future = widget.api.quote(widget.summary.id);

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return Scaffold(
      appBar: AppBar(
        title: Text('Cotización ${summary.number}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: QuoteActionsBar(
            api: widget.api,
            id: summary.id,
            number: summary.number,
            customerName: summary.customer.name,
            customerEmail: summary.customer.email,
            userEmail: widget.user['email'] as String?,
          ),
        ),
      ),
      body: FutureBuilder<QuoteDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _future = widget.api.quote(summary.id)),
                child: Text('${snapshot.error}\nReintentar', textAlign: TextAlign.center),
              ),
            );
          }
          final detail = snapshot.data;
          if (detail == null) return const Center(child: CircularProgressIndicator());
          final q = detail.summary;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              FormSection(
                title: 'Resumen',
                icon: Icons.request_quote_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ValidityPill(quote: q),
                    const SizedBox(height: 10),
                    Text(
                      formatMoney(q.total),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    Text(
                      'Creada el ${formatDate(q.createdAt)}${q.validUntil == null ? '' : ' · válida hasta el ${formatDate(q.validUntil!)}'}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft),
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
                    Text(q.customer.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('NIT ${q.customer.code}${q.customer.branch == null ? '' : ' · ${q.customer.branch}'}'),
                    Text(
                      q.customer.email?.trim().isNotEmpty == true ? q.customer.email! : 'Sin correo registrado',
                      style: TextStyle(
                        color: q.customer.email?.trim().isNotEmpty == true ? AppColors.text : const Color(0xFFB45309),
                      ),
                    ),
                    if (q.customer.phone != null) Text('Tel. ${q.customer.phone}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FormSection(
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
                                Text(
                                  'Ref. ${item.sku} · ${formatQuantity(item.quantity)} ${item.unit ?? ''} × ${formatMoney(item.unitPrice)}'
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
                    AmountRow('Subtotal', detail.subtotal),
                    AmountRow('Impuestos', detail.taxes),
                    AmountRow('Total', q.total, bold: true),
                  ],
                ),
              ),
              if (detail.notes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 12),
                FormSection(title: 'Notas', icon: Icons.sticky_note_2_outlined, child: Text(detail.notes!)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Botones "PDF" y "Enviar por correo" de una cotización.
class QuoteActionsBar extends StatelessWidget {
  const QuoteActionsBar({
    super.key,
    required this.api,
    required this.id,
    required this.number,
    required this.customerName,
    this.customerEmail,
    this.userEmail,
  });

  final ApiService api;
  final String id;
  final String number;
  final String customerName;
  final String? customerEmail;
  final String? userEmail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => shareQuotePdf(context, api, id: id, number: number),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('PDF / Compartir'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => showSendQuoteSheet(
              context,
              api,
              id: id,
              number: number,
              customerName: customerName,
              customerEmail: customerEmail,
              userEmail: userEmail,
            ),
            icon: const Icon(Icons.forward_to_inbox_rounded),
            label: const Text('Enviar correo'),
          ),
        ),
      ],
    );
  }
}
