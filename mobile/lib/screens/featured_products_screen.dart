import 'package:flutter/material.dart';

import '../models/featured.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/web_session.dart';

const _star = Color(0xFFF59E0B);
const _red = Color(0xFFDC2626);

/// Catálogo › Productos estrella: los que se recuerdan al vendedor en cada pedido de cortes.
class FeaturedProductsScreen extends StatefulWidget {
  const FeaturedProductsScreen({super.key, required this.api, required this.company});

  final ApiService api;
  final Company company;

  @override
  State<FeaturedProductsScreen> createState() => _FeaturedProductsScreenState();
}

class _FeaturedProductsScreenState extends State<FeaturedProductsScreen> {
  List<FeaturedProduct>? _featured;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final featured = await widget.api.featuredProducts(widget.company.id);
      if (mounted) setState(() => _featured = featured);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Marca o desmarca en la web; devuelve true si se aplicó.
  Future<bool> _toggle(FeaturedProduct product, {required bool add}) async {
    setState(() => _busy.add(product.sku));
    try {
      final done = await withWebSession(context, widget.api, () async {
        add
            ? await widget.api.addFeaturedProduct(widget.company.id, product.sku, product.name)
            : await widget.api.removeFeaturedProduct(widget.company.id, product.sku);
        return true;
      });
      if (done != true || !mounted) return false;
      setState(() {
        final list = [...?_featured];
        add ? list.add(product) : list.removeWhere((p) => p.sku == product.sku);
        list.sort((a, b) => a.name.compareTo(b.name));
        _featured = list;
      });
      _snack(add ? '${product.name} es ahora producto estrella.' : '${product.name} ya no es producto estrella.');
      return true;
    } catch (e) {
      if (mounted) _snack(e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(product.sku));
    }
  }

  Future<void> _openPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _CatalogSheet(
        api: widget.api,
        company: widget.company,
        isFeatured: (sku) => _featured?.any((p) => p.sku == sku) ?? false,
        onToggle: (p, add) => _toggle(p, add: add),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featured;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
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
                      _Header(count: featured?.length, onAdd: featured == null ? null : _openPicker),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _Message(icon: Icons.cloud_off_rounded, text: _error!, onRetry: _load),
                      ],
                    ],
                  ),
                ),
                if (featured == null && _error == null)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (featured != null && featured.isEmpty)
                  const SliverToBoxAdapter(
                    child: _Message(
                      icon: Icons.star_outline_rounded,
                      text: 'Aún no hay productos estrella.\nAgrega los que quieras impulsar en cada pedido.',
                    ),
                  )
                else if (featured != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    sliver: SliverList.separated(
                      itemCount: featured.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final p = featured[i];
                        return _FeaturedCard(
                          product: p,
                          busy: _busy.contains(p.sku),
                          onRemove: () => _toggle(p, add: false),
                        );
                      },
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

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onAdd});

  final int? count;
  final VoidCallback? onAdd;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.star_rounded, color: _star, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == null ? 'Productos estrella' : '$count productos estrella',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Se recuerdan al vendedor en cada pedido de cortes si no los incluye.',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar producto', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.product, required this.busy, required this.onRemove});

  final FeaturedProduct product;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final stock = product.stock;
    final (stockText, stockColor) = stock == null
        ? ('No está en el inventario', _red)
        : stock <= 0
        ? ('Sin stock', _red)
        : ('Stock ${formatQuantity(stock)}${product.unit == null ? '' : ' ${product.unit}'}', AppColors.primary);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: _star, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text('Ref. ${product.sku}', style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                Text(
                  stockText,
                  style: TextStyle(color: stockColor, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: 'Quitar de estrella',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSoft),
                ),
        ],
      ),
    );
  }
}

class _CatalogSheet extends StatefulWidget {
  const _CatalogSheet({required this.api, required this.company, required this.isFeatured, required this.onToggle});

  final ApiService api;
  final Company company;
  final bool Function(String sku) isFeatured;
  final Future<bool> Function(FeaturedProduct product, bool add) onToggle;

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  late final Future<List<FeaturedProduct>> _future = widget.api.featuredProducts(widget.company.id, catalog: true);
  final Set<String> _busy = {};
  String _query = '';

  Future<void> _tap(FeaturedProduct p) async {
    setState(() => _busy.add(p.sku));
    await widget.onToggle(p, !widget.isFeatured(p.sku));
    if (mounted) setState(() => _busy.remove(p.sku));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Catálogo de cortes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.viewInsetsOf(context).bottom > 0 ? 4 : 6),
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
            child: FutureBuilder<List<FeaturedProduct>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) return _Message(icon: Icons.cloud_off_rounded, text: snapshot.error.toString());
                final products = snapshot.data;
                if (products == null) return const Center(child: CircularProgressIndicator());
                final q = _query.trim().toLowerCase();
                final visible = products
                    .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q))
                    .toList();
                if (visible.isEmpty) {
                  return const _Message(icon: Icons.search_off_rounded, text: 'Ningún producto coincide.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final p = visible[i];
                    final featured = widget.isFeatured(p.sku);
                    final stock = p.stock ?? 0;
                    return ListTile(
                      onTap: _busy.contains(p.sku) ? null : () => _tap(p),
                      leading: _busy.contains(p.sku)
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              featured ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: featured ? _star : AppColors.textSoft,
                              size: 28,
                            ),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        'Ref. ${p.sku} · ${stock <= 0 ? 'sin stock' : 'stock ${formatQuantity(stock)}'}',
                        style: TextStyle(color: stock <= 0 ? _red : AppColors.textSoft, fontSize: 12.5),
                      ),
                      trailing: featured
                          ? const Text(
                              'Estrella',
                              style: TextStyle(color: _star, fontWeight: FontWeight.w800, fontSize: 12.5),
                            )
                          : null,
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
        mainAxisSize: MainAxisSize.min,
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
