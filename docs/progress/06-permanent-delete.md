# 6. Permanent Delete untuk Master Data

## Status: SELESAI ✓

## Deskripsi
Semua jenis data utama bisa dihapus permanen dari database.

## Yang Dilakukan
- Pattern hapus: `hapus`, `buang`, `hilangkan`
- Draft kinds: `merchantDelete`, `tagDelete`, `incomeSourceDelete`, `categoryDelete`, `accountDelete`
- Intent types: `deleteMerchant`, `deleteTag`, `deleteIncomeSource`, `deleteCategory`, `deleteAccount`
- Capabilities: `draft.merchant_delete`, `draft.tag_delete`, `draft.income_source_delete`, `draft.category_delete`, `draft.account_delete`

## Lokasi Kode
- `lib/features/assistant/data/ffm_assistant_interpreter.dart` — pattern matching
- `lib/features/assistant/domain/ffm_assistant_models.dart` — enum definitions
- `lib/features/assistant/domain/ffm_assistant_capabilities.dart` — capability definitions
- `lib/features/assistant/domain/ffm_assistant_action_planner.dart` — routing ke `sensitive.delete`
- `lib/features/assistant/data/ffm_assistant_capability_adapters.dart` — delete handlers

## Contoh Perintah
```
"Hapus kategori Transportasi"
"Buang rekening BCA"
"Hilangkan tag investasi"
```
