/// Human-readable size, e.g. `1.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

/// Time left until [expiresAt], e.g. `23h 10m`, `4m`, or `expired`.
String formatRemaining(DateTime expiresAt, [DateTime? now]) {
  final left = expiresAt.difference(now ?? DateTime.now());
  if (left.isNegative) return 'expired';
  if (left.inDays >= 1) return '${left.inDays}d ${left.inHours % 24}h';
  if (left.inHours >= 1) return '${left.inHours}h ${left.inMinutes % 60}m';
  if (left.inMinutes >= 1) return '${left.inMinutes}m';
  return '<1m';
}

/// Human-readable duration label, e.g. `10 minutes`, `1 hour`, `7 days`.
String formatDuration(Duration d) {
  String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';
  if (d.inDays >= 1) return plural(d.inDays, 'day');
  if (d.inHours >= 1) return plural(d.inHours, 'hour');
  return plural(d.inMinutes, 'minute');
}
