# OpenWrt 19.07.9 — TP-Link TL-WR841HP v3

Workflow GitHub Actions untuk target ath79/generic dengan konfigurasi:
- LuCI minimal
- Wi-Fi aktif
- openNDS terpasang tetapi service disabled
- Paket IPv6 userland dan PPP/PPPoE dihilangkan
- Kernel ABI diperiksa terhadap `4.14.267-1-b84a5a29b1d5ae1dc33ccf9ba292ca1d`
- Artifact factory dan sysupgrade

## Dukungan perangkat wajib

OpenWrt 19.07.9 tidak menyediakan profil WR841HP v3 secara bawaan. Masukkan
patch backport yang sudah diverifikasi ke `patches/` (DTS, board/device
definition, dan image recipe). Build sengaja dihentikan jika patch tidak ada
atau profil tidak ditemukan. Jangan flash image untuk perangkat lain.

## Kernel ABI dan distfeed

Nilai ABI diperiksa dari paket kernel hasil build. Mengganti string versi
kernel saja tidak membuat ABI cocok. Kernel config, patch, dan source revision
harus menghasilkan identitas ABI yang diminta. Workflow tidak mematikan
kernel IPv6 secara paksa karena perubahan Kconfig dapat mengubah ABI dan
merusak kompatibilitas modul kernel dari distfeed.

## Menjalankan

1. Buka tab **Actions**.
2. Pilih **Build OpenWrt 19.07.9 - TL-WR841HP v3**.
3. Klik **Run workflow**.
4. Unduh artifact jika build berhasil.

## Catatan

- Ukuran image dibatasi 7808 KiB sebagai pagar konservatif untuk flash 8 MiB.
- Wi-Fi dinyalakan pada first boot. Segera atur WPA2 password sebelum router
  dipakai pada jaringan nyata.
- Jangan menghapus paket inti seperti logd, netifd, dnsmasq, procd, atau
  komponen driver Wi-Fi untuk mengejar ukuran.
- Kernel ABI dan bootability tetap harus diverifikasi pada hardware sebelum
  digunakan.
