import 'package:intl/intl.dart';

const appLocale = 'es_CO';

final _integer = NumberFormat('#,##0', appLocale);
final _kilos = NumberFormat('#,##0.#', appLocale);
final _percent = NumberFormat('#,##0.0', appLocale);

String formatMoney(double value) => '\$ ${_integer.format(value.round())}';

final _millions = NumberFormat('#,##0.#', appLocale);

/// Valores grandes en millones (p. ej. "$ 245,3 M"), para ejes y textos compactos.
String formatMoneyShort(double value) =>
    value.abs() >= 1e6 ? '\$ ${_millions.format(value / 1e6)} M' : formatMoney(value);

String formatDayLabel(DateTime value) => DateFormat("EEEE d 'de' MMMM", appLocale).format(value);

String formatMonth(DateTime value) {
  final text = DateFormat("MMMM 'de' yyyy", appLocale).format(value);
  return text[0].toUpperCase() + text.substring(1);
}

String formatKilos(double value) => '${_kilos.format(value)} kg';

String formatQuantity(double value) => _kilos.format(value);

/// Cómo se cuentan las cantidades vendidas: kilos (cárnicos) o unidades (Carnes Frías).
class QtyUnit {
  const QtyUnit(this.code);

  static const kilos = QtyUnit('kg');

  final String code;

  bool get isUnits => code == 'und';

  /// "Kilos" / "Unidades".
  String get label => isUnits ? 'Unidades' : 'Kilos';

  /// "kilos" / "unidades".
  String get word => label.toLowerCase();

  String get soldLabel => isUnits ? 'Unidades vendidas' : 'Kilos vendidos';

  String format(double value) => isUnits ? '${_integer.format(value.round())} und' : formatKilos(value);
}

String formatPercent(double ratio) => '${_percent.format(ratio * 100)} %';

String formatInt(num value) => _integer.format(value);

String formatDateTime(DateTime value) => DateFormat('dd/MM/yyyy, hh:mm a', appLocale).format(value);

String formatShortDate(DateTime value) => DateFormat('d MMM', appLocale).format(value).replaceAll('.', '');

String formatDate(DateTime value) => DateFormat('d MMM yyyy', appLocale).format(value).replaceAll('.', '');

String formatTime(DateTime value) => DateFormat('h:mm a', appLocale).format(value);

String formatApiDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
