import 'package:intl/intl.dart';

int parseMinorUnits(String value) {
  final normalized = value.replaceAll(',', '').trim();
  final parsed = double.tryParse(normalized) ?? 0;
  return (parsed * 100).round();
}

String formatMoney(int minorUnits, {String symbol = 'Rs. '}) {
  final amount = minorUnits.abs() / 100;
  final formatted = NumberFormat('#,##0.##').format(amount);
  return '${minorUnits < 0 ? '-' : ''}$symbol$formatted';
}

String formatInputAmount(int minorUnits) =>
    (minorUnits / 100).toStringAsFixed(2);
