# Deploy Giveaway Raffle ke Vercel

## 1. Push ke GitHub
```powershell
cd C:\Codingan\giveaway-raffle-code   # sesuaikan folder
git init
git add .
git commit -m "Giveaway raffle v2 - Vercel KV + anti-spam"
git branch -M main
git remote add origin https://github.com/USERNAME/giveaway-raffle.git
git push -u origin main
```

## 2. Import ke Vercel
1. Buka https://vercel.com → Add New → Project
2. Import repo `giveaway-raffle`
3. Framework otomatis terdeteksi: Next.js → Deploy

## 3. Buat Upstash Redis (database)
> Catatan: Vercel KV sudah deprecated — proyek baru wajib pakai Upstash Redis.
1. Buka https://vercel.com/marketplace → cari **Upstash Redis** → **Add Integration**
2. Pilih project ini → Connect
3. Env var otomatis terisi di project:
   - `UPSTASH_REDIS_REST_URL`
   - `UPSTASH_REDIS_REST_TOKEN`
   (Gratis: 10rb request/hari — cukup banget buat giveaway)

## 4. Env var wajib: ADMIN_PASSWORD
1. Project → **Settings** → **Environment Variables**
2. Tambah: `ADMIN_PASSWORD` = password admin rahasia (bebas, mis. `raffle-admin-2026`)
3. **Redeploy** (Deployments → ⋯ → Redeploy) supaya env var kepakai

## 5. Bikin campaign Cloaked Entities
1. Buka `https://PROJECT.vercel.app/admin` → login pakai ADMIN_PASSWORD
2. Buat giveaway baru:
   - Judul: `Cloaked Entities FCFS Spot Giveaway`
   - Hadiah: `1 FCFS Spot — Cloaked Entities`
   - Deadline: tanggal tutup giveaway
   - Task: `Follow @agunverse | https://x.com/agunverse` (1 baris per task)
   - **Kode campaign**: mis. `CLOAKEDXAGUN` → peserta wajib cantumkan di tweet bukti
3. Link publik: `https://PROJECT.vercel.app/c/<campaign-id>`

## Fitur anti-spam yang aktif
- 1 wallet / 1 X username per campaign (duplikat ditolak)
- Maks 5 pendaftaran per IP per 24 jam
- Link bukti dicek otomatis via oEmbed X (tweet harus beneran ada + milik username tsb)
- Kode campaign wajib ada di tweet bukti (anti copas link asal)
- Link bukti yang sama dipakai 2 entry = di-flag di dashboard admin

## Catatan
- Verifikasi follow & deteksi bot otomatis TIDAK bisa tanpa X API berbayar ($200/bln).
  Alur: filter kasar via dashboard admin → cek manual finalis (follow @agunverse + @EntitiesOnRH).
- Data tersimpan di Upstash Redis (persist antar deploy). Mode lokal (`npm run dev`
  tanpa env Redis) tetap pakai `data/db.json` seperti dulu.
