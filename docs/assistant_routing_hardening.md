# Assistant routing hardening

## Goals

- Treat `beli`, `bayar`, `jual`, `makan`, and similar words as transaction vocabulary, not mutation permission by themselves.
- Require explicit mutation language before Gemini is instructed to emit a mutation or teaching proposal.
- Keep Agent validation, preview, confirmation, and persistence as the only mutation path.
- Make evidence precedence explicit: SQL/application and page snapshots are authoritative; approved memory/personalization are contextual; cloud memory and conversation history are non-authoritative.

## Regression examples

Denied mutation proposal gate:

- `Saya mau beli rumah tahun depan, menurut kamu masuk akal?`
- `Saya sudah bayar listrik kemarin.`
- `Kalau jual motor bagaimana?`

Allowed mutation proposal gate:

- `Catat beli makan 25000 sebagai pengeluaran.`
- `Buat transaksi bayar listrik 250000.`

The gate is an additional safety layer. It does not replace deterministic parsing or Agent-side validation.
