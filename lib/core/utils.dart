const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const _monthLong = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

/// Mengubah waktu ke WIB (UTC+7). Field year/month/day/hour pada hasilnya adalah waktu WIB.
DateTime wib(DateTime d) => d.toUtc().add(const Duration(hours: 7));

DateTime wibNow() => wib(DateTime.now());

String two(int n) => n.toString().padLeft(2, '0');

/// "14:32"
String fmtTime(DateTime d) {
  final w = wib(d);
  return '${two(w.hour)}:${two(w.minute)}';
}

/// "24 Sep 2025" — memakai field tanggal apa adanya (sudah WIB atau tanggal pilihan).
String fmtDateShort(DateTime d) => '${d.day} ${_monthShort[d.month - 1]} ${d.year}';

/// "24 September 2025"
String fmtDateLong(DateTime d) => '${d.day} ${_monthLong[d.month - 1]} ${d.year}';

String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "Hari ini, 24 Sep 2025" / "Kemarin" / "23 Sep 2025" (parameter: tanggal WIB)
String dayHeader(DateTime wibDate, {DateTime? now}) {
  final n = now ?? wibNow();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(wibDate.year, wibDate.month, wibDate.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Hari ini, ${fmtDateShort(d)}';
  if (diff == 1) return 'Kemarin';
  return fmtDateShort(d);
}

/// 2345 -> "2.345"
String fmtInt(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}

/// 1.2 -> "1,2"
String fmtDecimal(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

String fmtRadius(double meters) => meters >= 1000 ? '${fmtDecimal(meters / 1000)} km' : '${meters.round()} m';

int _monthsBetween(DateTime from, DateTime to) {
  var m = (to.year - from.year) * 12 + to.month - from.month;
  if (to.day < from.day) m--;
  return m < 0 ? 0 : m;
}

/// "2 th" / "8 bln"
String ageShort(DateTime? birth, {DateTime? now}) {
  if (birth == null) return '—';
  final m = _monthsBetween(birth, now ?? DateTime.now());
  return m >= 12 ? '${m ~/ 12} th' : '$m bln';
}

/// "1 tahun" / "8 bulan"
String ageLong(DateTime? birth, {DateTime? now}) {
  if (birth == null) return '';
  final m = _monthsBetween(birth, now ?? DateTime.now());
  if (m >= 12) return '${m ~/ 12} tahun${m % 12 > 0 ? ' ${m % 12} bulan' : ''}';
  return m == 0 ? 'Baru lahir' : '$m bulan';
}

/// Teks relatif untuk "Baru diperbarui".
String updatedAgo(DateTime? t) {
  if (t == null) return 'Belum ada data';
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 20) return 'Baru diperbarui';
  if (s < 60) return '$s detik lalu';
  if (s < 3600) return '${s ~/ 60} menit lalu';
  if (s < 86400) return '${s ~/ 3600} jam lalu';
  return '${s ~/ 86400} hari lalu';
}

String firstName(String full) => full.trim().split(RegExp(r'\s+')).first;
