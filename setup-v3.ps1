# VERSI BARU v3 - Write-File 100% .NET, tanpa cmdlet path PowerShell
# ======================================================
# Setup Giveaway Raffle — JALANKAN SEKALI di folder kosong
# Cara: .\setup-v3.ps1
# ======================================================
$ErrorActionPreference = "Stop"

function Write-File($p, $content) {
    $base = (Get-Location).Path
    $dir = [IO.Path]::GetDirectoryName($p)
    if ($dir) {
        $fullDir = [IO.Path]::Combine($base, $dir)
        if (-not [IO.Directory]::Exists($fullDir)) {
            [void][IO.Directory]::CreateDirectory($fullDir)
        }
    }
    $full = [IO.Path]::Combine($base, $p)
    [IO.File]::WriteAllText($full, $content, [Text.UTF8Encoding]::new($false))
    Write-Host "OK: $p"
}

Write-File "package.json" @'
{"dependencies":{"next":"14.2.5","react":"18.3.1","react-dom":"18.3.1"},"name":"giveaway-raffle","private":true,"scripts":{"build":"next build","dev":"next dev","start":"next start"},"version":"1.0.0"}
'@

Write-File "next.config.js" @'
/** @type {import('next').NextConfig} */
const nextConfig = {};

module.exports = nextConfig;
'@

Write-File "jsconfig.json" @'
{"compilerOptions":{"paths":{"@/*":["./*"]}}}
'@

Write-File ".env.example" @'
# Copy file ini menjadi .env.local lalu isi password admin
ADMIN_PASSWORD=ganti-dengan-password-kuat
'@

Write-File ".gitignore" @'
node_modules
.next
.env
.env.local
data/db.json
'@

Write-File "lib/db.js" @'
import fs from "node:fs";
import path from "node:path";

const DB_PATH = path.join(process.cwd(), "data", "db.json");

function ensureDb() {
  const dir = path.dirname(DB_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  if (!fs.existsSync(DB_PATH)) {
    fs.writeFileSync(
      DB_PATH,
      JSON.stringify({ campaigns: [], entries: [], draws: [] }, null, 2)
    );
  }
}

export function readDb() {
  ensureDb();
  return JSON.parse(fs.readFileSync(DB_PATH, "utf8"));
}

export function writeDb(db) {
  ensureDb();
  fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2));
}

export function uid(prefix = "id") {
  return (
    prefix +
    "_" +
    Date.now().toString(36) +
    "_" +
    Math.random().toString(36).slice(2, 8)
  );
}
'@

Write-File "lib/auth.js" @'
import crypto from "node:crypto";
import { cookies } from "next/headers";

export const ADMIN_COOKIE = "gr_admin";

function signature() {
  const secret = process.env.ADMIN_PASSWORD || "";
  return crypto
    .createHmac("sha256", secret)
    .update("giveaway-raffle-admin")
    .digest("hex");
}

export function adminCookieValue() {
  return signature();
}

// Dipakai di API route & server component
export async function isAdmin() {
  if (!process.env.ADMIN_PASSWORD) return false;
  const c = cookies().get(ADMIN_COOKIE)?.value;
  if (!c) return false;
  const expected = signature();
  if (c.length !== expected.length) return false;
  return crypto.timingSafeEqual(Buffer.from(c), Buffer.from(expected));
}
'@

Write-File "lib/raffle.js" @'
import crypto from "node:crypto";

// PRNG mulberry32 — deterministik dari seed integer
function mulberry32(seedInt) {
  let a = seedInt >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Kocok pool entry lalu ambil N pemenang. Hasil bisa direproduksi dari seed.
export function drawWinners(entryIds, count, seedHex) {
  const seedInt = parseInt(
    crypto.createHash("sha256").update(seedHex).digest("hex").slice(0, 8),
    16
  );
  const rand = mulberry32(seedInt);
  const pool = [...entryIds];
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, Math.min(count, pool.length));
}

export function newSeed() {
  return crypto.randomBytes(16).toString("hex");
}
'@

Write-File "middleware.js" @'
import { NextResponse } from "next/server";

// Nama cookie disamakan dengan lib/auth.js (ADMIN_COOKIE).
// Sengaja tidak import dari sana karena middleware (edge runtime)
// tidak boleh menarik next/headers.
const ADMIN_COOKIE = "gr_admin";

// Proteksi halaman admin — cek keberadaan cookie.
// Verifikasi signature dilakukan di API route & server component.
export function middleware(request) {
  const { pathname } = request.nextUrl;
  if (pathname.startsWith("/admin") && pathname !== "/admin") {
    const c = request.cookies.get(ADMIN_COOKIE)?.value;
    if (!c) {
      return NextResponse.redirect(new URL("/admin", request.url));
    }
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*"],
};
'@

Write-File "app/globals.css" @'
:root {
  --bg: #0b0e17;
  --bg2: #111627;
  --card: #151c31;
  --border: #263052;
  --text: #e8ecf7;
  --muted: #9aa4c0;
  --accent: #7c5cff;
  --accent2: #22d3a5;
  --danger: #ff5d6c;
  --warn: #ffb020;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  background: radial-gradient(1200px 600px at 50% -10%, #1b2340 0%, var(--bg) 60%);
  color: var(--text);
  font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
  min-height: 100vh;
}

a { color: var(--accent2); text-decoration: none; }
a:hover { text-decoration: underline; }

.container { max-width: 880px; margin: 0 auto; padding: 24px 16px 64px; }

.nav {
  display: flex; justify-content: space-between; align-items: center;
  padding: 16px 0; margin-bottom: 12px;
}
.nav .logo { font-size: 22px; font-weight: 800; color: var(--text); }
.nav .logo span { color: var(--accent2); }

.hero { text-align: center; padding: 40px 0 24px; }
.hero h1 { font-size: 34px; margin-bottom: 10px; }
.hero p { color: var(--muted); font-size: 16px; }

.card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 20px;
  margin: 16px 0;
}
.card h2 { margin-bottom: 6px; font-size: 20px; }
.card .meta { color: var(--muted); font-size: 13px; margin: 8px 0; }

.grid { display: grid; gap: 16px; }
@media (min-width: 640px) { .grid { grid-template-columns: 1fr 1fr; } }

.btn {
  display: inline-block; padding: 10px 18px; border-radius: 10px;
  border: 1px solid var(--border); background: var(--bg2); color: var(--text);
  font-size: 14px; font-weight: 600; cursor: pointer; transition: 0.15s;
}
.btn:hover { border-color: var(--accent); text-decoration: none; }
.btn-primary { background: var(--accent); border-color: var(--accent); color: #fff; }
.btn-primary:hover { filter: brightness(1.15); }
.btn-success { background: var(--accent2); border-color: var(--accent2); color: #06281e; }
.btn-danger { background: transparent; border-color: var(--danger); color: var(--danger); }
.btn-danger:hover { background: var(--danger); color: #fff; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }
.btn-row { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 14px; }

.input, .textarea, .select {
  width: 100%; padding: 10px 12px; border-radius: 10px;
  border: 1px solid var(--border); background: var(--bg2);
  color: var(--text); font-size: 14px; margin: 6px 0;
}
.textarea { min-height: 90px; resize: vertical; }
.input:focus, .textarea:focus, .select:focus {
  outline: none; border-color: var(--accent);
}
label.lbl { display: block; font-size: 13px; color: var(--muted); margin-top: 12px; }

.table-wrap { overflow-x: auto; }
table.tbl { width: 100%; border-collapse: collapse; font-size: 14px; }
table.tbl th, table.tbl td {
  text-align: left; padding: 10px 8px; border-bottom: 1px solid var(--border);
}
table.tbl th { color: var(--muted); font-size: 12px; text-transform: uppercase; }

.badge {
  display: inline-block; padding: 3px 10px; border-radius: 999px;
  font-size: 12px; font-weight: 700;
}
.badge.pending { background: #3a2f10; color: var(--warn); }
.badge.approved { background: #0d3327; color: var(--accent2); }
.badge.rejected { background: #3a1418; color: var(--danger); }
.badge.open { background: #0d3327; color: var(--accent2); }
.badge.closed { background: #2a2f45; color: var(--muted); }

.req-item {
  display: flex; gap: 10px; align-items: flex-start;
  padding: 12px; border: 1px solid var(--border); border-radius: 10px;
  margin: 8px 0; background: var(--bg2);
}
.req-item input[type="checkbox"] { width: 20px; height: 20px; margin-top: 2px; accent-color: var(--accent2); }
.req-item .req-body { flex: 1; }
.req-item .req-body b { display: block; margin-bottom: 4px; }
.req-item .req-body .hint { font-size: 12px; color: var(--muted); }

.winner {
  display: flex; align-items: center; gap: 12px;
  padding: 12px; border: 1px solid var(--accent2); border-radius: 10px;
  margin: 8px 0; background: #0d2b23;
}
.winner .rank {
  font-size: 22px; font-weight: 800; color: var(--accent2); min-width: 36px;
}

.alert { padding: 12px 16px; border-radius: 10px; margin: 12px 0; font-size: 14px; }
.alert-error { background: #3a1418; border: 1px solid var(--danger); color: #ffb3ba; }
.alert-ok { background: #0d3327; border: 1px solid var(--accent2); color: #a9f0da; }
.alert-info { background: #1a2340; border: 1px solid var(--accent); color: #c9bcff; }

.seed-box {
  font-family: monospace; font-size: 12px; word-break: break-all;
  background: var(--bg); border: 1px dashed var(--border);
  padding: 10px; border-radius: 8px; margin-top: 8px; color: var(--muted);
}

.footer { text-align: center; color: var(--muted); font-size: 12px; margin-top: 48px; }
.empty { text-align: center; color: var(--muted); padding: 40px 0; }
.small { font-size: 12px; color: var(--muted); }
.row-between { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
.mt { margin-top: 16px; }
'@

Write-File "app/layout.js" @'
import "./globals.css";

export const metadata = {
  title: "Giveaway Raffle",
  description: "Ikuti giveaway & raffle transparan untuk proyek NFT",
};

export default function RootLayout({ children }) {
  return (
    <html lang="id">
      <body>
        <div className="container">
          <nav className="nav">
            <a href="/" className="logo">
              🎰 Giveaway<span>Raffle</span>
            </a>
            <a href="/admin" className="btn">
              Admin
            </a>
          </nav>
          {children}
          <div className="footer">
            Giveaway Raffle — undian transparan dengan seed terverifikasi
          </div>
        </div>
      </body>
    </html>
  );
}
'@

Write-File "app/page.js" @'
import Link from "next/link";
import { readDb } from "@/lib/db";

export const dynamic = "force-dynamic";

function timeLeft(deadline) {
  const ms = new Date(deadline) - Date.now();
  if (ms <= 0) return "Ditutup";
  const d = Math.floor(ms / 86400000);
  const h = Math.floor((ms % 86400000) / 3600000);
  if (d > 0) return `${d} hari ${h} jam lagi`;
  const m = Math.floor((ms % 3600000) / 60000);
  return `${h} jam ${m} mnt lagi`;
}

export default function Home() {
  const db = readDb();
  const campaigns = db.campaigns
    .filter((c) => c.published)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

  return (
    <>
      <div className="hero">
        <h1>🎉 Giveaway Aktif</h1>
        <p>Ikuti giveaway, selesaikan task, menangkan hadiah. Pemenang diundi transparan.</p>
      </div>

      {campaigns.length === 0 && (
        <div className="empty">Belum ada giveaway aktif. Cek lagi nanti! 👀</div>
      )}

      <div className="grid">
        {campaigns.map((c) => {
          const closed = new Date(c.deadline) < new Date();
          const n = db.entries.filter(
            (e) => e.campaignId === c.id && e.status === "approved"
          ).length;
          return (
            <div className="card" key={c.id}>
              <div className="row-between">
                <h2>{c.title}</h2>
                <span className={`badge ${closed ? "closed" : "open"}`}>
                  {closed ? "Ditutup" : "Buka"}
                </span>
              </div>
              <p className="meta">
                🏆 {c.prize} &nbsp;•&nbsp; ✅ {n} peserta lolos &nbsp;•&nbsp; ⏰{" "}
                {timeLeft(c.deadline)}
              </p>
              <p style={{ fontSize: 14, color: "#c4cbe2" }}>
                {c.description?.slice(0, 140)}
                {c.description?.length > 140 ? "…" : ""}
              </p>
              <div className="btn-row">
                <Link href={`/c/${c.id}`} className="btn btn-primary">
                  Ikut Giveaway
                </Link>
                <Link href={`/c/${c.id}/hasil`} className="btn">
                  Lihat Hasil
                </Link>
              </div>
            </div>
          );
        })}
      </div>
    </>
  );
}
'@

Write-File "app/c/[id]/page.js" @'
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";

export default function CampaignPage() {
  const { id } = useParams();
  const [campaign, setCampaign] = useState(null);
  const [loading, setLoading] = useState(true);
  const [xUsername, setXUsername] = useState("");
  const [wallet, setWallet] = useState("");
  const [checks, setChecks] = useState({});
  const [evidence, setEvidence] = useState({});
  const [msg, setMsg] = useState(null);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    fetch(`/api/campaigns/${id}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        setCampaign(d);
        setLoading(false);
      });
  }, [id]);

  async function submit(e) {
    e.preventDefault();
    setMsg(null);

    const reqs = campaign.requirements || [];
    const unchecked = reqs.filter((r) => !checks[r.id]);
    if (unchecked.length > 0) {
      setMsg({ type: "error", text: "Centang semua task yang sudah kamu kerjakan dulu!" });
      return;
    }
    if (!xUsername.trim() || !wallet.trim()) {
      setMsg({ type: "error", text: "Isi X username dan wallet address!" });
      return;
    }

    setSending(true);
    const res = await fetch(`/api/campaigns/${id}/entries`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        xUsername: xUsername.trim().replace(/^@/, ""),
        wallet: wallet.trim(),
        evidence,
      }),
    });
    const data = await res.json();
    setSending(false);
    if (res.ok) {
      setMsg({ type: "ok", text: "Entry terkirim! Tunggu verifikasi admin. Good luck! 🍀" });
      setXUsername("");
      setWallet("");
      setChecks({});
      setEvidence({});
    } else {
      setMsg({ type: "error", text: data.error || "Gagal mengirim entry." });
    }
  }

  if (loading) return <div className="empty">Loading…</div>;
  if (!campaign) return <div className="empty">Giveaway tidak ditemukan 😢</div>;

  const closed = new Date(campaign.deadline) < new Date();

  return (
    <>
      <div className="card">
        <div className="row-between">
          <h2>{campaign.title}</h2>
          <span className={`badge ${closed ? "closed" : "open"}`}>
            {closed ? "Ditutup" : "Buka"}
          </span>
        </div>
        <p className="meta">
          🏆 Hadiah: {campaign.prize} &nbsp;•&nbsp; ⏰ Deadline:{" "}
          {new Date(campaign.deadline).toLocaleString("id-ID")}
        </p>
        <p style={{ fontSize: 14, whiteSpace: "pre-wrap" }}>{campaign.description}</p>
      </div>

      {closed ? (
        <div className="alert alert-info">
          Pendaftaran sudah ditutup.{" "}
          <Link href={`/c/${id}/hasil`}>Lihat hasil undian →</Link>
        </div>
      ) : (
        <div className="card">
          <h2>📝 Form Pendaftaran</h2>
          <form onSubmit={submit}>
            <label className="lbl">Selesaikan task berikut:</label>
            {(campaign.requirements || []).map((r) => (
              <div className="req-item" key={r.id}>
                <input
                  type="checkbox"
                  checked={!!checks[r.id]}
                  onChange={(e) => setChecks({ ...checks, [r.id]: e.target.checked })}
                />
                <div className="req-body">
                  <b>{r.label}</b>
                  {r.url && (
                    <a href={r.url} target="_blank" rel="noreferrer" className="btn" style={{ fontSize: 12, padding: "6px 12px" }}>
                      Buka ↗
                    </a>
                  )}
                  <input
                    className="input"
                    style={{ marginTop: 8 }}
                    placeholder="Link bukti (opsional)"
                    value={evidence[r.id] || ""}
                    onChange={(e) => setEvidence({ ...evidence, [r.id]: e.target.value })}
                  />
                </div>
              </div>
            ))}

            <label className="lbl">X Username (tanpa @)</label>
            <input
              className="input"
              placeholder="cth: agunverse"
              value={xUsername}
              onChange={(e) => setXUsername(e.target.value)}
            />

            <label className="lbl">Wallet Address</label>
            <input
              className="input"
              placeholder="0x…"
              value={wallet}
              onChange={(e) => setWallet(e.target.value)}
            />

            {msg && (
              <div className={`alert alert-${msg.type === "ok" ? "ok" : "error"}`}>
                {msg.text}
              </div>
            )}

            <div className="btn-row">
              <button className="btn btn-success" disabled={sending}>
                {sending ? "Mengirim…" : "Kirim Entry 🚀"}
              </button>
            </div>
            <p className="small mt">
              1 wallet = 1 entry. Entry duplikat otomatis ditolak.
            </p>
          </form>
        </div>
      )}
    </>
  );
}
'@

Write-File "app/c/[id]/hasil/page.js" @'
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";

export default function ResultPage() {
  const { id } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch(`/api/campaigns/${id}/draw`)
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        setData(d);
        setLoading(false);
      });
  }, [id]);

  if (loading) return <div className="empty">Loading…</div>;
  if (!data) return <div className="empty">Giveaway tidak ditemukan 😢</div>;

  const { campaign, draw, winners } = data;

  return (
    <>
      <div className="card">
        <h2>🏆 Hasil Undian — {campaign.title}</h2>
        <p className="meta">Hadiah: {campaign.prize}</p>
      </div>

      {!draw ? (
        <div className="alert alert-info">
          Undian belum dilakukan. Pemenang akan diumumkan di sini setelah draw oleh admin.
        </div>
      ) : (
        <div className="card">
          <h2>🎉 Pemenang ({winners.length})</h2>
          {winners.map((w, i) => (
            <div className="winner" key={w.id}>
              <div className="rank">#{i + 1}</div>
              <div>
                <b>@{w.xUsername}</b>
                <div className="small" style={{ fontFamily: "monospace" }}>
                  {w.wallet}
                </div>
              </div>
            </div>
          ))}
          <p className="small mt">
            Diundi pada: {new Date(draw.createdAt).toLocaleString("id-ID")}
            {draw.redraw ? " (redraw)" : ""}
          </p>
          <label className="lbl">Seed undian (bisa diverifikasi ulang):</label>
          <div className="seed-box">{draw.seed}</div>
          <div className="btn-row">
            <Link href={`/c/${id}`} className="btn">
              ← Kembali ke Giveaway
            </Link>
          </div>
        </div>
      )}
    </>
  );
}
'@

Write-File "app/admin/page.js" @'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function AdminLogin() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [sending, setSending] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setError("");
    setSending(true);
    const res = await fetch("/api/admin/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });
    setSending(false);
    if (res.ok) {
      router.push("/admin/dashboard");
    } else {
      setError("Password salah!");
    }
  }

  return (
    <div className="card" style={{ maxWidth: 420, margin: "40px auto" }}>
      <h2>🔐 Admin Login</h2>
      <form onSubmit={submit}>
        <label className="lbl">Password Admin</label>
        <input
          type="password"
          className="input"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Masukkan password admin"
        />
        {error && <div className="alert alert-error">{error}</div>}
        <div className="btn-row">
          <button className="btn btn-primary" disabled={sending}>
            {sending ? "Masuk…" : "Masuk"}
          </button>
        </div>
      </form>
    </div>
  );
}
'@

Write-File "app/admin/dashboard/page.js" @'
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function Dashboard() {
  const router = useRouter();
  const [campaigns, setCampaigns] = useState([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState({
    title: "",
    description: "",
    prize: "",
    deadline: "",
    requirements: "",
  });
  const [msg, setMsg] = useState(null);

  function load() {
    fetch("/api/campaigns?all=1")
      .then((r) => {
        if (r.status === 401) {
          router.push("/admin");
          return null;
        }
        return r.json();
      })
      .then((d) => {
        if (d) {
          setCampaigns(d);
          setLoading(false);
        }
      });
  }

  useEffect(load, []);

  async function create(e) {
    e.preventDefault();
    setMsg(null);
    const requirements = form.requirements
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean)
      .map((line, i) => {
        const [label, url] = line.split("|").map((s) => s.trim());
        return { id: `req_${Date.now()}_${i}`, label, url: url || "" };
      });

    const res = await fetch("/api/campaigns", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        title: form.title,
        description: form.description,
        prize: form.prize,
        deadline: new Date(form.deadline).toISOString(),
        requirements,
      }),
    });
    if (res.ok) {
      setMsg({ type: "ok", text: "Campaign dibuat! 🎉" });
      setForm({ title: "", description: "", prize: "", deadline: "", requirements: "" });
      load();
    } else {
      const d = await res.json();
      setMsg({ type: "error", text: d.error || "Gagal membuat campaign." });
    }
  }

  async function remove(id) {
    if (!confirm("Hapus campaign ini beserta semua entry-nya?")) return;
    const res = await fetch(`/api/campaigns/${id}`, { method: "DELETE" });
    if (res.ok) load();
  }

  async function logout() {
    await fetch("/api/admin/logout", { method: "POST" });
    router.push("/admin");
  }

  if (loading) return <div className="empty">Loading…</div>;

  return (
    <>
      <div className="row-between">
        <h2>📊 Dashboard Admin</h2>
        <button className="btn" onClick={logout}>
          Logout
        </button>
      </div>

      <div className="card">
        <h2>➕ Buat Giveaway Baru</h2>
        <form onSubmit={create}>
          <label className="lbl">Judul</label>
          <input className="input" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="cth: WL Spot Giveaway #1" required />
          <label className="lbl">Deskripsi</label>
          <textarea className="textarea" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="Syarat & info giveaway…" />
          <label className="lbl">Hadiah</label>
          <input className="input" value={form.prize} onChange={(e) => setForm({ ...form, prize: e.target.value })} placeholder="cth: 5 WL Spot" required />
          <label className="lbl">Deadline</label>
          <input type="datetime-local" className="input" value={form.deadline} onChange={(e) => setForm({ ...form, deadline: e.target.value })} required />
          <label className="lbl">Task (1 baris = 1 task, format: Label | link-opsional)</label>
          <textarea
            className="textarea"
            value={form.requirements}
            onChange={(e) => setForm({ ...form, requirements: e.target.value })}
            placeholder={"Follow X @proyek | https://x.com/proyek\nLike & repost postingan ini | https://x.com/…\nJoin Discord"}
          />
          {msg && <div className={`alert alert-${msg.type === "ok" ? "ok" : "error"}`}>{msg.text}</div>}
          <div className="btn-row">
            <button className="btn btn-primary">Buat Giveaway</button>
          </div>
        </form>
      </div>

      <h2 className="mt">📋 Semua Giveaway</h2>
      {campaigns.length === 0 && <div className="empty">Belum ada campaign.</div>}
      {campaigns.map((c) => (
        <div className="card" key={c.id}>
          <div className="row-between">
            <h2>{c.title}</h2>
            <span className={`badge ${c.published ? "open" : "closed"}`}>
              {c.published ? "Published" : "Draft"}
            </span>
          </div>
          <p className="meta">🏆 {c.prize} • ⏰ {new Date(c.deadline).toLocaleString("id-ID")}</p>
          <div className="btn-row">
            <Link href={`/admin/c/${c.id}`} className="btn btn-primary">Kelola</Link>
            <Link href={`/c/${c.id}`} className="btn">Lihat Publik</Link>
            <button className="btn btn-danger" onClick={() => remove(c.id)}>Hapus</button>
          </div>
        </div>
      ))}
    </>
  );
}
'@

Write-File "app/admin/c/[id]/page.js" @'
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";

export default function ManageCampaign() {
  const { id } = useParams();
  const router = useRouter();
  const [campaign, setCampaign] = useState(null);
  const [entries, setEntries] = useState([]);
  const [draw, setDraw] = useState(null);
  const [winners, setWinners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [count, setCount] = useState(1);
  const [msg, setMsg] = useState(null);
  const [drawing, setDrawing] = useState(false);

  function load() {
    Promise.all([
      fetch(`/api/campaigns/${id}?all=1`).then((r) => {
        if (r.status === 401) router.push("/admin");
        return r.ok ? r.json() : null;
      }),
      fetch(`/api/campaigns/${id}/entries`).then((r) => (r.ok ? r.json() : [])),
      fetch(`/api/campaigns/${id}/draw`).then((r) => (r.ok ? r.json() : null)),
    ]).then(([c, e, d]) => {
      setCampaign(c);
      setEntries(e || []);
      setDraw(d?.draw || null);
      setWinners(d?.winners || []);
      setLoading(false);
    });
  }

  useEffect(load, [id]);

  async function setStatus(entryId, status) {
    const res = await fetch(`/api/campaigns/${id}/entries/${entryId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    if (res.ok) load();
  }

  async function togglePublish() {
    const res = await fetch(`/api/campaigns/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ published: !campaign.published }),
    });
    if (res.ok) load();
  }

  async function runDraw() {
    const approved = entries.filter((e) => e.status === "approved").length;
    if (approved < count) {
      setMsg({ type: "error", text: `Entry approved cuma ${approved}, kurang dari ${count} pemenang!` });
      return;
    }
    if (draw && !confirm("Sudah ada hasil undian. Yakin redraw? (hasil lama diganti)")) return;
    setDrawing(true);
    const res = await fetch(`/api/campaigns/${id}/draw`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ count: Number(count) }),
    });
    const data = await res.json();
    setDrawing(false);
    if (res.ok) {
      setMsg({ type: "ok", text: `Undian selesai! ${data.winners.length} pemenang terpilih 🎉` });
      load();
    } else {
      setMsg({ type: "error", text: data.error || "Gagal mengundi." });
    }
  }

  if (loading) return <div className="empty">Loading…</div>;
  if (!campaign) return <div className="empty">Campaign tidak ditemukan 😢</div>;

  const stats = {
    total: entries.length,
    pending: entries.filter((e) => e.status === "pending").length,
    approved: entries.filter((e) => e.status === "approved").length,
    rejected: entries.filter((e) => e.status === "rejected").length,
  };

  return (
    <>
      <Link href="/admin/dashboard" className="btn">← Dashboard</Link>

      <div className="card">
        <div className="row-between">
          <h2>{campaign.title}</h2>
          <button className="btn" onClick={togglePublish}>
            {campaign.published ? "Unpublish" : "Publish"}
          </button>
        </div>
        <p className="meta">
          🏆 {campaign.prize} • ⏰ {new Date(campaign.deadline).toLocaleString("id-ID")}
        </p>
        <p className="small">
          Link publik: <a href={`/c/${campaign.id}`}>{typeof window !== "undefined" ? window.location.origin : ""}/c/{campaign.id}</a>
        </p>
        <p className="meta mt">
          📥 {stats.total} total • ⏳ {stats.pending} pending • ✅ {stats.approved} approved • ❌ {stats.rejected} rejected
        </p>
      </div>

      <div className="card">
        <h2>🎰 Undian</h2>
        {draw ? (
          <>
            <div className="alert alert-ok">
              Undian sudah dilakukan pada {new Date(draw.createdAt).toLocaleString("id-ID")}
              {draw.redraw ? " (redraw)" : ""}.
            </div>
            {winners.map((w, i) => (
              <div className="winner" key={w.id}>
                <div className="rank">#{i + 1}</div>
                <div><b>@{w.xUsername}</b><div className="small" style={{ fontFamily: "monospace" }}>{w.wallet}</div></div>
              </div>
            ))}
            <div className="seed-box">seed: {draw.seed}</div>
          </>
        ) : (
          <p className="small">Belum ada undian untuk campaign ini.</p>
        )}
        <div className="row-between mt">
          <div>
            <label className="lbl">Jumlah pemenang</label>
            <input type="number" min="1" className="input" style={{ width: 120 }} value={count} onChange={(e) => setCount(e.target.value)} />
          </div>
          <button className="btn btn-success" onClick={runDraw} disabled={drawing}>
            {drawing ? "Mengundi…" : draw ? "🔄 Redraw" : "🎲 Jalankan Undian"}
          </button>
        </div>
        {msg && <div className={`alert alert-${msg.type === "ok" ? "ok" : "error"}`}>{msg.text}</div>}
      </div>

      <div className="card">
        <h2>📝 Entry Peserta</h2>
        {entries.length === 0 && <div className="empty">Belum ada entry.</div>}
        <div className="table-wrap">
          <table className="tbl">
            <thead>
              <tr>
                <th>X</th><th>Wallet</th><th>Bukti</th><th>Status</th><th>Aksi</th>
              </tr>
            </thead>
            <tbody>
              {entries.map((e) => (
                <tr key={e.id}>
                  <td>@{e.xUsername}</td>
                  <td style={{ fontFamily: "monospace", fontSize: 12 }}>
                    {e.wallet.slice(0, 10)}…{e.wallet.slice(-6)}
                  </td>
                  <td>
                    {Object.values(e.evidence || {}).filter(Boolean).map((u, i) => (
                      <a key={i} href={u} target="_blank" rel="noreferrer" className="small">🔗[{i + 1}] </a>
                    ))}
                  </td>
                  <td><span className={`badge ${e.status}`}>{e.status}</span></td>
                  <td>
                    <div className="btn-row" style={{ marginTop: 0 }}>
                      {e.status !== "approved" && (
                        <button className="btn btn-success" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setStatus(e.id, "approved")}>✓</button>
                      )}
                      {e.status !== "rejected" && (
                        <button className="btn btn-danger" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setStatus(e.id, "rejected")}>✕</button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
'@

Write-File "app/api/campaigns/route.js" @'
import { NextResponse } from "next/server";
import { readDb, writeDb, uid } from "@/lib/db";
import { isAdmin } from "@/lib/auth";

// GET /api/campaigns → publik (published saja); ?all=1 → admin (semua)
export async function GET(request) {
  const db = readDb();
  const all = request.nextUrl.searchParams.get("all");
  if (all) {
    if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    return NextResponse.json(db.campaigns);
  }
  return NextResponse.json(db.campaigns.filter((c) => c.published));
}

// POST /api/campaigns → buat campaign (admin)
export async function POST(request) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const body = await request.json();
  if (!body.title || !body.prize || !body.deadline) {
    return NextResponse.json({ error: "title, prize, deadline wajib diisi." }, { status: 400 });
  }
  const db = readDb();
  const campaign = {
    id: uid("cmp"),
    title: body.title,
    description: body.description || "",
    prize: body.prize,
    deadline: body.deadline,
    requirements: Array.isArray(body.requirements) ? body.requirements : [],
    published: true,
    createdAt: new Date().toISOString(),
  };
  db.campaigns.push(campaign);
  writeDb(db);
  return NextResponse.json(campaign, { status: 201 });
}
'@

Write-File "app/api/campaigns/[id]/route.js" @'
import { NextResponse } from "next/server";
import { readDb, writeDb } from "@/lib/db";
import { isAdmin } from "@/lib/auth";

// GET /api/campaigns/[id] → detail campaign (publik; draft hanya admin via ?all=1)
export async function GET(request, { params }) {
  const db = readDb();
  const c = db.campaigns.find((x) => x.id === params.id);
  if (!c) return NextResponse.json({ error: "Not found" }, { status: 404 });
  if (!c.published) {
    const all = request.nextUrl.searchParams.get("all");
    if (!all || !(await isAdmin())) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
  }
  return NextResponse.json(c);
}

// PATCH /api/campaigns/[id] → update (admin)
export async function PATCH(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = readDb();
  const c = db.campaigns.find((x) => x.id === params.id);
  if (!c) return NextResponse.json({ error: "Not found" }, { status: 404 });
  const body = await request.json();
  for (const k of ["title", "description", "prize", "deadline", "requirements", "published"]) {
    if (body[k] !== undefined) c[k] = body[k];
  }
  writeDb(db);
  return NextResponse.json(c);
}

// DELETE /api/campaigns/[id] → hapus + entry & draw terkait (admin)
export async function DELETE(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = readDb();
  db.campaigns = db.campaigns.filter((x) => x.id !== params.id);
  db.entries = db.entries.filter((x) => x.campaignId !== params.id);
  db.draws = db.draws.filter((x) => x.campaignId !== params.id);
  writeDb(db);
  return NextResponse.json({ ok: true });
}
'@

Write-File "app/api/campaigns/[id]/entries/route.js" @'
import { NextResponse } from "next/server";
import { readDb, writeDb, uid } from "@/lib/db";
import { isAdmin } from "@/lib/auth";

// GET → daftar entry (admin)
export async function GET(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = readDb();
  return NextResponse.json(
    db.entries
      .filter((e) => e.campaignId === params.id)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
  );
}

// POST → submit entry (publik)
export async function POST(request, { params }) {
  const db = readDb();
  const c = db.campaigns.find((x) => x.id === params.id && x.published);
  if (!c) return NextResponse.json({ error: "Giveaway tidak ditemukan." }, { status: 404 });
  if (new Date(c.deadline) < new Date()) {
    return NextResponse.json({ error: "Pendaftaran sudah ditutup." }, { status: 400 });
  }

  const body = await request.json();
  const xUsername = (body.xUsername || "").trim().replace(/^@/, "").toLowerCase();
  const wallet = (body.wallet || "").trim().toLowerCase();

  if (!xUsername || !wallet) {
    return NextResponse.json({ error: "X username dan wallet wajib diisi." }, { status: 400 });
  }
  if (!/^0x[a-f0-9]{40}$/.test(wallet)) {
    return NextResponse.json({ error: "Format wallet address tidak valid." }, { status: 400 });
  }

  // Anti-duplikat: 1 wallet / 1 username per campaign
  const dupe = db.entries.find(
    (e) =>
      e.campaignId === params.id &&
      (e.wallet.toLowerCase() === wallet || e.xUsername.toLowerCase() === xUsername)
  );
  if (dupe) {
    return NextResponse.json({ error: "Wallet / X username ini sudah terdaftar." }, { status: 409 });
  }

  const entry = {
    id: uid("ent"),
    campaignId: params.id,
    xUsername,
    wallet: body.wallet.trim(),
    evidence: body.evidence || {},
    status: "pending",
    createdAt: new Date().toISOString(),
  };
  db.entries.push(entry);
  writeDb(db);
  return NextResponse.json(entry, { status: 201 });
}
'@

Write-File "app/api/campaigns/[id]/entries/[entryId]/route.js" @'
import { NextResponse } from "next/server";
import { readDb, writeDb } from "@/lib/db";
import { isAdmin } from "@/lib/auth";

// PATCH → approve / reject entry (admin)
export async function PATCH(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const { status } = await request.json();
  if (!["pending", "approved", "rejected"].includes(status)) {
    return NextResponse.json({ error: "Status tidak valid." }, { status: 400 });
  }
  const db = readDb();
  const e = db.entries.find(
    (x) => x.id === params.entryId && x.campaignId === params.id
  );
  if (!e) return NextResponse.json({ error: "Entry tidak ditemukan." }, { status: 404 });
  e.status = status;
  writeDb(db);
  return NextResponse.json(e);
}
'@

Write-File "app/api/campaigns/[id]/draw/route.js" @'
import { NextResponse } from "next/server";
import { readDb, writeDb, uid } from "@/lib/db";
import { isAdmin } from "@/lib/auth";
import { drawWinners, newSeed } from "@/lib/raffle";

// GET → hasil undian terbaru + data pemenang (publik)
export async function GET(request, { params }) {
  const db = readDb();
  const campaign = db.campaigns.find((x) => x.id === params.id);
  if (!campaign) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const draws = db.draws
    .filter((d) => d.campaignId === params.id)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  const draw = draws[0] || null;
  const winners = draw
    ? draw.winnerIds
        .map((wid) => db.entries.find((e) => e.id === wid))
        .filter(Boolean)
    : [];

  return NextResponse.json({ campaign, draw, winners });
}

// POST → jalankan undian (admin). Body: { count }
export async function POST(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = readDb();
  const campaign = db.campaigns.find((x) => x.id === params.id);
  if (!campaign) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const { count } = await request.json();
  const n = Math.max(1, Number(count) || 1);
  const pool = db.entries.filter(
    (e) => e.campaignId === params.id && e.status === "approved"
  );
  if (pool.length < n) {
    return NextResponse.json(
      { error: `Entry approved (${pool.length}) kurang dari jumlah pemenang (${n}).` },
      { status: 400 }
    );
  }

  const seed = newSeed();
  const winnerIds = drawWinners(pool.map((e) => e.id), n, seed);
  const hadDraw = db.draws.some((d) => d.campaignId === params.id);

  // Hapus draw lama campaign ini (redraw menggantikan)
  db.draws = db.draws.filter((d) => d.campaignId !== params.id);
  const draw = {
    id: uid("drw"),
    campaignId: params.id,
    winnerIds,
    seed,
    count: n,
    redraw: hadDraw,
    createdAt: new Date().toISOString(),
  };
  db.draws.push(draw);
  writeDb(db);

  const winners = winnerIds.map((wid) => db.entries.find((e) => e.id === wid));
  return NextResponse.json({ draw, winners });
}
'@

Write-File "app/api/admin/login/route.js" @'
import { NextResponse } from "next/server";
import crypto from "node:crypto";
import { ADMIN_COOKIE, adminCookieValue } from "@/lib/auth";

// POST /api/admin/login → { password }
export async function POST(request) {
  const { password } = await request.json();
  const expected = process.env.ADMIN_PASSWORD || "";
  if (!expected || !password) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const a = Buffer.from(password);
  const b = Buffer.from(expected);
  const ok = a.length === b.length && crypto.timingSafeEqual(a, b);
  if (!ok) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const res = NextResponse.json({ ok: true });
  res.cookies.set(ADMIN_COOKIE, adminCookieValue(), {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7, // 7 hari
  });
  return res;
}
'@

Write-File "app/api/admin/logout/route.js" @'
import { NextResponse } from "next/server";
import { ADMIN_COOKIE } from "@/lib/auth";

// POST /api/admin/logout
export async function POST() {
  const res = NextResponse.json({ ok: true });
  res.cookies.delete(ADMIN_COOKIE);
  return res;
}
'@

Write-File "README.md" @'
# 🎰 Giveaway Raffle

Web app giveaway/raffle untuk proyek NFT. Peserta isi form (X username + wallet + bukti task), admin verifikasi entry, lalu undi pemenang dengan seed acak yang bisa diverifikasi.

## 🚀 Cara Jalan (Lokal)

```powershell
cd giveaway-raffle-code
npm install
copy .env.example .env.local
# edit .env.local → isi ADMIN_PASSWORD dengan password kuat
npm run dev
```

Buka http://localhost:3000

## 📖 Alur Pakai

1. **Login admin** → klik tombol "Admin" (pojok kanan atas) → masukkan password dari `.env.local`
2. **Buat giveaway** → isi judul, hadiah, deadline, dan task (format per baris: `Label | link-opsional`)
3. **Share link publik** → `http://localhost:3000/c/<id-campaign>` ke komunitas
4. **Verifikasi entry** → di halaman Kelola, klik ✓ (approve) atau ✕ (reject) per entry
5. **Undi** → masukkan jumlah pemenang → "Jalankan Undian" → hasil + seed tampil di `/c/<id>/hasil`

## 🔐 Keamanan

- Login admin pakai password env + cookie httpOnly (signature HMAC).
- Entry duplikat (wallet / X username sama) otomatis ditolak.
- Format wallet divalidasi (`0x` + 40 hex).
- Jangan commit `.env.local` ke git!

## 🌐 Deploy ke Vercel

```powershell
vercel
```

Lalu set Environment Variable `ADMIN_PASSWORD` di dashboard Vercel.

> ⚠️ **Catatan:** penyimpanan pakai file JSON (`data/db.json`). Di Vercel filesystem-nya ephemeral — data bisa hilang saat redeploy. Untuk produksi serius, ganti `lib/db.js` dengan database beneran (mis. Vercel Postgres / Supabase).

## 🧩 Struktur

```
app/
  page.js                  → daftar giveaway aktif
  c/[id]/page.js           → form ikut giveaway
  c/[id]/hasil/page.js     → pengumuman pemenang
  admin/page.js            → login admin
  admin/dashboard/page.js  → buat & daftar campaign
  admin/c/[id]/page.js     → verifikasi entry + undian
  api/...                  → REST API
lib/
  db.js      → penyimpanan JSON
  auth.js    → session admin
  raffle.js  → undian seeded (mulberry32, reproducible dari seed)
```

## 🎲 Verifikasi Undian

Setiap undian menyimpan `seed` (hex acak). Dengan seed + daftar entry approved, urutan kocokan bisa direproduksi ulang memakai algoritma di `lib/raffle.js` — transparan untuk peserta.
'@

Write-Host ""
Write-Host "SELESAI! File proyek sudah kebentuk semua." -ForegroundColor Green
Write-Host "Lanjut: npm install  ->  copy .env.example .env.local  ->  isi ADMIN_PASSWORD  ->  npm run dev"
