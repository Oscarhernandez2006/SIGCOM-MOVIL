import 'package:flutter/material.dart';

import '../models/ordering.dart';
import '../models/settings.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand_background.dart';
import '../widgets/web_session.dart';

/// Configuración › Horario de pedidos: ventana global para crear pedidos (Montería TAT está exenta).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.api, required this.company});

  final ApiService api;
  final Company company;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  OrderScheduleSetting? _saved;
  String? _error;
  bool _enabled = true;
  TimeOfDay _open = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _close = const TimeOfDay(hour: 16, minute: 30);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static TimeOfDay _parse(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _apply(OrderScheduleSetting s) {
    _saved = s;
    _enabled = s.enabled;
    _open = _parse(s.open);
    _close = _parse(s.close);
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await widget.api.orderSchedule();
      if (mounted) setState(() => _apply(s));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool get _changed {
    final s = _saved;
    return s != null && (s.enabled != _enabled || s.open != _fmt(_open) || s.close != _fmt(_close));
  }

  bool get _valid => !_enabled || _fmt(_close).compareTo(_fmt(_open)) > 0;

  Future<void> _pick(bool open) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: open ? _open : _close,
      helpText: open ? 'Hora de apertura' : 'Hora de cierre',
    );
    if (picked != null) setState(() => open ? _open = picked : _close = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final s = await withWebSession(
        context,
        widget.api,
        () =>
            widget.api.saveOrderSchedule(widget.company.id, enabled: _enabled, open: _fmt(_open), close: _fmt(_close)),
      );
      if (s == null || !mounted) return;
      setState(() => _apply(s));
      messenger.showSnackBar(
        const SnackBar(content: Text('Horario guardado. Aplica de inmediato a todos los vendedores.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return Stack(
      children: [
        const BrandBackground(),
        if (saved == null)
          Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: _load,
                    child: Text('$_error\nReintentar', textAlign: TextAlign.center),
                  ),
          )
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _StatusCard(setting: saved),
              const SizedBox(height: 14),
              Material(
                color: Colors.white,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      title: const Text('Restringir el horario', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        _enabled
                            ? 'Solo se pueden crear pedidos dentro de la ventana.'
                            : 'Los pedidos se pueden crear a cualquier hora.',
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    _TimeTile(
                      label: 'Desde',
                      icon: Icons.wb_sunny_outlined,
                      value: DeliverySchedule.hour12(_fmt(_open)),
                      enabled: _enabled,
                      onTap: () => _pick(true),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                    _TimeTile(
                      label: 'Hasta',
                      icon: Icons.nights_stay_outlined,
                      value: DeliverySchedule.hour12(_fmt(_close)),
                      enabled: _enabled,
                      onTap: () => _pick(false),
                    ),
                  ],
                ),
              ),
              if (!_valid)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    'La hora de cierre debe ser posterior a la de apertura.',
                    style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 12),
              const _Note(
                icon: Icons.info_outline_rounded,
                text:
                    'Es un horario único para todas las compañías y se valida al crear el pedido (hora Colombia). '
                    'Montería TAT no tiene restricción. No afecta la aprobación ni el envío a Siesa.',
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _saving || !_changed || !_valid ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar horario', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.setting});

  final OrderScheduleSetting setting;

  @override
  Widget build(BuildContext context) {
    final open = setting.isOpen;
    final color = open ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
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
          const Text(
            'Horario de pedidos',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
          const SizedBox(height: 4),
          Text(
            setting.enabled
                ? 'De ${DeliverySchedule.hour12(setting.open)} a ${DeliverySchedule.hour12(setting.close)}'
                : 'Sin restricción de horario',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 10, color: color),
                    const SizedBox(width: 6),
                    Text(
                      open ? 'Abierto ahora' : 'Cerrado ahora',
                      style: TextStyle(color: color, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (setting.updatedAt != null)
                Text(
                  'Modificado ${formatShortDate(setting.updatedAt!)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: Icon(icon, color: enabled ? AppColors.primary : AppColors.textSoft),
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: enabled ? AppColors.text : AppColors.textSoft,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
