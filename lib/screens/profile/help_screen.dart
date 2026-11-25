import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';

const _faqs = [
  ('Bagaimana cara menambahkan hewan peliharaan?', 'Buka Beranda lalu ketuk "+ Tambah Hewan Peliharaan". Pilih jenis hewan, isi nama, jenis kelamin, dan tanggal lahir (wajib; perkirakan saja bila tidak tahu pastinya), kemudian ketuk Simpan.'),
  ('Bagaimana cara kerja geofencing?', 'Kamu menentukan area aman berbentuk lingkaran di sekitar rumah. Saat hewan keluar atau masuk area itu, PawFinder langsung mengirim notifikasi dan mencatatnya di Riwayat.'),
  ('Mengapa lokasi hewan terlambat diperbarui?', 'Lokasi dikirim kalung GPS sesuai interval pembaruan. Interval yang lebih pendek lebih akurat tetapi menguras baterai. Cek juga sinyal GPS dan Mode Hemat Daya pada Pengaturan.'),
  ('Berapa lama baterai kalung bertahan?', 'Daya tahan bergantung pada pemakaian dan kekuatan sinyal. Kamu akan menerima notifikasi saat baterai tinggal 20%.'),
  ('Bagaimana jika kalung tidak terhubung?', 'Pastikan kalung menyala dan nomor seri sudah benar. Buka Detail Perangkat lalu Koneksi Alat: di sana terlihat data yang masuk secara langsung, status kabel USB di server, dan saran perbaikan otomatis.'),
  ('Bagaimana menghubungkan kalung lewat kabel USB?', 'Colok Arduino kalung ke komputer yang menjalankan server PawFinder memakai kabel data, lalu jalankan server dengan "npm run start:usb". Buka Hubungkan GPS > tab Kabel USB: alat yang terdeteksi muncul di sana, ketuk Pasangkan. Bluetooth tidak dipakai.'),
  ('Mengapa status Online tetapi lokasi belum muncul?', 'Alat sudah terhubung tetapi modul GPS belum mendapat sinyal satelit, biasanya karena berada di dalam ruangan. Bawa ke luar ruangan dengan langit terbuka dan tunggu 1–5 menit; lokasi terakhir tetap dipertahankan.'),
  ('Apakah data saya aman?', 'Data lokasi dikirim melalui koneksi ke server PawFinder dan hanya dapat diakses oleh akunmu.'),
];

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _open = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Bantuan & FAQ'),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(PF.margin, 8, PF.margin, 28),
              itemCount: _faqs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final open = _open == i;
                return Pressable(
                  onTap: () => setState(() => _open = open ? null : i),
                  scale: 0.99,
                  child: PFCard(
                    padding: const EdgeInsets.all(16),
                    radius: 18,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(_faqs[i].$1, style: tx.bodyStrong)),
                        AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary)),
                      ]),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: open ? Padding(padding: const EdgeInsets.only(top: 10), child: Text(_faqs[i].$2, style: tx.bodySecondary.copyWith(fontSize: 14))) : const SizedBox(width: double.infinity),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
