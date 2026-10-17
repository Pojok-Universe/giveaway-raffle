# Setup Supabase Storage (bukti foto)

## 1. Bikin project Supabase (gratis)
1. Buka https://supabase.com → **New Project**
2. Isi nama project, password database (bebas), region **Singapore**
3. Tunggu ~2 menit sampai project ready

## 2. Bikin bucket `proofs`
1. Sidebar → **Storage** → **New bucket**
2. Name: `proofs`
3. **Public bucket: ON** (centang!) — biar foto bisa dilihat admin
4. Create

## 3. Ambil API keys
1. Sidebar → **Project Settings** (ikon gear) → **API**
2. Copy:
   - **Project URL** → ini `SUPABASE_URL`
   - **service_role** key (klik Reveal) → ini `SUPABASE_SERVICE_KEY`
   > ⚠️ Pakai service_role, BUKAN anon key. Jangan share ke siapa pun.

## 4. Tambah ke Vercel
1. Vercel → project `giveaway-raffle` → **Settings** → **Environment Variables**
2. Add:
   - Key: `SUPABASE_URL`, Value: Project URL, Env: Production
   - Key: `SUPABASE_SERVICE_KEY`, Value: service_role key, Env: Production
3. **Redeploy** (Deployments → ⋯ → Redeploy)

## 5. Cara pakai di campaign
Format task per baris: `Label | link-opsional | photo`

Contoh:
```
Screenshot bukti follow @agunverse | | photo
Screenshot bukti follow @EntitiesOnRH | | photo
Reply & like postingan ini (wajib kode) | https://x.com/...
```

- Task `photo` → peserta upload gambar (jpg/png/webp, maks 2MB)
- Bukti foto otomatis ditandai 📷 "perlu review manual" di dashboard admin
- Klik thumbnail buat lihat full, terus Approve/Reject manual
