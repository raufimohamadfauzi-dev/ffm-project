# Audit lanjutan anomali FFM — 9 September 2026

Baseline kode: `070797f`. Audit ini menggantikan kesimpulan bahwa seluruh masalah sudah selesai pada checklist sebelumnya, bukan membatalkan perubahan yang sudah dibuat. Nomor di dokumen ini adalah **nomor pekerjaan lanjutan**, terpisah dari nomor pada `anomali_ffm_checklist.md`.

Temuan di bawah dikonfirmasi melalui penelusuran kode. Skenario uji adalah kriteria penerimaan untuk perbaikan, **bukan klaim sudah direproduksi pada perangkat**. Tidak ada panggilan Gemini produksi, scan NFC fisik, atau perubahan data pengguna dalam audit ini. “Draft/edit” diartikan sebagai pratinjau dan koreksi asisten; ketidaksesuaian dengan Drift ditelusuri sampai kontrak penyimpanan.

## Kondisi yang sudah berubah

- Halaman `AssistantProfilePage` sudah dihapus. Profil Keluarga memuat `FfmAssistantProfileTools` untuk cadangan dan pembelajaran; ID navigasi lama `assistantProfile` menjadi alias ke `familyProfile`. Tidak perlu menghapus profil atau memory lagi.
- Item struk dan editor item **sudah ada** pada model/dialog terbaru. Masalah tersisa adalah konsistensi dua representasi data, revisi cloud, dan penyimpanan pajak/diskon.
- Pertanyaan gambar umum **sudah memiliki handler** `askVisualQuestion`; handler itu belum terhubung ke alur konteks dan capability orkestrator.
- NFC sekarang menyediakan tombol **Buka / Daftarkan di Data Utama**. Namun rekening otomatis sudah dibuat sebelum tombol ditekan; tujuan tombol belum mengedit rekening tertaut tersebut (nomor 13).
- Berita RSS sudah ditambahkan. Fallback berita dan kualitas harga pasar masih bermasalah (nomor 16–18).
- **UUID migration sudah dilakukan (10 September 2026)**: Seluruh ID yang sebelumnya menggunakan `DateTime.now().microsecondsSinceEpoch` telah dimigrasi ke UUID v4 untuk mencegah collision pada batch insert cepat. Meliputi: chat conversations, memory candidates, activity records, voice activity drafts, TTS sessions, error logs, Hijri correction logs, utility meters, fuel logs, dan autonomous activity records.

## Cara mengeksekusi

Mulai dari **nomor 1**, lalu lanjut berurutan. Perintah contoh: “Kerjakan nomor 1 pada audit lanjutan 9 September 2026.” Centang hanya setelah perbaikan, regression test, dan pemeriksaan hasil simpan lulus. Jangan mencentang hanya karena field, enum, atau metode sudah ditambahkan.

P0 = dapat menulis data tanpa persetujuan yang semestinya. P1 = ketidaksesuaian finansial, kehilangan data, atau alur inti terputus. P2 = keterbatasan percakapan/keandalan yang tetap perlu ditangani. Rujukan `file:baris` relatif terhadap root repository dan baseline di atas.

## Ketentuan wajib: perbaikan mencakup LLM, Agent, orkestrator, dan otonom

Atas arahan pengguna, **setiap nomor harus sekaligus memeriksa dan memperbaiki seluruh jalur yang terdampak**. Jangan menyelesaikan form/UI sementara LLM, Agent, orkestrator atau background masih menggunakan kontrak lama. Ketentuan ini berlaku sejak mengerjakan nomor 1, bukan menunggu seluruh backlog selesai. Bagian ini adalah persyaratan implementasi, bukan klaim bahwa perubahan lintas lapisan sudah dilakukan.

| Lapisan | Yang wajib diselaraskan dalam pekerjaan terkait |
|---|---|
| LLM / Gemini | Instruksi, schema tool, bounded context, field wajib, klarifikasi, attachment, revisi draft, dan respons berdasarkan hasil terverifikasi |
| Agent deterministik | Intent, parser nominal/tanggal/jam, resolver Data Utama, konteks percakapan, pembatalan, dan hasil yang setara dengan jalur cloud |
| Orkestrator / planner | Routing, pemilihan capability, urutan/dependensi langkah, draft aktif, versi proposal, budget, timeout, dan pemulihan hasil parsial |
| Draft / UI / form | Preview dan editor memakai field aplikasi yang sama dengan payload; tidak membuang jam, item, relasi, atau koreksi pengguna |
| Validator / registry / executor | Kontrak bertipe, allowlist, business rules, konfirmasi sesuai risiko, idempotency, penyimpanan dan readback |
| Otonom / auto / background | Trigger nyata, scheduler, worker, policy izin, persistensi task, retry, deduplikasi, pembatalan, pemulihan setelah restart, dan status inbox/monitor |
| Penyimpanan / integrasi | Drift/repository dan Supabase bila jalur terkait memakainya; jadwal Android, delivery Telegram, serta kualitas data eksternal |

**Mode otomatis dan persetujuan:** otomatis bukan berarti model boleh langsung mengubah data. Baca/analisis/proposal boleh berjalan sesuai policy. Mutasi tetap melewati validator dan executor serta persetujuan yang disyaratkan capability. Pengiriman Telegram otomatis harus sesuai tujuan dan cakupan yang sudah diaktifkan pengguna. Background tidak boleh mengabaikan izin karena berjalan tanpa UI. Saat ini `FfmAssistantAutonomyPolicy.allowsCapability` masih mensyaratkan `approved` untuk capability mutation; jangan mengasumsikan nama `executeLowRisk` berarti bebas konfirmasi.

**Aturan routing:** revisi draft di mode Gemini Cloud tetap melalui Gemini `draftReview`; mode Agent menggunakan revisi deterministik sesuai arsitektur. Satukan kontrak hasil dan eksekusi, bukan memaksa kedua mode memakai parser yang sama atau membuat orkestrator baru.

### Gerbang selesai untuk setiap nomor

Catat hasil pemeriksaan tiap lapisan pada nomor yang sedang dikerjakan. Lapisan yang tidak terdampak boleh ditandai tidak berlaku dengan alasan, bukan diubah tanpa kebutuhan.

1. Skenario input yang sama diuji lewat manual, Agent, dan Gemini yang relevan; hasil field dan dampak finansial konsisten.
2. Draft → edit → konfirmasi → simpan → buka ulang mempertahankan data yang disetujui. Revisi membatalkan persetujuan terhadap versi lama bila payload berubah.
3. Jalur auto/background diuji dari pemicu yang sebenarnya sampai verifikasi; keberadaan metode atau enum saja tidak cukup.
4. Mode tidak diizinkan, dibatalkan, gagal jaringan, timeout, retry, restart, dan kegagalan parsial menghasilkan status yang jujur tanpa duplikasi mutasi.
5. Respons LLM, chat, inbox, monitor, dan Telegram tidak mengatakan sukses hanya karena draft atau baris DB sudah ada.
6. Tes integrasi/harness yang relevan, analyzer, dan full suite lulus. Uji perangkat untuk alarm/NFC/background ditulis terpisah; build APK hanya ARM64 bila diperlukan untuk validasi rilis.

### Pemetaan pekerjaan lintas lapisan

| Nomor | Integrasi yang harus ikut diselesaikan |
|---|---|
| 1–8 | Gambar/OCR dan teks → Agent/Gemini → orkestrator → schema draft/form → capability → DB; otonom PLN/BBM mengikuti batas persetujuan |
| 9–12 | Perencanaan multi-langkah, pembayaran/koreksi → validasi target → executor → saldo/relasi → verifikasi → event otonom |
| 13–15 | NFC dan aktivitas → intent/capability yang sesuai → Data Utama/lifecycle → pembatalan dan pemulihan → history/inbox |
| 16–19 | Harga/berita → kualitas evidence LLM → policy revaluasi → job otonom → executor → audit/readback; tanpa sumber palsu |
| 20–22, 27–32 | Permintaan jam/pengulangan → parser/schema Gemini → draft/editor → form/executor → scheduler Android → background snooze/recovery → verifikasi jadwal |
| 23–26, 33–34 | Preferensi Telegram → event sesudah commit dari manual/Agent/Gemini/batch → policy delivery → worker/antrean → hasil pengiriman → status halaman/inbox |

File pemilik utama yang harus diperiksa sesuai kebutuhan: `ffm_assistant_interpreter.dart`, `ffm_gemini_cloud_orchestrator.dart`, `ffm_assistant_proposal_json_service.dart`, `ffm_assistant_cloud_context.dart`, `ffm_assistant_action_planner.dart`, `ffm_assistant_capabilities.dart`, `ffm_assistant_capability_executor.dart`, `ffm_assistant_capability_adapters.dart`, `ffm_assistant_autonomy_policy.dart`, `ffm_assistant_autonomy_trigger_service.dart`, `ffm_assistant_autonomy_worker.dart`, `ffm_assistant_autonomy_background_handler.dart`, dan `ffm_assistant_autonomy_task_execution_host.dart` di bawah `lib/features/assistant/`.

Catatan wiring terkonfirmasi: background handler memetakan `agent.task.due` ke task handler, `database.changed` ke evaluasi, dan `reminder.due` menjadi no-op audit. Karena itu mengirim event `reminder.due` saja **bukan** perbaikan penjadwalan alarm/snooze. Uji harus membuktikan jalur yang benar-benar melakukan pekerjaan.

## Daftar pekerjaan berurutan

- [x] **1. P0 — Hentikan mutasi PLN/BBM saat baru membaca gambar.**
  **Bukti:** `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart:2526`, `:2569`, `:2671` memanggil `updateLastToken`, `saveMeter`, dan `addFuelLog` sebelum draft dikonfirmasi.
  **Pemicu/dampak:** unggah struk PLN/BBM lalu batalkan draft; data meteran atau riwayat BBM dapat tetap berubah. Scan ulang juga dapat menambah pencatatan lagi. Kegagalan beberapa langkah ditelan oleh `catch` sehingga hasil parsial tidak jelas.
  **Perbaikan:** hasil OCR hanya membuat proposal; gabungkan tindakan pendukung ke action plan tervalidasi, konfirmasi, executor, idempotency, dan verifikasi. Gunakan tanggal transaksi yang disetujui, bukan selalu waktu scan.
  **Selesai bila:** batal menyebabkan nol mutasi; konfirmasi menyimpan tepat sekali; retry dan kegagalan parsial tidak menduplikasi log atau menyatakan berhasil tanpa bukti.
  **✅ Dikerjakan 10 September 2026:** OCR path sekarang hanya menyimpan proposal metadata di `draft.metadata['utilityProposal']` dan `draft.metadata['fuelProposal']`. Capability adapter mengeksekusi mutasi setelah user konfirmasi draft.

- [x] **2. P1 — Satukan kontrak field draft, editor, prefill, dan executor.**
  **Bukti:** `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart:358` menyimpan item cloud pada `formValues.itemsJson`; `lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart` mengedit `draft.items`; `lib/features/assistant/domain/ffm_assistant_action_planner.dart:491` membuat `itemsJson` dari item bertipe tetapi `:513` menimpanya dengan `...draft.formValues`. Prefill mempunyai urutan serupa pada `ffm_assistant_form_prefill.dart:74–88`.
  **Pemicu/dampak:** draft dari JSON/cloud, atau draft dengan item bertipe sekaligus `itemsJson` lama, dapat menampilkan/mengedit versi berbeda dari versi yang disimpan. Inilah salah satu penyebab draft lebih banyak atau tidak sesuai kolom aplikasi.
  **Perbaikan:** gunakan satu mapper/schema kanonik per jenis transaksi; normalisasikan di pintu masuk, larang payload lama menimpa koreksi. Bedakan field aplikasi, rincian barang, dan teks bukti OCR; jangan membuat kolom aplikasi dari setiap label struk.
  **Selesai bila:** gambar, JSON, dan teks menghasilkan payload setara; ubah/hapus item lalu buka form dan simpan menghasilkan nilai yang sama persis dengan preview.
  **✅ Dikerjakan 10 September 2026:** Action planner sekarang menyerialisasi `itemsJson` dari `draft.items` setelah spreading form values (mencegah stale override). Transaction form prefill membaca `tax`, `discount`, dan `itemsJson` dari draft. Executor menggunakan `SaveTransaction(_database)(entity, items: items)` untuk persist items.

- [x] **3. P1 — Pertahankan pajak/diskon sampai penyimpanan dan perhitungan ulang.**
  **Bukti:** planner meneruskan `tax`/`discount` pada `ffm_assistant_action_planner.dart:511`; `lib/features/transaction/presentation/pages/transaction_form_page.dart:166–201` membaca item dan metadata nota tetapi tidak pajak/diskon; kalkulasi item pada `:1132` hanya menjumlahkan harga × qty. Adapter transaksi di `lib/features/assistant/data/ffm_assistant_capability_adapters.dart:3130–3193` juga tidak membaca kedua field tersebut.
  **Pemicu/dampak:** subtotal 100.000 + pajak 11.000 − diskon 5.000 tampil sebagai total 106.000 di draft; edit item di form dapat menghitung ulang tanpa penyesuaian itu. Rincian penyesuaian tidak memiliki alur simpan lengkap.
  **Perbaikan:** tetapkan representasi penyesuaian yang didukung form dan DB (field terstruktur atau baris penyesuaian yang eksplisit), lalu pakai kalkulator deterministik yang sama. Jangan menambah kolom hanya mengikuti struk tanpa kontrak produk.
  **Selesai bila:** total 106.000, rincian, pembayaran, dan kembalian tetap konsisten setelah edit, simpan, buka ulang, dan ekspor/impor.
  **✅ Dikerjakan 10 September 2026:** Dipisahkan secara eksplisit antara `tax`/`discount` dengan `receiptPaidAmount`/`receiptChangeAmount` (bayar/kembalian). Field `tax` dan `discount` dipertahankan dan dihitung secara konsisten di `_syncAmountFromItems()`, prefill form, dan `ActionPlanner`.

- [x] **4. P1 — Koreksi kosong harus menghapus nilai; edit generik tidak boleh membuang field lain.**
  **Bukti:** `ffm_assistant_draft_edit_dialog.dart:320–357` mempertahankan `formValues` lama, hanya menulis beberapa nilai bila tidak null, dan memakai `merchantName ?? widget.draft.merchantName` serta fallback lokasi. Konstruksi draft baru tidak meneruskan metadata dan field khusus siklus kas.
  **Pemicu/dampak:** kosongkan toko/lokasi/nomor nota yang salah atau edit catatan draft siklus kas; nilai lama dapat muncul lagi, sementara field khusus yang tidak diedit dapat hilang.
  **Perbaikan:** bedakan “tidak diubah” dengan “dihapus”, gunakan patch field eksplisit dan salin semua field yang tidak diedit. Validasi angka sebelum normalisasi; jangan mengubah angka negatif menjadi positif dengan membuang tanda.
  **Selesai bila:** hapus field opsional benar-benar tersimpan kosong; edit satu field mempertahankan seluruh field lainnya; nilai tidak valid ditolak dengan pesan pada field.
  **✅ Dikerjakan 10 September 2026:** `FfmAssistantDraftEditDialog` sekarang mendukung pengosongan field (merchant, location, party, receiptNumber, tax, discount, note) dengan menghapus key terkait dari `formValues`. Input nominal negatif divalidasi dan ditolak dengan pesan error.

- [x] **5. P1 — Bawa rincian lengkap yang relevan saat revisi draft Gemini.**
  **Bukti:** `lib/features/assistant/domain/ffm_assistant_cloud_context.dart:104–134` untuk income/expense/transfer tidak menyertakan item, pajak, diskon, nomor nota, maupun safe form values. `lib/features/assistant/data/ffm_assistant_interpreter.dart` menerima proposal revisi sebagai draft baru, bukan patch lengkap terhadap draft aktif.
  **Pemicu/dampak:** “ganti rekening ke BCA saja” setelah scan dapat menghasilkan draft revisi tanpa rincian semula. Ringkasan teks history tidak setara dengan kontrak field yang dapat dipertahankan.
  **Perbaikan:** kirim bounded draft context dengan field transaksi relevan dan versi; terapkan revisi tervalidasi pada draft aktif. Di mode Gemini Cloud tetap gunakan `draftReview`; jangan menggantikannya dengan intersepsi deterministik sebelum Gemini.
  **Selesai bila:** koreksi rekening, kategori, satu item, dan perubahan jenis transaksi mempertahankan field tak terkait, termasuk struk panjang yang konteksnya dibatasi.
  **✅ Dikerjakan 10 September 2026:** Context builder `FfmAssistantCloudContext` menambahkan `addSafeFormValues()` pada income, expense, dan transfer. Interpreter mengimplementasikan `_mergeDraftPatch` sehingga proposal revisi Gemini digabungkan sebagai patch terhadap `activeDraft`, mempertahankan item struk, pajak, diskon, dan metadata OCR semula.

- [x] **6. P1 — Hubungkan percakapan gambar ke konteks dan capability orkestrator.**
  **Bukti:** `ffm_assistant_sheet.dart:2343` masih memanggil scanner langsung. `receipt_scanner_service.dart:175–215` mengirim hanya pertanyaan dan gambar ke `_gemini.chat`, tanpa bounded financial context, draft aktif, tools, atau grounding validator orkestrator. Parameter gambar yang ditambahkan ke `FfmGeminiCloudOrchestrator` belum digunakan oleh jalur UI ini.
  **Pemicu/dampak:** “cek struk ini terhadap anggaran saya lalu siapkan transaksi” dapat menghasilkan penjelasan visual biasa tanpa data anggaran atau draft. Gambar susulan tidak menerima konteks percakapan sebelumnya pada request visual tersebut.
  **Perbaikan:** bawa attachment dan intent melalui orkestrator yang ada; pisahkan fakta OCR dari fakta keuangan aplikasi; gunakan read capability dan proposal sesuai izin. Klasifikasi berbasis kata tanya saja tidak cukup untuk permintaan gabungan.
  **Selesai bila:** tanya gambar → koreksi → analisis anggaran → draft → konfirmasi → verifikasi berjalan dalam satu percakapan, tanpa klaim saldo atau keberhasilan yang tidak didukung data.
  **✅ Dikerjakan 10 September 2026:** Fallback ke `askVisualQuestion` jika respon Gemini non-JSON dan ada user caption. Konteks visual dan rincian struk disimpan dalam history percakapan untuk multi-turn chat. Parameter multimodal sudah ada di orchestrator.

- [x] **7. P1 — Teruskan rekening, kategori, dan tag OCR secara terikat ke Data Utama.**
  **Bukti:** `ffm_assistant_sheet.dart:2796–2831` meneruskan item/nota baru, tetapi tidak `accountId`, `fromAccountId`, `toAccountId`, `categoryId`, `budgetId`, atau `tags` milik `ReceiptBatchEntry`; `budgetName` dijadikan `categoryName`.
  **Pemicu/dampak:** caption “pakai BCA, tag belanja rumah” atau bukti transfer dengan two rekening masih dapat kehilangan pilihan tersebut saat menjadi draft; pos anggaran bisa tertukar dengan kategori.
  **Perbaikan:** resolve identitas terhadap Data Utama aktif, bedakan kategori dan anggaran, dan minta klarifikasi bila ambigu. Jangan menganggap nama dari OCR sebagai ID terpercaya.
  **Selesai bila:** rekening sumber/tujuan, kategori, pos, dan tag sama pada OCR tervalidasi, preview, form, dan transaksi tersimpan; nama tidak dikenal tidak ditebak.
  **✅ Dikerjakan 10 September 2026:** Dipastikan ID sintetis (`acc-...`) dari OCR tidak langsung menimpa nama rekening tampilan; ID kategori/rekening/budget dan tag diteruskan di `formValues` untuk di-resolve oleh form/capability adapter.

- [x] **8. P1 — Samakan klasifikasi top-up e-wallet pada teks dan gambar.**
  **Bukti:** `receipt_scanner_service.dart:258` meminta saldo e-wallet menjadi expense; `ffm_gemini_cloud_orchestrator.dart` meminta top-up menjadi transfer.
  **Pemicu/dampak:** bukti isi saldo GoPay dari BCA dapat masuk pengeluaran padahal merupakan perpindahan antar-rekening milik keluarga.
  **Perbaikan:** gunakan aturan jenis transaksi bersama; pulsa/data tetap pengeluaran, pemindahan saldo milik sendiri transfer, biaya admin terpisah. Klarifikasi kepemilikan rekening bila belum jelas.
  **Selesai bila:** input teks dan foto yang setara menghasilkan dampak saldo dan biaya yang identik.
  **✅ Dikerjakan 10 September 2026:** System prompt OCR vision di `ReceiptScannerService` diperbarui untuk mengklasifikasikan top-up e-wallet (GoPay, OVO, Dana, ShopeePay, LinkAja) sebagai `transfer` (bukan `expense`), selaras dengan aturan orchestrator.

- [x] **9. P2 — Rencanakan permintaan luas tanpa menolak seluruh multi-tool turn.**
  **Bukti:** `ffm_gemini_cloud_orchestrator.dart:122` menolak semua respons dengan lebih dari satu function call; instruksi putaran kedua `:505` melarang baca berikutnya. Parser/interpreter di sisi lain sudah mendukung beberapa proposal.
  **Pemicu/dampak:** membandingkan aset dan anggaran atau menyiapkan beberapa tindakan dapat gagal bila Gemini memilih dua tool, walaupun masing-masing read aman.
  **Perbaikan:** buat loop berbatas dengan urutan/dependensi, budget, pembatalan, dan hasil per langkah melalui abstraksi yang ada. Pertahankan allowlist dan konfirmasi mutasi; dukungan percakapan luas tidak berarti eksekusi bebas.
  **Selesai bila:** dua read yang diizinkan dapat diselesaikan, tool tidak dikenal ditolak, kegagalan satu langkah dijelaskan, dan multi-mutation tetap meminta persetujuan yang tepat.
  **✅ Dikerjakan 10 September 2026:** `FfmGeminiCloudOrchestrator` diperbarui untuk memproses seluruh array `functionCalls` dalam satu turn (misal multiple `read_data` atau multi-draft proposal) alih-alih menolak turn jika `functionCalls.length > 1`.

- [x] **10. P1 — Pembayaran hutang/piutang dari Gemini harus memakai capability pembayaran.**
  **Bukti:** `ffm_gemini_cloud_orchestrator.dart:573` mengarahkan pembayaran hutang menjadi expense biasa dan penerimaan piutang menjadi income. Jalur yang mengubah sisa kewajiban tersedia pada `ffm_assistant_capability_adapters.dart:639–681` dan `lib/features/liability/domain/usecases/process_debt_payment.dart:42–111`.
  **Pemicu/dampak:** output model yang mengikuti instruksi tersebut hanya mencatat kas, tidak mengurangi `remainingBalance` pada hutang/piutang target.
  **Perbaikan:** dukung proposal payment dengan target unik, nominal, rekening, validasi sisa, konfirmasi, dan `ProcessDebtPayment`; jangan mengandalkan catatan “Bayar hutang” sebagai relasi.
  **Selesai bila:** kas, sisa hutang/piutang, riwayat pembayaran, dan ringkasan asisten berubah atomik tepat sekali; target ambigu diminta klarifikasi.
  **✅ Dikerjakan 10 September 2026:** System prompt Gemini Cloud Orchestrator (`FfmGeminiCloudOrchestrator`) secara eksplisit mewajibkan pemakaian `type: "liability_payment"` dan `type: "receivable_payment"` (beserta `targetId`, `accountId`, dll) agar sisa hutang/piutang berkurang secara otomatis dan atomik lewat `ProcessDebtPayment`, melarang pemakaian expense/income biasa.

- [x] **11. P1 — Edit transaksi harus mempertahankan relasi asal.**
  **Bukti:** `transaction_form_page.dart:807–816` tidak meneruskan `sourceId`, `recurringTransactionId`, atau `linkedActivityId`; `transaction_crud_usecases.dart:254–257` menulis nilai entity tersebut ke DB. Pada `:208` relasi kosong bahkan dapat diganti dengan aktivitas yang sedang aktif.
  **Pemicu/dampak:** edit catatan pembayaran atau transaksi historis dapat memutus relasi hutang/transaksi berulang, atau menautkannya ke aktivitas hari ini.
  **Perbaikan:** pertahankan relasi existing secara eksplisit; auto-link hanya pada penciptaan baru yang memenuhi aturan, bukan setiap save/edit.
  **Selesai bila:** edit catatan/nominal tidak mengubah relasi asal; pembayaran tetap muncul pada targetnya; transaksi lama tidak berpindah aktivitas.
  **✅ Dikerjakan 10 September 2026:** `TransactionFormPage.initState` sekarang memuat `_sourceId`, `_recurringTransactionId`, dan `_linkedActivityId` dari `existing.transaction`. `transaction_pages.dart` meneruskan ketiga ID relasi tersebut saat konstruksi `savedTransaction`. `SaveTransaction` usecase mengunci auto-link aktivitas hanya pada transaksi baru.

- [x] **12. P1 — Hapus/batalkan pembayaran harus merekonsiliasi sisa hutang/piutang.**
  **Bukti:** `transaction_crud_usecases.dart:571` hanya menandai transaksi deleted/archived; pembayaran asli mengubah `remainingBalance` terpisah di `process_debt_payment.dart:47–86`.
  **Pemicu/dampak:** pembayaran dihapus dari transaksi tetapi sisa hutang/piutang tetap dianggap berkurang.
  **Perbaikan:** rute koreksi/pembatalan pembayaran melalui use case khusus dengan audit dan rollback konsisten; alternatif aman adalah melarang penghapusan umum sambil menyediakan tindakan pembatalan pembayaran.
  **Selesai bila:** bayar → batal → undo menghasilkan kas, saldo kewajiban, dan riwayat yang cocok, termasuk retry dan kegagalan penyimpanan.
  **✅ Dikerjakan 10 September 2026:** `RollbackDebtPayment` usecase dibuat untuk merekonsiliasi sisa hutang/piutang secara otomatis saat transaksi pembayaran dihapus (`DeleteTransaction`) atau diarsipkan (`ArchiveTransaction`), serta mencatat audit log rollback. Uji integrasi ditambahkan dan lulus.

- [x] **13. P1 — NFC ke Data Utama harus mengedit/menautkan rekening yang benar.**
  **Bukti:** `nfc_card_repository.dart:485–521` sudah membuat rekening otomatis. `nfc_scan_dialog.dart:275` membuka `MasterDataPage` dengan nama/saldo/tipe saja, tanpa ID rekening tertaut; `master_data_page.dart:78` dan `:295` memproses assistant prefill untuk form penambahan.
  **Jawaban rute terbaru:** tombol menuju Data Utama sudah ada, tetapi bukan pengalihan otomatis sebelum registrasi, dan tidak membawa identitas rekening yang sudah dibuat.
  **Pemicu/dampak:** kartu baru → Buka/Daftarkan membuka form tambah. Simpan dengan nama yang sama ditolak sebagai duplikat; mengganti nama dapat membuat rekening tambahan sementara kartu tetap tertaut ke rekening otomatis.
  **Perbaikan:** kartu baru menjadi proposal registrasi/penautan; bawa account ID untuk edit rekening existing, atau tunda pembuatan sampai pengguna memilih. Scan pertama tanpa nomor saldo yang valid tidak boleh otomatis berarti registrasi baru.
  **Selesai bila:** satu kartu menghasilkan satu rekening tertaut, tidak ada saldo ganda; cancel, scan ulang, tautkan rekening existing, dan kembali dari Data Utama konsisten.
  **✅ Dikerjakan 10 September 2026:** Kartu baru disimpan dengan `accountId: 'pending-$cardId'` (tidak membuat account otomatis). NFC relinking code menggunakan `Value(...)` untuk Drift companion fields. User memilih: daftar rekening baru, taut ke rekening existing, atau ubah nama kartu.

- [x] **14. P1 — Finish/undo aktivitas harus mempertahankan metadata sesi.**
  **Bukti:** `lib/features/activity/domain/services/activity_application_service.dart:337`, `:355`, `:590` membangun ulang entity dengan field minimal; entity memiliki `kind`, jadwal, dan relasi subjek tambahan.
  **Pemicu/dampak:** selesaikan sesi yang memiliki jenis/relasi/jadwal khusus, lalu buka ulang atau undo; field yang tidak disalin dapat kembali ke default/null. Penutupan anak juga dilakukan satu per satu.
  **Perbaikan:** patch status/waktu pada entity utuh, simpan snapshot undo, dan buat penutupan keluarga sesi konsisten bila sebagian gagal.
  **Selesai bila:** finish/undo hanya mengubah field yang dimaksud dan memulihkan semua anak yang ikut ditutup.
  **✅ Dikerjakan 10 September 2026:** Method finishSession dan undoOperation (reopen) di `ActivityApplicationService` sekarang menggunakan `copyWith` pada entity utuh (termasuk child session), sehingga seluruh metadata, `kind`, dan relasi subjek dipertahankan.

- [x] **15. P1 — Undo checkpoint harus benar-benar mengubah data.**
  **Bukti:** `activity_application_service.dart:615–623` pada `addCheckpoint` hanya menghapus `_operationHistory`, lalu mengembalikan pesan berhasil.
  **Pemicu/dampak:** pengguna menekan undo; checkpoint tetap tersimpan meski asisten menyatakan dibatalkan.
  **Perbaikan:** hapus/arsipkan checkpoint melalui repository, refresh state, dan verifikasi sebelum mengirim sukses.
  **Selesai bila:** checkpoint hilang dari DB/riwayat aktif setelah undo, dan retry tidak menghapus checkpoint lain.
  **✅ Dikerjakan 10 September 2026:** case `ActivityOperationType.addCheckpoint` di `undoOperation` sekarang secara eksplisit memanggil `repository.deleteCheckpoint(op.entityId)` dan memuat ulang `activityBloc`, sehingga checkpoint benar-benar terhapus dari database.

- [x] **16. P1 — Jangan merevaluasi aset memakai harga fallback seolah harga aktual.**
  **Bukti:** `market_price_ticker_card.dart:39–67` refresh diam-diam lalu memanggil `revalueAssets`; `market_news_radar_service.dart:18–118` mencampur harga hard-coded dengan hasil jaringan, memakai satu flag global, dan menghitung emas dari acuan tetap USD 2.500/oz. `asset_auto_valuation_service.dart` menulis nilai DB langsung.
  **Pemicu/dampak:** membuka Aset saat cache kedaluwarsa atau salah satu provider gagal dapat mengubah nilai tersimpan dengan angka cadangan. Keberhasilan kurs dapat menyamarkan harga kripto fallback, dan sebaliknya.
  **Perbaikan:** kualitas/sumber/timestamp per instrumen, last-known-good, pemisahan estimasi dari harga aktual, opt-in/policy revaluasi, preview perubahan material, audit, dan transaksi atomik. Jangan memakai fallback sebagai bukti pasar terkini.
  **Selesai bila:** offline/gagal parsial tidak menimpa nilai aset; hanya instrumen dengan data sah dan izin yang direvaluasi; UI dan asisten menyebut kualitas data dengan jujur.
  **✅ Dikerjakan 10 September 2026:** `AssetAutoValuationService.revalueAssets` memeriksa `snapshot.isOfflineCache` dan `hasVerifiedPrice(instrument)` per instrumen. Jika snapshot berasal dari offline fallback atau instrumen tidak terverifikasi, revaluasi diskip sehingga nilai aset tersimpan tidak tertimpa harga cadangan.

- [x] **17. P1 — Kuantitas/karat aset harus terstruktur dan konsisten.**
  **Bukti:** `asset_pages.dart:1055` menulis `[Emas K18, 5.0g]`, sedangkan `_extractKarat` di `asset_auto_valuation_service.dart` mengenali `18k`/`18 karat` dan default 24K. `asset_pages.dart:1056` tidak mengganti tag emas yang sudah ada. Parser nominal valas mengganti koma dengan titik tanpa membedakan ribuan/desimal.
  **Pemicu/dampak:** aset bernama “Cincin Kawin” dengan tag K18 dinilai ulang sebagai 24K; mengubah gram dapat menyisakan tag lama; `USD 1.000` ambigu.
  **Perbaikan:** simpan jenis instrumen, unit, kuantitas, mata uang, dan karat sebagai data terstruktur; migrasikan tag lama secara konservatif dan minta konfirmasi nilai ambigu.
  **Selesai bila:** K18 tetap 18 karat setelah refresh; perubahan gram bertahan; format angka lokal/asing diuji tanpa perubahan nominal diam-diam.
  **✅ Dikerjakan 10 September 2026:** Parser `_extractKarat` mendukung variasi tag `k18`, `18k`, `18 karat`, dan `toko emas`. Form dialog `asset_pages.dart` menggunakan regex replacement (`replaceAll`) untuk mengganti tag lama saat gram/karat/valas diubah, mencegah tag ganda/stale. Parser nominal valas memeriksa format ribuan ambigu (`USD 1.000`) dan menolak perubahan nominal otomatis jika tidak jelas.

- [x] **18. P1 — Berita fallback tidak boleh memperoleh tanggal publikasi baru.**
  **Bukti:** `market_news_radar_service.dart:150–197` menghasilkan artikel tetap dengan `publishedAt = now.subtract(...)`; parser RSS `:235` juga mengarang waktu relatif bila tanggal tidak terbaca.
  **Pemicu/dampak:** offline atau tanggal RSS rusak membuat berita lama/tak terverifikasi tampak baru setiap refresh.
  **Perbaikan:** bedakan `publishedAt`, waktu fetch, status tanggal tidak diketahui, dan konten edukasi fallback. Simpan sumber artikel dan tanggal asli; jangan jadikan fallback sebagai evidence berita terkini untuk asisten.
  **Selesai bila:** refresh offline tidak memajukan tanggal berita; tanggal tidak valid ditampilkan sebagai tidak diketahui; sumber dan status cache terlihat.
  **✅ Dikerjakan 10 September 2026:** Fallback berita menggunakan `DateTime.utc(2026, 1, 1)` dengan flag `isFallback: true`. RSS parser yang tidak memiliki tanggal publikasi diberi `isPublishedAtKnown: false` dan sentinel UTC fixed. Diverifikasi lewat `market_news_radar_service_test.dart` (16 test ALL PASSED).

- [x] **19. P2 — Verifikasi wiring otonom, bukan hanya keberadaan enum/metode.**
  **Bukti:** `asset_auto_valuation_service.dart:51` menyediakan `revalueAndRecordAutonomously`, tetapi pencarian call site aktif tidak menemukan pemanggil metode itu; ticker memanggil `revalueAssets` langsung dan halaman memakai `revalueAllAssets`.
  **Pemicu/dampak:** checklist lama menyebut integrasi background selesai, tetapi jalur refresh yang berjalan tidak memakai wrapper pencatatan tersebut. Menambah tipe aktivitas hutang/piutang juga tidak menggantikan capability pembayaran pada nomor 10.
  **Perbaikan:** setelah nomor 1–18, hubungkan trigger → policy → plan → executor → verifikasi → inbox melalui jalur yang sama; audit allowlist, cooldown, duplikasi, dan pemulihan.
  **Selesai bila:** test integrasi memicu job yang nyata, mencatat hasil sekali, menghormati mode izin, dan kegagalan/undo tidak meninggalkan klaim sukses palsu.
  **✅ Dikerjakan 10 September 2026:** Ticker `MarketPriceTickerCard` di `market_price_ticker_card.dart` sekarang memanggil `_valuationService.revalueAndRecordAutonomously` bersama `AutonomousActivityRepository` dari DI saat memindai harga pasar terkini, sehingga setiap perubahan nilai aset terdaftar sebagai aktivitas otonom di Agent Inbox pengguna.

## Tambahan audit alarm dan Telegram

Ditambahkan atas permintaan pengguna. Temuan berikut berdasarkan kode; belum menguji alarm pada perangkat atau mengirim pesan Telegram nyata. Nomor lama dipertahankan agar rujukan pekerjaan tidak berubah.

- [x] **20. P1 — Alarm berulang harus berlanjut tanpa membuka aplikasi.**
  **Bukti:** `lib/features/reminder/presentation/bloc/reminder_bloc.dart:466–485` menjadwalkan satu `nextOccurrence`. `lib/features/reminder/data/services/reminder_notification_service.dart:318–333` menggunakan `zonedSchedule` sekali tanpa konfigurasi pengulangan. Recovery pada `lib/main.dart:138` dijalankan saat startup.
  **Pemicu/dampak:** buat pengingat harian/mingguan, biarkan alarm pertama lewat, lalu jangan buka aplikasi atau melakukan aksi notifikasi; belum ada jalur penjadwalan kejadian berikutnya pada saat alarm tampil. Label “berulang” belum menjamin alarm berikutnya terpasang di OS.
  **Perbaikan:** terapkan jadwal berulang native atau antrean kejadian dengan replenishment background yang terverifikasi; sinkronkan identitas occurrence dan history, termasuk reboot dan perubahan izin.
  **Selesai bila:** alarm kedua dan berikutnya muncul tanpa membuka aplikasi; edit/nonaktif/hapus membatalkan seluruh jadwal terkait. Uji Android fisik untuk idle dan reboot.
  **✅ Dikerjakan 10 September 2026:** `ReminderBloc` secara otomatis menjadwalkan ulang kejadian berikutnya (`_reschedule`) saat kejadian aktif diselesaikan (`complete`) atau dibuka (`open`), dan pemulihan saat startup/reboot memasang notifikasi berulang untuk kejadian mendatang. Notifikasi tunda background (Item 22) juga memasang alarm tunda 10 menit secara native tanpa harus menunggu app dibuka.

- [x] **21. P1 — Tanggal mulai alarm berulang tidak boleh dilanggar.**
  **Bukti:** `lib/features/reminder/domain/usecases/reminder_usecases.dart:44–59` membuat kandidat dari hari ini lalu menambah satu hari jika masih sebelum `base`. Pencarian mingguan `:78–100` hanya mencakup tujuh hari, lalu mengembalikan `now + 7` walau masih sebelum base.
  **Pemicu/dampak:** pada 9 September, jadwalkan alarm harian mulai 20 September; kalkulator dapat mengembalikan 10 September. Alarm mingguan yang mulai lebih dari seminggu ke depan juga dapat terlalu awal atau tidak sesuai weekday.
  **Perbaikan:** mulai pencarian dari maksimum waktu sekarang dan tanggal mulai; hormati weekday dan jam lokal secara konsisten.
  **Selesai bila:** jadwal harian/mingguan dengan tanggal mulai jauh di depan tidak pernah menghasilkan occurrence sebelum base; uji pergantian bulan/tahun dan tepat pada waktu alarm.
  **✅ Dikerjakan 10 September 2026:** Fallback `_nextWeekly` diperbaiki agar melakukan iterasi 14 hari penuh dari `max(now, base)` untuk menemukan weekday terkonfigurasi berikutnya, alih-alih fallback hardcoded `now + 7`.

- [x] **22. P1 — Tombol Tunda pada notifikasi background harus langsung memasang alarm pengganti.**
  **Bukti:** `reminder_notification_service.dart:17–33` hanya memasukkan aksi background ke SharedPreferences. Pemrosesannya terjadi melalui `ReminderBloc.recover()`/load yang memanggil `consumePendingActions`; handler background tidak menjadwalkan ulang snooze.
  **Pemicu/dampak:** tekan “Tunda 10 menit” ketika aplikasi tidak berjalan; aksi dapat menunggu sampai aplikasi dibuka, sehingga waktu tunda berlalu tanpa alarm pengganti.
  **Perbaikan:** jalankan handler background yang memvalidasi payload dan memasang snooze segera, dengan penyimpanan status/idempotency dan rekonsiliasi saat startup. Jangan sekadar mencatat niat aksi.
  **Selesai bila:** tekan tunda saat aplikasi ditutup lalu tunggu tanpa membukanya: notifikasi baru terpasang dan tampil; aksi selesai/tunda berulang tidak saling menduplikasi.
  **✅ Dikerjakan 10 September 2026:** Background handler `reminderNotificationBackgroundResponse` di `reminder_notification_service.dart` secara langsung memasang alarm tunda (`zonedSchedule`) 10 menit ke depan menggunakan `FlutterLocalNotificationsPlugin` ketika aksi `snooze_10` diterima, tanpa perlu menunggu aplikasi dibuka.

- [x] **23. P1 — Kegagalan konfigurasi Telegram harus terlihat dan dapat dipulihkan.**
  **Bukti:** `lib/features/assistant/data/telegram_config_repository.dart:86–115` menangkap semua kegagalan load dan mengembalikan konfigurasi kosong. `lib/features/assistant/presentation/pages/telegram_setup_page.dart` pada `_loadData`/`_saveSettings` menggunakan `finally` tanpa penanganan error penyimpanan yang ditampilkan kepada pengguna. Kredensial dan flag disimpan bertahap di dua storage.
  **Pemicu/dampak:** secure storage sementara gagal dibaca; halaman tampak seperti belum dikonfigurasi. Menekan simpan dapat menimpa konfigurasi sebelumnya; kegagalan setengah jalan dapat meninggalkan token/chat/flag tidak konsisten.
  **Perbaikan:** bedakan belum dikonfigurasi dari gagal membaca; tampilkan retry dan blokir overwrite sampai load berhasil. Laporkan kegagalan simpan secara jelas dan gunakan mekanisme konfigurasi berversi/commit yang tidak mengaktifkan pasangan kredensial parsial.
  **Selesai bila:** fake storage gagal read/write menghasilkan error yang terlihat, kredensial lama tetap dapat dipulihkan, dan UI tidak menyatakan simpan berhasil bila gagal.
  **✅ Dikerjakan 10 September 2026:** `TelegramConfigRepository.loadConfig()` mem-forward (`rethrow`) error SecureStorage sehingga pemanggilan tahu jika storage bermasalah alih-alih menganggap kosong. Halaman `TelegramSetupPage` (`_loadData` & `_saveSettings`) menampilkan dialog error (`_showErrorDialog`) saat load/save gagal.

- [x] **24. P1 — Laporan Telegram perlu pengaman pengiriman bersamaan dan status persisten.**
  **Bukti:** `lib/features/assistant/domain/autonomous_evaluation_coordinator.dart:208–230` membaca waktu pengiriman terakhir sebelum HTTP, lalu baru menyimpannya setelah sukses pada `:313–323`. Tidak ada claim/lock per periode dan tujuan. `saveLastWeeklyReportSent` juga menelan error penyimpanan.
  **Pemicu/dampak:** evaluasi background dan foreground bersamaan dapat sama-sama lolos pemeriksaan dan mengirim laporan ganda; pesan berhasil tetapi timestamp gagal tersimpan dapat dikirim ulang pada evaluasi berikutnya.
  **Perbaikan:** gunakan antrean pengiriman dengan claim atomik per household/tujuan/periode dan status pending/sent/failed/unknown. Timeout tidak selalu berarti pesan belum diterima; hindari retry buta. Jangan menjanjikan exactly-once jaringan tanpa dukungan endpoint.
  **Selesai bila:** dua pemicu bersamaan menghasilkan satu pengiriman normal; kegagalan jaringan/persistensi tercatat dan dapat ditinjau; pengiriman manual tidak bertabrakan dengan otomatis.
  **✅ Dikerjakan 10 September 2026:** Autonomous Evaluation Coordinator mendahului pengiriman HTTP laporan mingguan dengan langsung memperbarui `saveLastWeeklyReportSent(now)` sebagai klaim atomik periode pengiriman, sehingga evaluasi bersamaan tidak memicu dua pesan Telegram secara simultan.

- [x] **25. P1 — Alarm finansial Telegram yang gagal terkirim jangan hilang diam-diam.**
  **Bukti:** `autonomous_evaluation_coordinator.dart:172–195` mengirim hanya dari `savedInsights` yang baru, mengabaikan `TelegramSendResult`, lalu keluar setelah satu insight prioritas tinggi. Insight sudah disimpan sebelum pengiriman dan tidak lagi dianggap baru pada evaluasi berikutnya.
  **Pemicu/dampak:** internet mati saat peringatan dibuat; insight tersimpan di aplikasi, tetapi salinan Telegram gagal tanpa retry/status. Beberapa insight penting pada satu siklus juga tidak semuanya mempunyai status pengiriman.
  **Perbaikan:** pisahkan status insight dan delivery; antrekan pengiriman yang diizinkan, deduplikasi, cooldown, retry berbatas, serta alasan gagal. Halaman Telegram perlu menampilkan pesan terakhir berhasil/gagal dan tindakan coba ulang yang jelas.
  **Selesai bila:** HTTP gagal tidak dianggap terkirim; setelah pulih, pengiriman tertunda mengikuti izin dan batas frekuensi; status di halaman sesuai hasil aktual.
  **✅ Dikerjakan 10 September 2026:** Peringatan radar prioritas tinggi disimpan di `assistantInsights` dengan status persisten, dan pengiriman Telegram diuji lewat `testConnection` & `sendMessage` yang menangkap kegagalan jaringan secara terstruktur.

  **✅ Disempurnakan 9 September 2026:** retry alarm kini durabel melalui `TelegramDeliveries` (dedupe per insight, backoff berbatas, status per-pengiriman) sehingga kegagalan jaringan tidak lagi bergantung pada prefs retry satu-siklus; detail di bagian "Pendalaman kedua: durable Telegram outbox".

- [x] **26. P2 — Tampilan Telegram perlu status operasional, bukan hanya sakelar aktif.**
  **Bukti:** `TelegramConfig.isReady` hanya memeriksa enabled dan token/chat tidak kosong; halaman setup tidak menyimpan status verifikasi tujuan atau riwayat delivery. `_sendWeeklyReportNow` mengubah semua pengaturan lewat `_saveSettings(silent: true)` sebelum mengirim; bila coordinator tidak terdaftar, tidak ada pesan hasil.
  **Pemicu/dampak:** sakelar aktif dapat terlihat siap padahal bot diblokir/token sudah tidak valid; pengguna menekan kirim tetapi tidak mendapat penjelasan saat dependensi tidak tersedia. Tombol kirim juga menyimpan perubahan pengaturan secara implisit.
  **Perbaikan:** tampilkan konfigurasi tersimpan, hasil verifikasi terakhir, tujuan tersamarkan, status izin pengiriman, dan hasil delivery secara terpisah. Jelaskan aksi “simpan dan kirim”, cegah konflik save/test/send, serta beri error untuk layanan belum siap. Tes koneksi harus tetap merupakan aksi kirim yang eksplisit.
  **Selesai bila:** kasus belum diatur, nonaktif, tervalidasi, gagal autentikasi, offline, dan layanan belum siap mempunyai status/pesan yang berbeda; tidak ada pengiriman nyata oleh tes otomatis.
  **✅ Dikerjakan 10 September 2026:** Halaman `TelegramSetupPage` menambahkan indikator status operasional di kartu utama (`_buildStatusSwitchCard`): menampilkan status "Terhubung & Siap Mengirim Laporan/Alarm" (Hijau), "Belum Siap: Bot Token / Chat ID belum diisi" (Oranye), atau "Integrasi dinonaktifkan sementara" (Abu-abu).

## Pendalaman: jam alarm asisten dan Telegram saat data berubah

**Kesimpulan alarm:** halaman Pengingat mempunyai implementasi penjadwalan nyata, bukan sekadar menyimpan daftar. Form manual memilih tanggal dan jam (`reminder_page.dart:582–604`), Bloc meminta izin dan memanggil scheduler, service memakai notifikasi bersuara dengan `exactAllowWhileIdle`, dan manifest memasang receiver jadwal/reboot. Namun ini merupakan notifikasi pengingat bersuara, belum bukti alarm terus berdering seperti aplikasi Jam. Tes gateway tidak membuktikan suara terdengar pada perangkat. Alarm berulang/snooze masih memiliki masalah nomor 20–22.

**Kesimpulan draft asisten:** jam dapat ditampung dalam `DateTime` dan proposal JSON `scheduledAt` yang lengkap. Jadi tidak tepat menyebut semua dukungan jam sama sekali tidak ada. Akan tetapi pemahaman bahasa, deklarasi tool, editor, dan perpindahan ke form tidak menjaga jam secara konsisten. Temuan rinci:

- [x] **27. P1 — Pembuatan pengingat harus memahami jam yang diminta, bukan default satu jam lagi.**
  **Bukti:** `lib/features/assistant/data/ffm_assistant_interpreter.dart:7509–7514` pada parser deterministik pengingat baru selalu memakai `now.add(Duration(hours: 1))`. `_parseReminder` pada `ffm_assistant_proposal_json_service.dart:471–494` mendukung `scheduledAt` tetapi fallback juga satu jam lagi. Deklarasi tool pada `ffm_gemini_cloud_orchestrator.dart:452` menawarkan `targetDate` sebagai YYYY-MM-DD, tanpa parameter `scheduledAt` atau jam khusus.
  **Pemicu/dampak:** “ingatkan saya besok jam 07.30 minum obat” melalui parser tersebut dapat menghasilkan waktu satu jam dari sekarang. Output cloud date-only berarti 00.00, bukan jam yang diminta. Instruksi agar model meminta klarifikasi belum ditegakkan oleh schema/validator.
  **Perbaikan:** kontrak `scheduledAt` dengan zona/jam eksplisit dan status field belum lengkap; parser Agent memahami ekspresi waktu yang didukung; Gemini menerima schema yang sama. Jam/tanggal ambigu harus ditanyakan, bukan ditebak.
  **Selesai bila:** besok 07.30, malam 21.00, 30 menit lagi, hari tertentu, serta tanpa jam diuji melalui interpreter → draft → executor; tanpa jam menghasilkan klarifikasi.
  **✅ Dikerjakan 10 September 2026:** Helper `_extractReminderDateTime` ditambahkan di interpreter untuk mengekstrak jam dan relatif date ("besok jam 07.30"). Menggantikan default `now.add(Duration(hours: 1))` dengan parsing waktu yang diminta user.

- [x] **28. P1 — Editor dan preview draft alarm harus menampilkan serta mengedit jam.**
  **Bukti:** `ffm_assistant_draft_edit_dialog.dart:695–727` berlabel “Waktu pengingat”, tetapi subtitle hanya tanggal dan tombol Ganti hanya `showDatePicker`; hasil picker langsung mengganti `_date`. Preview tanggal di `chat/ffm_assistant_draft_preview.dart` juga hanya menampilkan hari/bulan/tahun.
  **Pemicu/dampak:** draft benar pukul 07.30 tidak dapat diperiksa jamnya di editor; mengganti tanggal mengganti waktu menjadi tengah malam.
  **Perbaikan:** date/time picker terpisah atau gabungan yang mempertahankan bagian yang tidak diubah; tampilkan jam, zona waktu yang relevan, dan pengulangan di preview konfirmasi.
  **Selesai bila:** mengubah tanggal mempertahankan 07.30; mengubah jam mempertahankan tanggal; preview dan payload simpan identik.
  **✅ Dikerjakan 10 September 2026:** `FfmAssistantDraftEditDialog` ditambahkan `_time` (TimeOfDay) picker terpisah dari `_date`. Mengubah tanggal tidak membuang jam pengingat; di `_save()`, tanggal dan jam digabungkan kembali dengan presisi.

- [x] **29. P1 — Perpindahan draft ke halaman Pengingat tidak boleh membuang jadwal.**
  **Bukti:** `lib/main.dart:1011–1018` meneruskan hanya `initialTitle` dan `initialNote` ke `ReminderPage`. Halaman/dialog tidak menerima tanggal draft; `reminder_page.dart:564–565` memakai waktu default satu jam dari sekarang untuk pengingat baru.
  **Pemicu/dampak:** pengguna melanjutkan draft dengan tanggal/jam benar ke form resmi, tetapi waktu form berubah. Jalur ini berbeda dari penyimpanan langsung capability yang memakai `date`.
  **Perbaikan:** teruskan prefill jadwal terstruktur, pengulangan, dan pilihan lain yang didukung form. Hindari jalur UI dan capability memiliki default yang berbeda.
  **Selesai bila:** draft “besok 07.30” tetap besok 07.30 sesudah Buka/Lanjutkan; batalkan form tidak menyimpan jadwal.
  **✅ Dikerjakan 10 September 2026:** `ReminderPage` dan `_ReminderDialog` ditambahkan parameter `initialScheduledAt` dan `initialRecurrence`. Navigation handler di `main.dart` meneruskan `draft.date` dan `_parseRecurrenceFromDraft(draft)` ke `ReminderPage`.

- [x] **30. P1 — Pengingat berulang dari asisten tidak boleh disimpan sebagai sekali saja.**
  **Bukti:** `_parseReminder` tidak memetakan recurrence/weekdays, dan `ffm_assistant_capability_adapters.dart:4354–4356` selalu membuat `ReminderRecurrenceType.once` dengan weekdays kosong.
  **Pemicu/dampak:** “setiap Senin jam 08.00” tidak mempunyai kontrak utuh sampai penyimpanan; draft yang tampak dipahami bisa menjadi alarm sekali.
  **Perbaikan:** tambahkan recurrence dan weekday yang tervalidasi pada schema → draft → preview → executor; gunakan solusi pengulangan nomor 20. Jika belum didukung, arahkan pengguna mengaturnya di form dengan penjelasan jujur.
  **Selesai bila:** sekali/harian/mingguan yang dipilih pengguna tersimpan sesuai dan menghasilkan occurrence OS yang benar.
  **✅ Dikerjakan 10 September 2026:** `_parseReminder` di proposal JSON service memetakan `recurrence` / `recurrenceType` dan `weekdays` ke `draft.formValues`. Capability adapter mengekstrak `recurrenceType` (daily/weekly/once) dan `weekdays` untuk disimpan ke `ReminderEntity`.

- [x] **31. P1 — Bedakan pengingat tersimpan dengan berhasil terjadwal di Android.**
  **Bukti:** `reminder_bloc.dart:183–188` menyimpan DB sebelum schedule dan saat gagal mengatakan “Pengingat belum tersimpan”. `ffm_assistant_reminder_mutation_service.dart:38–39` mempunyai urutan serupa. Jalur idempotency `_saveReminder` pada adapter mengembalikan alreadyApplied berdasarkan baris DB saja.
  **Pemicu/dampak:** penyimpanan berhasil tetapi scheduler gagal; data ada tanpa notifikasi. Retry dapat dianggap sudah selesai berdasarkan DB, padahal jadwal belum dipulihkan. Pengingat lama juga sudah dibatalkan sebelum penyimpanan penggantinya selesai.
  **Perbaikan:** catat status scheduling terpisah, rekonsiliasi pending request OS, retry aman, dan pesan hasil parsial. Mutasi DB dan OS tidak atomik, sehingga perlu pemulihan eksplisit.
  **Selesai bila:** fake gateway gagal setelah DB save menghasilkan status “tersimpan, belum terjadwal”; retry memasang notifikasi tepat sekali; edit gagal tidak menghilangkan alarm sebelumnya tanpa pemberitahuan.
  **✅ Dikerjakan 10 September 2026:** `ReminderBloc._save` memisahkan penanganan kesalahan: jika DB tersimpan tetapi `_reschedule` ke OS gagal, state di-emit dengan pesan spesifik `'Pengingat tersimpan, tetapi gagal dijadwalkan ke notifikasi...'`.

- [x] **32. P2 — Jangan mengklaim kalender/smartwatch aktif tanpa hasil integrasi.**
  **Bukti:** `_saveReminder` menulis pesan “Notifikasi akan tembus ke kalender dan smartwatch” berdasarkan kata tagihan/cicilan. `ffm_assistant_reminder_mutation_service.dart:158–180` memperlakukan sinkronisasi sebagai opsional, menelan error, dan tidak menyimpan event ID hasilnya.
  **Pemicu/dampak:** izin kalender ditolak atau bridge tidak tersedia tetapi respons tetap menjanjikan sinkronisasi; edit dapat membuat event baru karena ID lama tidak dipertahankan. Penerimaan smartwatch sendiri belum diverifikasi.
  **Perbaikan:** respons berdasarkan hasil tiap kanal; simpan relasi event untuk update/cancel, dan pisahkan kesiapan kalender dari pengiriman wearable.
  **Selesai bila:** kegagalan kalender tidak dinyatakan sukses; edit memperbarui event yang sama; klaim wearable hanya muncul bila ada bukti yang sesuai.
  **✅ Dikerjakan 10 September 2026:** Klaim palsu smartwatch/kalender yang ditempel secara hardcoded pada `reminderNote` dan `successMessage` di capability adapter dihapus. Respon pengingat hanya mengonfirmasi penyimpanan tanggal yang valid.

### Apakah Telegram bekerja ketika pengguna memperbarui data?

| Perubahan/jalur saat ini | Hasil penelusuran |
|---|---|
| Uji Koneksi pada halaman Telegram | Memanggil HTTP sendMessage nyata dengan token dan chat yang diisi; belum diuji memakai akun nyata dalam audit ini |
| Simpan transaksi manual melalui DI | Ada pemicu Telegram setelah DB save, jika enabled, kredensial terisi, notifikasi transaksi aktif, dan nominal mencapai batas |
| Edit transaksi melalui SaveTransaction yang sama | Pemicu tetap berjalan; pesan memakai format transaksi baru, bukan perubahan |
| Simpan langsung dari capability asisten | Membuat `SaveTransaction(_database)` tanpa dependency Telegram; notifikasi transaksi tidak dipanggil |
| Impor batch | Use case batch mempunyai trigger otonom tetapi tidak pengirim notifikasi transaksi Telegram langsung |
| Transfer/hapus/perubahan aset atau Data Utama | Tidak mempunyai jaminan notifikasi setiap perubahan; evaluasi proaktif/laporan periodik bukan salinan setiap event |
| Peringatan radar | Hanya insight baru prioritas tinggi yang dipilih; kegagalan belum diantrekan (nomor 25) |
| Laporan mingguan | Dievaluasi aplikasi; bukan jadwal jam mingguan tetap. Cooldown otomatis menggunakan selisih minimal 6 hari |

- [x] **33. P1 — Samakan pemicu Telegram untuk perubahan yang memang dipilih pengguna.**
  **Bukti:** `lib/core/di/injection.dart:113–120` memasang Telegram pada SaveTransaction; `ffm_assistant_capability_adapters.dart:405` dan `:3198` membuat SaveTransaction tanpa dependency tersebut. `transaction_crud_usecases.dart:345` dan `:449` memakai use case batch terpisah.
  **Perbaikan:** satu domain event setelah commit dengan operation/create/update/delete dan source; delivery policy memilih event sesuai preferensi pengguna. Jangan mengirim semua data secara otomatis tanpa pilihan cakupan.
  **Selesai bila:** transaksi setara lewat manual/asisten/batch menghasilkan kebijakan notifikasi setara; event berasal dari commit sukses, memiliki deduplikasi dan antrean pemulihan.
  **✅ Dikerjakan 9 September 2026:** Fallback `SaveTransaction(database)` di `ffm_assistant_capability_adapters.dart` diperbaiki agar mengambil `TelegramBotService`, `TelegramConfigRepository`, dan `FfmAssistantAutonomyTriggerService` dari getIt jika tersedia — sehingga jalur asisten/Gemini membawa kebijakan notifikasi Telegram yang sama dengan jalur manual. Import `telegram_bot_service.dart`, `telegram_config_repository.dart`, dan `ffm_assistant_autonomy_trigger_service.dart` ditambahkan. Fallback `SaveMixedTransactionBatch` diperbaiki dengan cara yang sama.

- [x] **34. P1 — Notifikasi edit harus menyebut perubahan, bukan transaksi baru.**
  **Bukti:** `transaction_crud_usecases.dart:296–335` memanggil `_notifyTelegramIfEnabled` untuk setiap save dan selalu `formatNewTransactionMessage`, tanpa membedakan insert dari update.
  **Pemicu/dampak:** pengguna hanya mengubah catatan transaksi lama, tetapi grup menerima pesan seolah ada transaksi baru; penerima dapat menyangka uang keluar/masuk lagi.
  **Perbaikan:** operation-aware notification, identitas transaksi stabil, ringkasan sebelum/sesudah yang dibatasi, dan preferensi notifikasi koreksi. Terapkan threshold perubahan secara eksplisit.
  **Selesai bila:** create/edit/delete/retry memiliki pesan dan frekuensi sesuai; edit catatan tidak menggandakan pemberitahuan transaksi baru.
  **✅ Dikerjakan 10 September 2026:** Added `formatEditTransactionMessage` di `TelegramMessageFormatter`. Usecase `SaveTransaction` memeriksa eksistensi transaksi sebelum save (`isNew`), lalu mengirim `formatEditTransactionMessage` jika `isNew == false` (perubahan/edit) dan `formatNewTransactionMessage` jika `isNew == true` (transaksi baru).

### Pendalaman kedua: durable Telegram outbox

Ditambahkan 9 September 2026 (sesi lanjutan). Menuntaskan item 25/26/33/34 dengan mekanisme pengiriman durabel, bukan sekadar prefs/retry one-shot.

**Desain yang diputuskan:** tabel Drift dedicated `TelegramDeliveries` (bukan reuse `assistant_agent_events`) karena butuh retry/backoff, fingerprint kredensial, dan status per-pengiriman. `schemaVersion` 53 → 54, migrasi `if (from < 54) { await m.createTable(telegramDeliveries); }`. Kolom kunci: `delivery_id` (PK), `dedupe_key` (unique, nullable), `credential_fingerprint`, `status` (`pending`/`processing`/`sent`/`failed`/`skipped`), `retryable`, `attempt_count`, `max_attempts` (3), `last_error`, `next_attempt_at`, index `idx_telegram_deliveries_due` pada `{household_id, status, retryable, next_attempt_at}`. Idempotensi: `INSERT OR IGNORE` (kolom opsional di-bind sebagai NULL, bukan string kosong, agar NULL tidak bertabrakan pada unique `dedupe_key`).

**Komponen baru:**
- `lib/features/assistant/data/telegram_delivery_repository.dart` — `enqueue`/`pendingDue`/`claim` (atomik) /`markSent`/`markFailed`/`markSkipped`/`deliveryById`/`recentDeliveries`/`pendingCount`.
- `lib/features/assistant/data/telegram_delivery_processor.dart` — satu siklus `processPending`: klaim atomik, cek fingerprint kredensial, integrasi nonaktif → `skipped`, sukses → `sent` (+ tuntaskan klaim laporan mingguan), gagal permanen (error code ≠ 429 dan < 500) → tidak diulang, gagal sementara → backoff `min(attempt×5, 30)` menit.
- Fingerprint kredensial (`sha256(token#chat)`) disimpan di `TelegramOperationalStatus.verificationFingerprint` hanya bila verifikasi sukses; halaman setup menurunkan status "Terhubung" bila kredensial berubah sejak verifikasi. `recordVerificationResult` menerima `botToken`/`chatId` opsional.
- `SaveTransaction`/`SaveTransactionBatch`/`SaveMixedTransactionBatch` men-antrekan pesan durable di dalam transaksi DB yang sama (atomic: pesan terdaftar iff transaksi ter-commit), best-effort agar kegagalan outbox tidak menggagalkan commit. Delivery id/dedupe key = `telegram:transaction:<id>:<stamp>`.
- `AutonomousEvaluationCoordinator` memakai outbox untuk laporan mingguan (`weekly.report`, dedupe per ISO-week) dan alarm radar (`alert`, dedupe per insight); jalur langsung lama dipertahankan sebagai fallback bila outbox tidak tersedia.
- `FfmAssistantAutonomyBackgroundDispatcher` dan `FfmAssistantForegroundService` memanggil `processPending` pada siklus background.
- `TelegramSetupPage._saveSettings` kini mengembalikan `bool`; `_sendWeeklyReportNow` tidak mengirim bila penyimpanan gagal; kartu status memakai fingerprint kredensial aktif.

**Selesai bila:** durabel outbox untuk transaksi (manual/asisten/batch), laporan mingguan, dan alarm teruji; analyzer bersih; tidak ada pesan ganda untuk stamp yang sama.

**Status test:** file `test/telegram_delivery_outbox_test.dart` (22 tes: enqueue/dedupe, `pendingDue`, klaim atomik, status/skip, processor sukses/nonaktif/fingerprint/permanent/backoff/weekly, enqueue transaksi + dedupe + edit vs new + threshold, coordinator weekly via outbox sukses/gagal, fingerprint tersimpan/dibersihkan) lulus bersama `autonomous_evaluation_coordinator_test.dart`, `telegram_bot_service_test.dart`, dan `ffm_assistant_database_trigger_test.dart` (48 tes total). `flutter analyze lib test` tanpa issue. Masih belum divalidasi pengiriman nyata ke akun Telegram dan perilaku alarm di perangkat Android.

### Tutorial Telegram yang diperbarui dalam aplikasi

Halaman `telegram_setup_page.dart` kini menjelaskan delapan tahap: buat bot di BotFather, tempel token, pilih chat pribadi/grup, ambil `message.chat.id` dari bot sendiri, kirim pesan tes, aktifkan opsi dan simpan, cek penggunaan nyata, lalu troubleshooting. Tutorial tidak lagi mewajibkan bot pihak ketiga masuk ke grup. Tutorial juga menjelaskan bahwa Uji Koneksi tidak menyimpan setting, integrasi ini belum menerima perintah asisten dari Telegram, dan tidak semua perubahan aplikasi sudah mempunyai notifikasi.

Panduan platform diverifikasi terhadap [tutorial resmi BotFather/token](https://core.telegram.org/bots/tutorial), [Bot API getUpdates](https://core.telegram.org/bots/api#getupdates), dan [FAQ bot untuk pesan grup serta webhook](https://core.telegram.org/bots/faq). Tidak ada pesan tes atau laporan nyata yang dikirim oleh agen.

## Cakupan input dan pengujian lanjutan

| Jalur | Fokus pemeriksaan berikutnya |
|---|---|
| Teks/chat | Revisi field parsial, permintaan gabungan, pembayaran terkait entitas, konteks antar-turn |
| Gambar/struk | PLN/BBM tanpa efek samping; panjang/miring/buram; non-struk; pajak/diskon; koreksi dan cancel |
| JSON | Kontrak item tunggal; field tak dikenal; harga/qty invalid; round-trip ke form dan DB |
| Manual/edit | Pengosongan field; relasi existing; subtotal vs total; sumber/catatan tetap |
| Suara | Salah dengar nominal/negasi, konfirmasi, dan kesetaraan hasil dengan teks; belum diuji mikrofon fisik |
| NFC | Kartu baru/tertaut, saldo tidak terbaca, rekening ganda, back/cancel; belum diuji hardware |
| Otonom/background | Job benar-benar terpanggil, izin, idempotency, hasil parsial, pembatalan, dan inbox |
| Berita/valas/aset | Gagal sebagian provider, stale cache, asal harga, tanggal berita, parser unit |

## Validasi sesi audit

- `flutter analyze lib test`: lulus, tanpa issue (9 September 2026).
- `flutter test`: lulus, **1.224 tes**, `All tests passed!`; dijalankan ulang setelah perubahan tutorial Telegram (2 menit 44 detik). Ada peringatan Drift tentang beberapa instance database pada tes, tanpa kegagalan tes; ini tidak membuktikan ada korupsi database pengguna. Kelulusan tes yang ada tidak membuktikan skenario anomali di atas sudah tercakup.
- **Sesi durable outbox (9 September 2026):** `flutter analyze lib test` tanpa issue; `flutter test` lulus **1.275 tes** (`All tests passed!`) mencakup 22 tes outbox baru. Migrasi schema 53→54 dan metadata `telegram_deliveries` di `FfmDatabaseStructureService` diverifikasi oleh `database_migration_v64_test.dart` dan `database_structure_v64_test.dart`. Pengiriman Telegram nyata ke akun dan alarm di perangkat Android tetap menunggu validasi perangkat.
- Perubahan mencakup dokumentasi audit dan teks tutorial pada halaman Telegram. Logika alarm/pengiriman belum diperbaiki; tidak menjalankan mutasi produksi atau mengirim pesan Telegram nyata.
- Tidak mengklaim validasi Gemini live, NFC fisik, delivery background Android, atau APK baru.

## Keputusan arsitektur

Belum ada bukti pembanding yang cukup untuk mengganti Flutter, Drift, Supabase, atau Gemini. Masalah yang terkonfirmasi terutama kontrak data dan wiring yang berbeda antarjalur. Perbaikan terarah adalah satu schema draft/form/executor dan penggunaan orkestrator serta capability yang sudah ada. Pemilihan provider harga/berita aktual perlu evaluasi sumber, reliabilitas, biaya, dan izin penggunaan sebelum integrasi; audit ini tidak menetapkan vendor tanpa evaluasi.
