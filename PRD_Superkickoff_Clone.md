# PRD — Game Manajer Sepak Bola (Klon Terinspirasi "Superkickoff")

> **Status:** Draft v1.0
> **Tujuan dokumen:** Blueprint teknis & produk untuk membangun game manajer sepak bola baru dari nol (menggunakan AI-assisted development), dengan nuansa gameplay seperti Superkickoff.
> **Catatan hukum:** Dokumen ini mendeskripsikan **mekanik game** (genre tidak bisa di-copyright). Untuk implementasi, **gunakan aset orisinal** (logo, jersey, nama tim/pemain fiktif atau berlisensi), jangan menyalin aset, artwork, teks UI, atau data berlisensi dari game asli. Lihat §16.

---

## 1. Ringkasan Eksekutif

Bangun game **manajer sepak bola / soccer manager simulator** untuk Android (Flutter), bertema offline-first dengan data lokal SQLite yang kaya (254 negara, ±2.000 klub, ±55.000 pemain), simulasi pertandingan, taktik, transfer, kontrak, kompetisi liga & piala (nasional + internasional), finansial klub, sistem hadiah, lalu monetisasi lewat coins/IAP/subscription/ads.

**Pilares produk:**
1. **Data raksasa & realistis** — database lokal besar, bisa dimainkan tanpa internet.
2. **Simulasi mendalam** — mesin pertandingan berbasis event + varian "simulasi kilat".
3. **Karier panjang** — multi-temporada, transfer, kontrak, hadiah, ranking dunia.
4. **Kustomisasi** — buat klub sendiri, edit liga/pemain, komunitas aset.
5. **Monetisasi non-agresif** — coins, item konsumabel, subscription opsional.

---

## 2. Tujuan & Metrik Keberhasilan

| Tujuan | Metrik |
|---|---|
| Onboarding cepat | Pemain bisa mulai pertandingan pertama < 5 menit |
| Retensi | D1 > 35%, D7 > 12%, D30 > 5% |
| Sesi | Rata-rata 15–25 menit, 2–3 sesi/hari |
| Monetisasi | ARPDAU sehat, conversion ke subscription 1–3% |
| Kualitas | Crash-free rate > 99.5% |
| Performa | Simulasi 1 pertandingan < 500 ms di HP mid-range |

---

## 3. Platform & Arsitektur Teknis

- **Klien:** Flutter (Dart), target Android (min SDK 24+, target 34+). Opsional iOS fase 2.
- **Penyimpanan utama:** SQLite lokal (`sqflite`) — sumber kebenaran data permainan saat offline.
- **Backend (opsional, fase 2):** Firebase (Auth, Firestore/RTDB, Crashlytics, Remote Config, Analytics, Functions).
- **Auth:** Google Sign-In, Apple Sign-In, Email/Password, plus mode "tanpa Play Services".
- **Aset:** bundel di APK (base DB + assets) dan/atau unduh dari paket komunitas.
- **Pola state:** Provider / Riverpod setara.
- **Lokalisasi:** multi-bahasa (lihat §11).

**Prinsip arsitektur:**
- Offline-first; sinkronisasi cloud hanya untuk akun, backup, konten komunitas, dan validasi IAP.
- Pemisahan tegas: `Database` (raw SQL + model), `Simulation` (algoritma murni), `UI` (widget), `Providers` (state).

---

## 4. Target Audiens

- Penggemar sepak bola & football manager (Football Manager, Top Eleven, Dream League Soccer, Soccer Manager).
- Pemain kasual yang ingin progres karier tanpa harus hadir tiap pertandingan (simulasi kilat).
- Penggemar kustomisasi (buat klub, edit liga, unduh aset komunitas).

---

## 5. Core Gameplay Loop

```
Mulai Karier → Pilih Klub/Liga → Susun Taktik & Lineup
      → Jalankan Pertandingan (simulasi penuh / kilat)
      → Dapat Hasil, Statistik, Cuán (uang), Pengalaman
      → Kelola Transfer, Kontrak, Latihan, Finansial
      → Lanjut ke Pertandingan Berikutnya → Akhir Musim
      → Hadiah & Promosi/Degradasi → Musim Baru
```

**Loop harian:** cek inbox/notifikasi → latihan/recuperasi energi → susun lineup → simulasikan → kelola keuangan & pasar.

---

## 6. Mode Permainan

1. **Karier (Career)** — mode utama, multi-temporada.
2. **Simulasi Cepat (BotonSimulacionRapida)** — simulasikan banyak pertandingan/sekaligus tanpa menonton.
3. **Simulasi Penuh / Live** — tonton pertandingan dengan timeline event, VAR, penalti.
4. **Editor / Kustom** — buat liga, ubah klub, edit pemain, buat tim sendiri dari nol.
5. **Komunitas** — unduh paket aset (logo/jersey) buatan pemain lain.
6. **Tamu/Guest** — main cepat tanpa akun.

---

## 7. Alur Mulai Permainan Baru (Wizard)

**Step 0 — Pilih Basis Data**
- Pilih dataset/liga awal (misal edisi musim 2025). Opsi editor.

**Step 1 — Identitas**
- Buat nama manajer (Entrenador), negara, foto (image picker + crop).

**Step 2 — Pilih Klub**
- Pilih dari daftar klub (2014 klub), atau **buat klub sendiri**:
  - Nama, singkatan (abrev), tahun berdiri (fundación).
  - Pilih/edit **stadion** (nama, kota, kapasitas: general/plateas/tribunas/palcos).
  - **Editor crest/escudo** (kanvas + addon layer) → logo kustom.
  - Susun **pemain** awal (cari dari market, pilih template).

**Step 3 — Pilih Liga/Kompetisi**
- Pilih liga gratis (kuota liga gratis terbatas; sisanya via subscription).
- Konfigurasi negara & cupos (kuota internasional per negara).

**Step 4 — Konfirmasi & Generate Dunia**
- Proses "CargandoQuilombo": generate fixture, kalkulasi kekuatan, dst.
- Simpan sebagai save game.

---

## 8. Konten & Cakupan Data

**Skala data referensi (edisi 2025):**

| Entitas | Jumlah |
|---|---|
| Negara (paises) | 254 |
| Klub (eq_equipos) | 2.014 |
| Pemain (jug_jugadores) | 55.624 |
| Pelatih (eq_entrenadores) | 2.014 |
| Stadion (eq_estadios) | 2.014 |
| Turnamen (tor_torneos) | 225 |
| Posisi | 11 |
| Kemampuan/habilidad | 25 |
| Sponsor | 19 |
| Divisi | 5 |

### 8.1 Skema Database (ringkas)

**Klub & Orang**
- `eq_equipos` (klub): `equid`, `equi_abrev`, `equi_nombre`, `equi_funda` (tahun berdiri), `equi_valor`, `equi_poder`, `equi_presupuesto` (budget), `equi_pts`, `equi_estaid` (stadion), `equi_paid` (negara), `equi_entid` (pelatih), `equi_division`.
- `eq_entrenadores` (pelatih): `entid`, `en_nombre`, `en_edad`, `en_paid`, `en_pts`.
- `eq_estadios` (stadion): `estaid`, `es_nombre`, `es_ciudad`, `es_tot_general/plateas/tribunas/palcos`, `es_max_*`.
- `eq_equipos_jugadores` (relasi klub–pemain).
- `eq_equipos_cesiones` (pemain pinjaman/loan).
- `paises` (negara): `paid`, `nombre`, `iso2`, `poder`, `pts`, `confederacion`.

**Pemain**
- `jug_jugadores`: `jugid`, `jug_nombre`, `jug_edad`, `jug_estatura`, `jug_star` (0–5 bintang), `jug_valor` (nilai pasar), `jug_salario`, `jug_perfil`, `jug_condicion` (0–100), `jug_poder` (kekuatan sekarang), `jug_potencial`, `jug_mercado` (status bursa), `jug_paid` (kewarganegaraan), `jug_posid` (posisi), `jug_titular` (starter/0–1), `jug_capitan`, `jug_pts`, `jug_habilidad_A/B`, `jug_experiencia`.
- `jug_habilidades`: master 25 kemampuan.
- `jug_jugadores_habilidades` (nilai per kemampuan).
- `jug_posiciones`: 11 posisi (POR, DC, DL, M, D + sub-tipe; `pos_tipo` 1=kiper, 2=bertahan, 3=tengah, 4=depan).
- `jug_posiciones_habilidades`.
- `jug_status`: Aktivo/Jubilado/Muerto.
- `jug_contratos`: kontrak (`jc_inicio`, `jc_fin`, `jc_status`, `jc_salario`, bonus gol/assist/MVP/juara/penampilan).
- `jug_premios`: trofi individu (Ballon d'Or, Golden Boot, dst).

**Kompetisi**
- `tor_torneos`: `torid`, `tor_nombre`, `tor_idiv` (divisi), `tor_organizacion` (1=liga, 2=kontinental/internasional, 3=piala nasional), `tor_vueltas`, `tor_inverso`, `tor_fecha_1/2`, `tor_label_1/2`, `tor_dias` (hari bermain), `tor_cupos` (jumlah peserta), `tor_pts`, `tor_asciende`, `tor_desciende`, `tor_premio_equipos/goleador/mvps`.
- `tor_temporadas`, `tor_temporadas_torneos`, `tor_temporadas_equipos`.
- `tor_grupos`, `tor_partidos`, `tor_partidos_incidencias`, `tor_partidos_jugadores`, `tor_partidos_paises`, `tor_partidos_jugadores_paises`.
- `tor_arbitros`, `tor_arbitros_tipos` (Bonachón, Justo, Inseguro, Bipolar, Cascarrabias).
- `tor_inabilitados` (skorsing/suspensi).
- `tor_cupos_internacionales` (kuota per negara).
- `tor_torneos_paises`, `tor_temporada_paises`.
- `tor_transferencias_jugadores`, `tor_transferencias_entrenadores`.

**Piala & Internasional**
- `tor_divisiones`: Primera/Segunda/Tercera/Cuarta/Sin Division.
- Piala internasional: `tor_cupos_internacionales`.

**Hadiah, Papan Skor, Sosial**
- `jug_premios`, `historial_ranking_mundial`, `historial_user`, `jus_stats`, `jus_stats_paises`.
- `Patrocinadores`, `Patrocinios`.
- `mensajes` (inbox notifikasi).
- `pais_entrenador`, `pais_jugador_convocatoria`.

**Trigger (logika in-DB)**
- `tVenderJugadores` — auto-jual pemain saat ada perubahan (mis. saat reset musim).
- `tCederJugadores` — auto-pinjamkan/cesión.
- `tLimpiarTemporada`, `tLimpiarTemporadaPaises` — reset data antar musim.
- `tDeleteOldMensajes` — bersihkan pesan lama.

**View:** `vPaises`, `vEstadios`, dll.

### 8.2 Atribut Pemain (25 kemampuan)

`Atajo, Reflejos, Anticipacion, Juego Aereo, Posicionamiento, Entradas, Marcacion, Recuperador, Remate, Cabeceo, Fuerza, Corpulencia, Velocidad, Agilidad, Creatividad, Pases, Resistencia, Tiros Libres, Regate, Tecnica, Liderazgo, Agresividad, Inteligencia, Control, Movilidad`

Tiap pemain punya 2 **habilidad utama (A/B)** yang menonjol, plus nilai lengkap. Rating diturunkan dari atribut ke `jug_poder` (kekuatan sekarang) dan `jug_potencial` (batas atas).

### 8.3 Posisi (11)

| ID | Abrev | Nama | Tipe |
|---|---|---|---|
| 1 | POR | Portero (kiper) | 1 |
| 2 | DC | Defensa Central | 2 |
| 3 | DC | Defensa Central Líbero | 2 |
| 4 | DL | Defensa Lateral | 2 |
| 5 | M | Mediocampista Defensivo | 3 |
| 6 | M | Mediocampista Ofensivo | 3 |
| 7 | M | Mediocampista Central | 3 |
| 8 | M | Mediocampista Extremo | 3 |
| 9 | D | Delantero Extremo | 4 |
| 10 | D | Centro Delantero | 4 |
| 11 | D | Delantero Media Punta | 4 |

---

## 9. Sistem Inti

### 9.1 Klub & Finansial
- **Anggaran (presupuesto):** dana untuk transfer & gaji.
- **Pendapatan:** tiket (entradas), sponsor, hadiah turnamen, jual pemain.
- **Pengeluaran:** gaji pemain, biaya operasional, beli pemain.
- **Tiket stadion berjenjang:** General, Plateas, Tribunas, Palcos (kapasitas + harga berbeda). Hitung okupansi dari performa/aficion.
- **Sponsor** (`Patrocinadores`, `Patrocinios`): level sponsor, target/objektif, reward unik/base.
- **Monedas/Coins** (mata uang IAP) dipisah dari uang klub.

### 9.2 Pasar Transfer
- **Bursa pemain (mercado):** pemain berstatus `jug_mercado`.
- **Beli/jual pemain**, negosiasi (oferta, contra-offer, analisa oferta).
- **Ventas Express** — jual cepat pemain.
- **Transfer window** per musim; transfer pemain & pelatih.
- **Algoritma AI** (`AlgFichajesBackground`): klub AI cari & beli pemain otomatis.

### 9.3 Kontrak & Negosiasi
- Durasi kontrak, gaji, dan bonus: gol, assist, MVP, juara, penampilan.
- Notifikasi **kontrak akan berakhir/expired**, renewal, "kontrak mal-pagado" vs "kontrak bagus".
- Bisa pecah kontrak / pemain minta naik gaji.

### 9.4 Pinjaman (Cesiones)
- Pinjamkan / pinjam pemain dengan tanggal mulai–selesai, durasi bulan.
- Status cesión: permintaan, disetujui, ditolak, selesai, pemain tidak senang, terima kasih.
- `tCederJugadores` untuk auto-proses antar musim.

### 9.5 Kondisi, Energi & Medis
- `jug_condicion` (0–100): kebugaran.
- **Energía** (stamina) pemain — turun saat bertanding, dipulihkan dengan **Bebida/Makanan Energética**.
- **Cedera (lesión):** acak saat pertandingan/latihan; perlu **Kit Médico** & waktu pemulihan.
- **Pelatihan** untuk naikkan atribut/`jug_experiencia`.

### 9.6 Takik & Lineup
- Formasi (tactica/alineación) dari daftar formasi (AlgFormacionTactica, AlgGeneradorTactica).
- Assign pemain ke posisi, kapten, starter (`jug_titular`).
- **Once Ideal** (best XI otomatis).
- Efek kondisi/energi/moral terhadap performa.

### 9.7 Moral & Dinamika Skuad
- **Moral/felicidad/añimo** pemain, **confianza** (kepercayaan), **afición** (dukungan fans).
- Reaksi: pemain senang/marah (`JUGADOR_ENOJADO`), rage quit, permintaan transfer.

---

## 10. Mesin Simulasi Pertandingan

**Input:** kekuatan kedua tim (poder), taktik, kondisi/energi/moral pemain, rating individu, home/away, tipe wasit.

**Output:** skor + daftar **insiden/event** pertandingan.

**Jenis event (dari data game):**
```json
{
  "amarilla":  (kartu kuning),
  "atajada":   (penyelamatan kiper),
  "autogol":   (gol bunuh diri),
  "cambio":    (substitusi),
  "gol":       (gol),
  "lesion":    (cedera),
  "penalti":   (penalti),
  "roja":      (kartu merah),
  "salvada":   (sapuan/clearance)
}
```
Setiap event punya bobot, durasi, dan efek ke skor/statistik.

**Fitur simulasi:**
- **Simulasi penuh (live):** timeline menit demi menit, animasi lapangan (Canvas), gol, kartu, cedera, substitusi manual, timer waktu tambahan.
- **VAR:** review gol/penalti, animasi CanvasVAR, ModalVAR.
- **Penalti (Penal/Penalty):** pemilihan penendang, simulasi adu penalti.
- **Simulasi kilat:** proses cepat semua pertandingan (termasuk pertandingan tim AI).
- **Status partida:** menjeda, simpan, rage quit handling.
- **Statistik pasca-pertandingan:** gol, assist, MVP, menit main, rating, possessions.
- **Penyebab cedera (ModalLesion)**, **kartu & skorsing** (`tor_inabilitados`).

**Algoritma pendukung:** AlgPartido, AlgFixture (penyusun jadwal), AlgEquipos, AlgJugadores, AlgSeleccionJugadoresPais.

---

## 11. Kompetisi & Turnamen

### 11.1 Struktur
- **Liga domestik** (tor_organizacion=1, 116 turnamen): multi-divisi (Primera–Cuarta), sistem poin, promosi/degradasi (`tor_asciende`/`tor_desciende`).
- **Piala nasional** (tor_organizacion=3, 60 turnamen): knockout (Copa Mx, FA Cup, Copa do Brasil, Copa del Rey, Copa Italia, DFB-Pokal, Coupe de France, Copa Argentina, Copa de Portugal, Copa Colombia, KNVB Beker, King's Cup, Türkiye Kupası, U.S. Open Cup, dll).
- **Kontinental/internasional** (tor_organizacion=2, 49 turnamen):
  - **UEFA:** Champions League, Europa League, Super Cup, Intercontinental.
  - **CONMEBOL:** Libertadores, Sudamericana, Recopa Sudamericana.
  - **CONCACAF:** Champions Cup, Leagues Cup, Copa Oro.
  - **AFC:** AFC Champions Elite, AFC Champions Two, Champions Asia.
  - **CAF:** CAF Champions, Champions Africa.
  - **Supercups** nasional (Argentina, Brazil, Chile, Costa Rica, Guatemala, Thailand, Poland, Spanyol, dll).
  - **Piala Dunia (World Cup)** & **Club World Cup (Mundial de Clubes)** format baru.
  - **Piala regional:** Liga MX (Liguilla), Liga Argentina (Liguilla), Liga Colombia (Cuadrangulares), Liga Guatemala (Liguilla), Copa América, Eurocopa.

### 11.2 Format fase
- Fase grup, fase liga (format baru Champions), fase gugur/octavos, liguilla, repechaje, cuadrangulares, playoff promosi.

### 11.3 Fixture Engine
- Generator jadwal per turnamen: `tor_dias` (hari main), `tor_vueltas` (putaran), `tor_inverso` (home/away), tanggal (`tor_fecha_1/2`).
- Modul khusus: FixtureCopas, FixtureChampions*, FixtureLigaArgentina/Colombia, FixtureLeaguesCup, FixtureLiguilla, dst.

### 11.4 Klasemen & Statistik
- Tabel klasemen (TablaGeneral), panel top-skorer (PanelGoleadores), statistik tim & pemain per turnamen.
- Klasemen negara (paises.pts) & ranking dunia.

---

## 12. Hadiah & Ranking

### 12.1 Trofi Individu (ModalPremiosBalonOro)
- **Balón de Oro** (Ballon d'Or)
- **Bota de Oro** (Golden Boot / top skorer)
- **Guante de Oro** (Golden Glove / kiper terbaik)
- **Mejor Joven** (pemain muda terbaik)
- **MVP** turnamen/musim
- **Once Ideal** (best XI)
- Trofi tim (Campeón liga/piala), pemain legenda (CoronaGoat).

### 12.2 Ranking
- **Ranking mundial** (klub & negara) historis (`historial_ranking_mundial`).
- Statistik pemain lintas musim (`JugadorAnioAnterior`).

### 12.3 Trofeos (layar Trofeos)
- Koleksi trofi karier manajer & klub.

---

## 13. Item / Toko / Inventory (UsoItems)

**Konsumabel & utilitas:**
| Item | Fungsi |
|---|---|
| Bebida Energética | Pulihkan energi seluruh pemain |
| Kit Médico | Percepat pemulihan cedera |
| Kit Apelación | Banding kartu/skorsing |
| Pase Anti-Despido | Cegah pemecatan manajer |
| Poder Extra (individual) | Tambah kekuatan pemain |
| Poder Extra Equipo | Tambah kekuatan tim |
| Convertir Super Estrella | Ubah pemain jadi superstar |
| Jugadores Leyenda | Dapat pemain legenda (acak/pilihan) |
| Cambio Nombre Equipo | Ganti nama klub |
| Cambio Nombre Estadio | Ganti nama stadion |
| Kit Estadio | Tingkatkan stadion |
| Botón Cambio Coins | Tukar coins |

**Toko (Tienda):**
- Beli **Coins** (CardCoins, BotonCoins).
- Beli **liga tambahan** (CardLigas) — akses liga di luar kuota gratis.
- **Subscription** (CardSuscripcion, PaywallSuscripciones, WidgetSuscripcionActiva): plan **semanal/mensual**.
- **ModalItem**, **ModalHistorial** (riwayat pembelian).
- **Inventory** (Inventario).

**Rarity artikel (ARTICULO_RAREZA):** Comun, Raro, Épico, (Legendarisch/Mítico opsional).

---

## 14. Akun, Auth & Sinkronisasi

- **Google Sign-In** (GoogleButton), **Apple Sign-In** (AppleButton), **Email/Password**, tombol **No Play Services** (NoPlayServicesButton) untuk perangkat tanpa Google Play Services.
- **WizardNuevoUsuario** — pembuatan profil pengguna.
- **ModalLinkearCuenta** — hubungkan akun (guest → akun).
- Data user (profil, coins, item, subscription, progres) disimpan di cloud (Firebase) + cache lokal.
- **AjustesFirebase**, **PerfilFirebase**, **AssetComunidad**.
- GDPR: hapus akun & data (pesan konfirmasi multi-bahasa sudah ada di game asli).

---

## 15. Fitur Komunitas & Sosial

- **Comunidad:** unduh paket aset (logo, jersey, bendera) buatan pemain (`AssetComunidad`, `DescargaAssets`, `WidgetDescargaAutomatica`).
- **Torneo país** (tim nasional) & convocatoria pemain.
- Berbagi (share) hasil/screenshot (SharePlus).
- Papan peringkat & historial user.

---

## 16. Monétisasi

| Kanal | Deskripsi |
|---|---|
| **Coins (soft/hard currency)** | Beli item, liga, pemain legenda |
| **IAP** | Paket coins, item premium |
| **Subscription** | Plan mingguan/bulanan → liga tak terbatas, rewards harian |
| **Rewarded Ads** | AdBanner, AdButton, HeaderAdWidget → hadiah coins/energi |
| **Liga tambahan** | Beli akses liga per negara |

Prinsip: monetisasi tidak memblokir progres inti; pemain F2P tetap bisa menikmati liga dasar.

---

## 17. UI/UX — Daftar Layar Utama

**Start & Setup**
- StartScreen, Wizard (Step0–3), CrearEquipo (crest/estadio/jugadores), Editor (CrearLiga, Cupos, Ligas, Paises), ModalSeleccionarBaseDB.

**Home / Navigasi**
- CustomDrawer/homeDrawer, appTheme, HeaderAdWidget, BotonCalendario, BotonCopado2, BotonOnceIdeal, BotonAcelerar.

**Klub & Skuad**
- Plantilla, EquipoDetalle, Contratos (modal), Cesiones (ModalSolicitudCesiones), Inventario, UsoItemsModal.

**Pertandingan**
- Simulador (live & quick), PartidoWidget, Penal/Penalty, VAR, ModalLesion, ModalCampeon, ResumenPartidos.

**Kompetisi**
- TablaGeneral + widget per turnamen, PanelGoleadores, Calendario_Equipo, WidgetCopa.

**Premium & Sosial**
- Tienda, PaywallSuscripciones, Trofeos, Ranking, Comunidad, Mensajes/Notificaciones, Config (idioma, sonido, kontrak).

---

## 18. Lokalisasi

Game asli mendukung banyak bahasa (contoh terdeteksi: Español, English, Português, Italiano, Deutsch, Français, Bahasa Indonesia, Melayu, Nederlands, Dansk, Norsk, Svenska, Polski, Türkçe, dst).

**Rekomendasi klon:** mulai dari **Bahasa Indonesia + English + Español**, arsitektur i18n siap tambah bahasa (file `.arb` Flutter / tabel terjemahan).

---

## 19. Kebutuhan Non-Fungsional

- **Offline-first:** hanya butuh internet untuk auth, IAP, konten komunitas.
- **Performa:** DB query dioptimasi (index), simulasi paralel/isolate, hindari jank UI.
- **Ukuran:** base DB besar (~?MB) — pertimbangkan kompresi & unduh-on-demand untuk paket liga/aset.
- **Kompatibilitas:** Android 7+ (API 24+), ABI arm64-v8a (+ armeabi-v7a opsional).
- **Robustness:** save/backup (ekspor-impor DB), anti-corrupt, migrasi skema versi DB.
- **Analytics & crash:** Firebase Analytics + Crashlytics.
- **Kepatuhan:** GDPR (hapus akun), kebijakan anak (IAP/ads), lisensi data pemain/tim.

---

## 20. Strategi Produksi dengan AI (Roadmap)

**Fase 0 — Fondasi (MVP)**
- Setup Flutter + SQLite; skema DB inti (klub, pemain, posisi, liga).
- Start wizard minimal; pilih 1 liga.
- Simulasi pertandingan dasar (skor + event teks).
- UI: Plantilla, TablaGeneral, Calendario.

**Fase 1 — Karier Inti**
- Multi-temporada, transfer sederhana, kontrak, gaji.
- Klasemen, promosi/degradasi, piala nasional.
- Simulasi kilat.

**Fase 2 — Kedalaman**
- Atribut lengkap (25 habilidad), taktik & formasi, energi/cedera.
- Piala internasional (Champions, Libertadores, dll).
- Hadiah individu (Ballon d'Or, dll), ranking dunia.

**Fase 3 — Meta & Monetisasi**
- Coins, item, toko, subscription, rewarded ads.
- Komunitas aset, editor liga/klub/pemain, creator crest.

**Fase 4 — Sosial & Live Ops**
- Akun cloud, sinkronisasi, balance patch, live events, leaderboard.

**Peran AI dalam produksi:**
- Generate data pemain/tim fiktif masif (nama, atribut konsisten).
- Generate fixture & kalender otomatis.
- Generate aset UI (ikon, background) — tetap orisinal.
- Bantu balancing (tuning bobot simulasi).
- Generate terjemahan.

---

## 21. Ruang Lingkup MVP (Prioritas)

**Wajib (P0):**
- 1 negara + 1–2 liga, ~20 klub, ~500 pemain.
- Wizard mulai cepat + pilih klub.
- Lineup + taktik dasar.
- Simulasi pertandingan + hasil + klasemen.
- Save/load multi-temporada.

**P1:** transfer, kontrak, piala nasional, statistik.
**P2:** internasional, hadiah, ranking, item/coins.
**P3:** komunitas, editor, subscription, cloud.

---

## 22. Risiko & Mitigasi

| Risiko | Mitigasi |
|---|---|
| IP/legal (nama pemain/tim/logo) | Pakai data fiktif atau lisensi resmi; aset orisinal |
| Ukuran DB & performa | Index, pagination, isolate, unduh-on-demand |
| Balancing simulasi | Iterasi + analytics, tuning berbasis data |
| Auth Google gagal (re-signing) | Dukung email/password & mode guest tanpa Play Services |
| Kompleksitas turnamen | Bangun fixture engine generik + konfigurasi data-driven |

---

## 23. Lampiran — Pemetaan Tabel DB (untuk migrasi/klon)

**Klub/Orang:** `eq_equipos`, `eq_entrenadores`, `eq_estadios`, `eq_equipos_jugadores`, `eq_equipos_cesiones`, `paises`, `pais_entrenador`, `pais_jugador_convocatoria`
**Pemain:** `jug_jugadores`, `jug_habilidades`, `jug_jugadores_habilidades`, `jug_posiciones`, `jug_posiciones_habilidades`, `jug_status`, `jug_contratos`, `jug_premios`
**Kompetisi:** `tor_torneos`, `tor_temporadas`, `tor_temporadas_torneos`, `tor_temporadas_equipos`, `tor_grupos`, `tor_partidos`, `tor_partidos_incidencias`, `tor_partidos_jugadores`, `tor_partidos_paises`, `tor_partidos_jugadores_paises`, `tor_arbitros`, `tor_arbitros_tipos`, `tor_inabilitados`, `tor_cupos_internacionales`, `tor_torneos_paises`, `tor_temporada_paises`, `tor_transferencias_jugadores`, `tor_transferencias_entrenadores`, `tor_divisiones`
**Finansial/Sosial:** `Patrocinadores`, `Patrocinios`, `mensajes`, `historial_ranking_mundial`, `historial_user`, `jus_stats`, `jus_stats_paises`
**Trigger:** `tVenderJugadores`, `tCederJugadores`, `tLimpiarTemporada`, `tLimpiarTemporadaPaises`, `tDeleteOldMensajes`

---

*Dokumen ini disusun dari hasil reverse-engineering struktur data & fitur game referensi (skema SQLite, daftar layar/kelas Dart, string fitur, dan manifest). Gunakan sebagai acuan desain orisinal.*
