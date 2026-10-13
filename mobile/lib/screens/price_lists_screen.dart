import 'package:flutter/material.dart';

import '../models/price_list.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/quote_actions.dart';
import '../widgets/web_session.dart';

/// Catálogo › Listas de precios: consulta de las listas de Siesa, su PDF y la sincronización.
class PriceListsScreen extends StatefulWidget {
  const PriceListsScreen({super.key, required this.api, required this.company});

  final ApiService api;
  final Company company;

  @override
  State<PriceListsScreen> createState() => _PriceListsScreenState();
}

class _PriceListsScreenState extends State<PriceListsScreen> {
  PriceListsResult? _result;
  String? _error;
  String _query = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final result = await widget.api.priceListsCatalog(widget.company.id);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _sync() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizar con Siesa'),
        content: Text(
          'Se traen las listas de precios de ${widget.company.name} desde Siesa y se reemplazan las actuales. '
          'Los pedidos y cotizaciones nuevos usarán los precios actualizados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sincronizar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await withWebSession(context, widget.api, () => widget.api.syncPriceLists(widget.company.id));
      if (r == null || !mounted) return;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            '${r.lists} listas · ${formatInt(r.total)} precios. '
            'Nuevos ${formatInt(r.created)}, actualizados ${formatInt(r.updated)}, eliminados ${formatInt(r.removed)}.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _open(PriceListInfo list) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PriceListDetailScreen(api: widget.api, company: widget.company, list: list),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final q = _query.trim().toLowerCase();
    final lists = (result?.lists ?? const <PriceListInfo>[])
        .where((l) => q.isEmpty || l.name.toLowerCase().contains(q) || l.code.toLowerCase().contains(q))
        .toList();
    final updated = result?.lists
        .map((l) => l.updatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

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
                      count: result?.lists.length,
                      updated: updated,
                      canSync: result?.canSync ?? false,
                      syncing: _syncing,
                      onSync: _sync,
                      onSearch: (v) => setState(() => _query = v),
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
              else if (result != null && lists.isEmpty)
                SliverToBoxAdapter(
                  child: _Message(
                    icon: Icons.sell_outlined,
                    text: result.lists.isEmpty
                        ? 'Esta compañía no tiene listas de precios.'
                        : 'Ninguna lista coincide con la búsqueda.',
                  ),
                )
              else if (result != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: lists.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ListCard(list: lists[i], onTap: () => _open(lists[i])),
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
    required this.count,
    required this.updated,
    required this.canSync,
    required this.syncing,
    required this.onSync,
    required this.onSearch,
  });

  final int? count;
  final DateTime? updated;
  final bool canSync;
  final bool syncing;
  final VoidCallback onSync;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                  'Listas de precios',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
              ),
              if (canSync)
                syncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : IconButton(
                        tooltip: 'Sincronizar con Siesa',
                        onPressed: onSync,
                        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18)),
                        icon: const Icon(Icons.sync_rounded, color: Colors.white),
                      ),
            ],
          ),
          Text(
            [
              if (count != null) '$count ${count == 1 ? 'lista' : 'listas'}',
              if (updated != null) 'actualizado ${formatShortDate(updated!)} ${formatTime(updated!)}',
            ].join(' · '),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar lista por nombre o código',
              isDense: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search_rounded),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.list, required this.onTap});

  final PriceListInfo list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      list.code,
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        _Tag(icon: Icons.inventory_2_outlined, text: '${formatInt(list.items)} productos'),
                        _Tag(
                          icon: Icons.storefront_outlined,
                          text: list.clients == 0
                              ? 'Sin clientes'
                              : '${formatInt(list.clients)} ${list.clients == 1 ? 'cliente' : 'clientes'}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSoft),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
      ],
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

class PriceListDetailScreen extends StatefulWidget {
  const PriceListDetailScreen({super.key, required this.api, required this.company, required this.list});

  final ApiService api;
  final Company company;
  final PriceListInfo list;

  @override
  State<PriceListDetailScreen> createState() => _PriceListDetailScreenState();
}

class _PriceListDetailScreenState extends State<PriceListDetailScreen> {
  late Future<List<PriceListItem>> _future = widget.api.priceListItems(widget.company.id, widget.list.code);
  String _query = '';

  void _sharePdf() {
    final list = widget.list;
    sharePdf(
      context,
      load: () => withWebSession(context, widget.api, () => widget.api.priceListPdf(widget.company.id, list.code)),
      fileName: 'lista-precios-${list.code}-${formatApiDate(DateTime.now())}.pdf',
      subject: 'Lista de precios ${list.name} · ${formatDate(DateTime.now())}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(list.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(
              'Lista ${list.code} · ${formatInt(list.items)} productos',
              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Compartir PDF', onPressed: _sharePdf, icon: const Icon(Icons.picture_as_pdf_rounded)),
        ],
      ),
      body: Column(
        children: [
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
            child: FutureBuilder<List<PriceListItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _Message(
                    icon: Icons.cloud_off_rounded,
                    text: snapshot.error.toString(),
                    onRetry: () =>
                        setState(() => _future = widget.api.priceListItems(widget.company.id, widget.list.code)),
                  );
                }
                final items = snapshot.data;
                if (items == null) return const Center(child: CircularProgressIndicator());
                final q = _query.trim().toLowerCase();
                final visible = items
                    .where((i) => q.isEmpty || i.name.toLowerCase().contains(q) || i.sku.toLowerCase().contains(q))
                    .toList();
                if (visible.isEmpty) {
                  return const _Message(icon: Icons.search_off_rounded, text: 'Ningún producto coincide.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final item = visible[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  'Ref. ${item.sku}${item.unit == null ? '' : ' · ${item.unit}'}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(item.price),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              if (item.unit != null)
                                Text(
                                  'por ${item.unit}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
