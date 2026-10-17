#  Giveaway Raffle

Web app giveaway/raffle untuk proyek NFT. Peserta isi form (X username + wallet + bukti task), admin verifikasi entry, lalu undi pemenang dengan seed acak yang bisa diverifikasi.

##  Cara Jalan (Lokal)

```powershell
cd giveaway-raffle-code
npm install
copy .env.example .env.local
# edit .env.local -> isi ADMIN_PASSWORD dengan password kuat
npm run dev
```

Buka http://localhost:3000

## Bot Anti-Spam Bukti

Setiap entry otomatis dicek saat submit (gratis, tanpa API key):

- Link bukti **wajib diisi** untuk semua task - kosong langsung ditolak
- Link dicek via oEmbed publik X: tweet beneran ada atau ngawur, dan **cocok tidak penulis tweet dengan username peserta**
- **Bukti duplikat** (link sama dipakai 2 entry) otomatis di-flag
- Di halaman Kelola ada filter **Bermasalah / Bersih** + badge per bukti (centang = valid, silang = bermasalah, ? = belum bisa dicek otomatis)
- Keputusan akhir tetap di tangan admin (tombol approve/reject) - bot hanya menandai, tidak auto-ban

##  Alur Pakai

##  Alur Pakai

1. **Login admin** -> klik tombol "Admin" (pojok kanan atas) -> masukkan password dari `.env.local`
2. **Buat giveaway** -> isi judul, hadiah, deadline, dan task (format per baris: `Label | link-opsional`)
3. **Share link publik** -> `http://localhost:3000/c/<id-campaign>` ke komunitas
4. **Verifikasi entry** -> di halaman Kelola, klik [OK] (approve) atau [X] (reject) per entry
5. **Undi** -> masukkan jumlah pemenang -> "Jalankan Undian" -> hasil + seed tampil di `/c/<id>/hasil`

##  Keamanan

- Login admin pakai password env + cookie httpOnly (signature HMAC).
- Entry duplikat (wallet / X username sama) otomatis ditolak.
- Format wallet divalidasi (`0x` + 40 hex).
- Jangan commit `.env.local` ke git!

##  Deploy ke Vercel

```powershell
vercel
```

Lalu set Environment Variable `ADMIN_PASSWORD` di dashboard Vercel.

> [!] **Catatan:** penyimpanan pakai file JSON (`data/db.json`). Di Vercel filesystem-nya ephemeral - data bisa hilang saat redeploy. Untuk produksi serius, ganti `lib/db.js` dengan database beneran (mis. Vercel Postgres / Supabase).

##  Struktur

```
app/
  page.js                  -> daftar giveaway aktif
  c/[id]/page.js           -> form ikut giveaway
  c/[id]/hasil/page.js     -> pengumuman pemenang
  admin/page.js            -> login admin
  admin/dashboard/page.js  -> buat & daftar campaign
  admin/c/[id]/page.js     -> verifikasi entry + undian
  api/...                  -> REST API
lib/
  db.js      -> penyimpanan JSON
  auth.js    -> session admin
  raffle.js  -> undian seeded (mulberry32, reproducible dari seed)
```

##  Verifikasi Undian

Setiap undian menyimpan `seed` (hex acak). Dengan seed + daftar entry approved, urutan kocokan bisa direproduksi ulang memakai algoritma di `lib/raffle.js` - transparan untuk peserta.
