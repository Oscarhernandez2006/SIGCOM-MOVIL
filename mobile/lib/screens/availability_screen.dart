import 'package:flutter/material.dart';

import '../models/availability.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/email_sheet.dart';
import '../widgets/quote_actions.dart';
import '../widgets/web_session.dart';

enum _Species { all, beef, pork }

/// Productos con existencias para vender hoy, con precio de una lista opcional.
/// El listado se comparte en PDF o por correo, igual que en la web.
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key, required this.api, required this.company, required this.user});

  final ApiService api;
  final Company company;
  final Map<String, dynamic> user;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  List<AvailableProduct>? _products;
  List<PriceListRef> _priceLists = const [];
  PriceListRef? _priceList;
  String? _error;
  bool _loading = false;
  String _query = '';
  _Species _species = _Species.all;
  int _request = 0;

  ApiService get _api => widget.api;
  String get _company => widget.company.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadPriceLists();
    });
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await withWebSession(
        context,
        _api,
        () => _api.availability(_company, priceList: _priceList?.code),
      );
      if (mounted && request == _request && products != null) setState(() => _products = products);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _loadPriceLists() async {
    try {
      final lists = await withWebSession(context, _api, () => _api.priceLists(_company));
      if (mounted && lists != null) setState(() => _priceLists = lists);
    } catch (_) {
      // Sin listas se puede seguir consultando la disponibilidad sin precios.
    }
  }

  Future<void> _pickPriceList() async {
    final choice = await showModalBottomSheet<({PriceListRef? list})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _PriceListSheet(lists: _priceLists, selected: _priceList),
    );
    if (choice == null || choice.list?.code == _priceList?.code) return;
    setState(() => _priceList = choice.list);
    _load();
  }

  void _share() {
    final date = formatApiDate(DateTime.now());
    sharePdf(
      context,
      load: () => withWebSession(context, _api, () => _api.availabilityPdf(_company, priceList: _priceList?.code)),
      fileName: 'disponibilidad-$date.pdf',
      subject: 'Disponibilidad de productos ${formatDate(DateTime.now())}',
    );
  }

  void _email() {
    final list = _priceList;
    showEmailSheet(
      context,
      title: 'Enviar disponibilidad',
      customerName: null,
      userEmail: widget.user['email'] as String?,
      defaultMessage:
          'Cordial saludo.\n\nCompartimos los productos disponibles para pedido hoy'
          '${list == null ? '' : ' con precios de la lista ${list.name}'}. Quedamos atentos a su solicitud.',
      onSend: (sheetContext, to, cc, message) => withWebSession(
        sheetContext,
        _api,
        () => _api.sendAvailability(_company, priceList: list, to: to, cc: cc, message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    final query = _query.trim().toLowerCase();
    final visible = (products ?? const <AvailableProduct>[])
        .where(
          (p) => switch (_species) {
            _Species.all => true,
            _Species.beef => !p.isPork,
            _Species.pork => p.isPork,
          },
        )
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query))
        .toList();
    final porkCount = products?.where((p) => p.isPork).length ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: products == null || products.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: _share,
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('PDF / Compartir'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: _email,
                        icon: const Icon(Icons.forward_to_inbox_rounded),
                        label: const Text('Enviar correo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  sliver: SliverList.list(
                    children: [
                      _Header(
                        count: products?.length,
                        priceList: _priceList,
                        loading: _loading,
                        onPickPriceList: _pickPriceList,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre o referencia',
                          prefixIcon: Icon(Icons.search_rounded),
                          fillColor: Colors.white,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      if (porkCount > 0) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<_Species>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(backgroundColor: Colors.white),
                            segments: [
                              ButtonSegment(value: _Species.all, label: Text('Todos (${products?.length ?? 0})')),
                              ButtonSegment(
                                value: _Species.beef,
                                label: Text('Res (${(products?.length ?? 0) - porkCount})'),
                              ),
                              ButtonSegment(value: _Species.pork, label: Text('Cerdo ($porkCount)')),
                            ],
                            selected: {_species},
                            onSelectionChanged: (v) => setState(() => _species = v.first),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(onPressed: _load, child: const Text('Reintentar')),
                        ],
                      ),
                    ),
                  )
                else if (products == null)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 44, color: AppColors.textSoft),
                          const SizedBox(height: 8),
                          Text(
                            query.isNotEmpty
                                ? 'No hay productos disponibles con esa búsqueda.'
                                : _priceList != null
                                ? 'No hay productos con existencias en esta lista de precios.'
                                : 'No hay productos con existencias en este momento.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _ProductTile(product: visible[i]),
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
  const _Header({required this.count, required this.priceList, required this.loading, required this.onPickPriceList});

  final int? count;
  final PriceListRef? priceList;
  final bool loading;
  final VoidCallback onPickPriceList;

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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Disponibilidad',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
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
          Text(
            count == null
                ? 'Productos con existencias para vender hoy'
                : '$count referencia${count == 1 ? '' : 's'} disponible${count == 1 ? '' : 's'} hoy',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onPickPriceList,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.sell_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        priceList == null ? 'Sin precios (solo disponibilidad)' : 'Precios: ${priceList!.label}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSoft),
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

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final AvailableProduct product;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    ['Ref. ${product.sku}', ?product.unit].join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (product.price != null)
                  Text(formatMoney(product.price!), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${formatQuantity(product.stock)} disp.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceListSheet extends StatefulWidget {
  const _PriceListSheet({required this.lists, required this.selected});

  final List<PriceListRef> lists;
  final PriceListRef? selected;

  @override
  State<_PriceListSheet> createState() => _PriceListSheetState();
}

class _PriceListSheetState extends State<_PriceListSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final lists = widget.lists
        .where((l) => l.name.toLowerCase().contains(query) || l.code.toLowerCase().contains(query))
        .toList();

    Widget option(PriceListRef? list) {
      final selected = list?.code == widget.selected?.code;
      return ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        selectedColor: AppColors.primary,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
        leading: Icon(list == null ? Icons.inventory_2_outlined : Icons.sell_outlined),
        title: Text(list?.name ?? 'Sin precios', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(list == null ? 'Solo disponibilidad' : 'Lista ${list.code}'),
        trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
        onTap: () => Navigator.pop(context, (list: list)),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Lista de precios', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          if (widget.lists.length > 6)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Buscar lista', prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [if (query.isEmpty) option(null), for (final l in lists) option(l)],
            ),
          ),
        ],
      ),
    );
  }
}
