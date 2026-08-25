import 'package:intl/intl.dart';

final _dateFmt = DateFormat('dd MMM yyyy');

String formatDate(DateTime? d) => d == null ? '—' : _dateFmt.format(d);

/// null when there is no expiry.
int? daysUntil(DateTime? expiry) {
  if (expiry == null) return null;
  final now = DateTime.now();
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(expiry.year, expiry.month, expiry.day);
  return b.difference(a).inDays;
}

String expiryLabel(DateTime? expiry) {
  final d = daysUntil(expiry);
  if (d == null) return 'No expiry';
  if (d < 0) return 'Expired ${-d}d ago';
  if (d == 0) return 'Expires today';
  if (d <= 30) return 'Expires in ${d}d';
  return 'Valid till ${formatDate(expiry)}';
}
