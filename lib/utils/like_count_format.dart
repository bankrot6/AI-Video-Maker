String formatLikeCount(int n) {
  if (n < 0) return '0';
  if (n < 1000) return '$n';
  if (n < 10_000) {
    final s = (n / 1000).toStringAsFixed(1);
    return s.endsWith('.0') ? '${s.substring(0, s.length - 2)}K' : '${s}K';
  }
  if (n < 1_000_000) {
    return '${(n / 1000).floor()}K';
  }
  if (n < 10_000_000) {
    final s = (n / 1_000_000).toStringAsFixed(1);
    return s.endsWith('.0') ? '${s.substring(0, s.length - 2)}M' : '${s}M';
  }
  return '${(n / 1_000_000).floor()}M';
}
