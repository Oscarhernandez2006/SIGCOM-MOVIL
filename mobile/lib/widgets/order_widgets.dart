import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ordering.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'status_pill.dart';
import 'web_session.dart';

/// Buscador de clientes de la cartera (lo usan pedidos y cotizaciones).
class ClientPicker extends StatefulWidget {
  const ClientPicker({
    super.key,
    required this.api,
    required this.company,
    required this.selected,
    required this.onSelect,
  });

  final ApiService api;
  final String company;
  final OrderClient? selected;
  final ValueChanged<OrderClient> onSelect;

  @override
  State<ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<ClientPicker> {
  List<OrderClient>? _clients;
  String? _error;
  Timer? _debounce;
  String _search = '';
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
    setState(() => _error = null);
    try {
      final clients = await withWebSession(context, widget.api, () => widget.api.orderClients(widget.company, _search));
      if (mounted && request == _request) setState(() => _clients = clients ?? []);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = _clients;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            autofocus: widget.selected == null,
            decoration: const InputDecoration(
              hintText: 'Buscar cliente por nombre o NIT',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                _search = v;
                _load();
              });
            },
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: Text('$_error\nReintentar', textAlign: TextAlign.center),
                  ),
                )
              : clients == null
              ? const Center(child: CircularProgressIndicator())
              : clients.isEmpty
              ? const Center(
                  child: Text('Sin clientes para esta búsqueda.', style: TextStyle(color: AppColors.textSoft)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: clients.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = clients[i];
                    final selected = c.id == widget.selected?.id;
                    final noList = c.priceList == null || c.priceList!.trim().isEmpty;
                    return Material(
                      color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => widget.onSelect(c),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text(
                                  c.name.isEmpty ? '?' : c.name[0],
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      [c.code, if (c.subtitle.isNotEmpty) c.subtitle].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                                    ),
                                    const SizedBox(height: 4),
                                    noList
                                        ? const StatusPill(label: 'Sin lista de precios', color: Color(0xFFDC2626))
                                        : Text(
                                            'Lista ${c.priceListName ?? c.priceList}${c.paymentTerm == null ? '' : ' · ${c.paymentTerm}'}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                              Icon(
                                selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                                color: selected ? AppColors.primary : AppColors.textSoft,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Control de cantidad entera: "Agregar" y luego − / número editable / +.
class QtyControl extends StatelessWidget {
  const QtyControl({super.key, required this.qty, required this.enabled, required this.onQty, this.unit});

  final int qty;
  final bool enabled;
  final ValueChanged<int> onQty;
  final String? unit;

  Future<void> _type(BuildContext context) async {
    final text = await showNumberDialog(
      context,
      title: 'Cantidad${unit == null ? '' : ' ($unit)'}',
      initial: qty > 0 ? '$qty' : '',
    );
    if (text != null) onQty(int.tryParse(text) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    if (qty == 0) {
      return OutlinedButton.icon(
        onPressed: enabled ? () => onQty(1) : null,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Agregar'),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, color: AppColors.primary),
            onPressed: () => onQty(qty - 1),
          ),
          InkWell(
            onTap: () => _type(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 36),
              child: Text(
                '$qty',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            onPressed: () => onQty(qty + 1),
          ),
        ],
      ),
    );
  }
}

/// Pide un número; devuelve el texto escrito o null si se cancela.
Future<String?> showNumberDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  bool decimal = false,
  String? suffix,
  String confirmLabel = 'Aceptar',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _NumberDialog(title: title, initial: initial, decimal: decimal, suffix: suffix, confirmLabel: confirmLabel),
  );
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.initial,
    required this.decimal,
    required this.suffix,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final bool decimal;
  final String? suffix;
  final String confirmLabel;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: [
          widget.decimal
              ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              : FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(suffixText: widget.suffix, hintText: '0'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.value, {super.key, this.bold = false});

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: bold ? 17 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(formatMoney(value), style: style),
        ],
      ),
    );
  }
}
