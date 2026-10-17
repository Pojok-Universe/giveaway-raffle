# FIX EMOJI: emoji ditulis sebagai kode \u{...} (ASCII murni di file, tampil asli di browser)
# Dijamin anti-rusak saat copas. Cara: .\fix-emoji.ps1  (di folder proyek)
$ErrorActionPreference = "Stop"

function Write-File($p, $content) {
    $base = (Get-Location).Path
    $full = [IO.Path]::Combine($base, $p)
    [IO.File]::WriteAllText($full, $content, [Text.UTF8Encoding]::new($false))
    Write-Host "OK: $p"
}

Write-File "app/layout.js" @'
import "./globals.css";

export const metadata = {
 title: "Giveaway Raffle",
 description: "Ikuti giveaway & raffle transparan untuk proyek NFT",
};

export default function RootLayout({ children }) {
 return (
 <html lang="id">
 <head>
 <meta charSet="utf-8" />
 </head>
 <body>
 <div className="container">
 <nav className="nav">
 <a href="/" className="logo">
 {"\u{1F3B0}"} Giveaway<span>Raffle</span>
 </a>
 <a href="/admin" className="btn">
 Admin
 </a>
 </nav>
 {children}
 <div className="footer">
 Giveaway Raffle - undian transparan dengan seed terverifikasi
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
 <h1>{"\u{1F389}"} Giveaway Aktif</h1>
 <p>Ikuti giveaway, selesaikan task, menangkan hadiah. Pemenang diundi transparan.</p>
 </div>

 {campaigns.length === 0 && (
 <div className="empty">Belum ada giveaway aktif. Cek lagi nanti! {"\u{1F440}"}</div>
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
 {"\u{1F3C6}"} {c.prize} &nbsp;{"\u2022"}&nbsp; {n} peserta lolos &nbsp;{"\u2022"}&nbsp; {"\u23F0"} {" "}
 {timeLeft(c.deadline)}
 </p>
 <p style={{ fontSize: 14, color: "#c4cbe2" }}>
 {c.description?.slice(0, 140)}
 {c.description?.length > 140 ? "..." : ""}
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
 setMsg({ type: "ok", text: "Entry terkirim! Tunggu verifikasi admin. Good luck! \u{1F340}" });
 setXUsername("");
 setWallet("");
 setChecks({});
 setEvidence({});
 } else {
 setMsg({ type: "error", text: data.error || "Gagal mengirim entry." });
 }
 }

 if (loading) return <div className="empty">Loading...</div>;
 if (!campaign) return <div className="empty">Giveaway tidak ditemukan </div>;

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
 {"\u{1F3C6}"} Hadiah: {campaign.prize} &nbsp;{"\u2022"}&nbsp; {"\u23F0"} Deadline:{" "}
 {new Date(campaign.deadline).toLocaleString("id-ID")}
 </p>
 <p style={{ fontSize: 14, whiteSpace: "pre-wrap" }}>{campaign.description}</p>
 </div>

 {closed ? (
 <div className="alert alert-info">
 Pendaftaran sudah ditutup.{" "}
 <Link href={`/c/${id}/hasil`}>Lihat hasil undian -></Link>
 </div>
 ) : (
 <div className="card">
 <h2>{"\u{1F4DD}"} Form Pendaftaran</h2>
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
 Buka {"\u2197"}
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
 placeholder="0x..."
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
 {sending ? "Mengirim..." : "Kirim Entry \u{1F680}"}
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

 if (loading) return <div className="empty">Loading...</div>;
 if (!data) return <div className="empty">Giveaway tidak ditemukan {"\u{1F622}"}</div>;

 const { campaign, draw, winners } = data;

 return (
 <>
 <div className="card">
 <h2>{"\u{1F3C6}"} Hasil Undian - {campaign.title}</h2>
 <p className="meta">Hadiah: {campaign.prize}</p>
 </div>

 {!draw ? (
 <div className="alert alert-info">
 Undian belum dilakukan. Pemenang akan diumumkan di sini setelah draw oleh admin.
 </div>
 ) : (
 <div className="card">
 <h2>{"\u{1F389}"} Pemenang ({winners.length})</h2>
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
 {"\u2190"} Kembali ke Giveaway
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
 <h2>{"\u{1F510}"} Admin Login</h2>
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
 {sending ? "Masuk..." : "Masuk"}
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
 setMsg({ type: "ok", text: "Campaign dibuat! \u{1F389}" });
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

 if (loading) return <div className="empty">Loading...</div>;

 return (
 <>
 <div className="row-between">
 <h2>{"\u{1F4CA}"} Dashboard Admin</h2>
 <button className="btn" onClick={logout}>
 Logout
 </button>
 </div>

 <div className="card">
 <h2>{"\u2795"} Buat Giveaway Baru</h2>
 <form onSubmit={create}>
 <label className="lbl">Judul</label>
 <input className="input" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="cth: WL Spot Giveaway #1" required />
 <label className="lbl">Deskripsi</label>
 <textarea className="textarea" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="Syarat & info giveaway..." />
 <label className="lbl">Hadiah</label>
 <input className="input" value={form.prize} onChange={(e) => setForm({ ...form, prize: e.target.value })} placeholder="cth: 5 WL Spot" required />
 <label className="lbl">Deadline</label>
 <input type="datetime-local" className="input" value={form.deadline} onChange={(e) => setForm({ ...form, deadline: e.target.value })} required />
 <label className="lbl">Task (1 baris = 1 task, format: Label | link-opsional)</label>
 <textarea
 className="textarea"
 value={form.requirements}
 onChange={(e) => setForm({ ...form, requirements: e.target.value })}
 placeholder={"Follow X @proyek | https://x.com/proyek\nLike & repost postingan ini | https://x.com/...\nJoin Discord"}
 />
 {msg && <div className={`alert alert-${msg.type === "ok" ? "ok" : "error"}`}>{msg.text}</div>}
 <div className="btn-row">
 <button className="btn btn-primary">Buat Giveaway</button>
 </div>
 </form>
 </div>

 <h2 className="mt">{"\u{1F4CB}"} Semua Giveaway</h2>
 {campaigns.length === 0 && <div className="empty">Belum ada campaign.</div>}
 {campaigns.map((c) => (
 <div className="card" key={c.id}>
 <div className="row-between">
 <h2>{c.title}</h2>
 <span className={`badge ${c.published ? "open" : "closed"}`}>
 {c.published ? "Published" : "Draft"}
 </span>
 </div>
 <p className="meta"> {c.prize} - {new Date(c.deadline).toLocaleString("id-ID")}</p>
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
 setMsg({ type: "ok", text: `Undian selesai! ${data.winners.length} pemenang terpilih \u{1F389}` });
 load();
 } else {
 setMsg({ type: "error", text: data.error || "Gagal mengundi." });
 }
 }

 if (loading) return <div className="empty">Loading...</div>;
 if (!campaign) return <div className="empty">Campaign tidak ditemukan </div>;

 const stats = {
 total: entries.length,
 pending: entries.filter((e) => e.status === "pending").length,
 approved: entries.filter((e) => e.status === "approved").length,
 rejected: entries.filter((e) => e.status === "rejected").length,
 };

 return (
 <>
 <Link href="/admin/dashboard" className="btn">{"\u2190"} Dashboard</Link>

 <div className="card">
 <div className="row-between">
 <h2>{campaign.title}</h2>
 <button className="btn" onClick={togglePublish}>
 {campaign.published ? "Unpublish" : "Publish"}
 </button>
 </div>
 <p className="meta">
 {"\u{1F3C6}"} {campaign.prize} {"\u2022"} {"\u23F0"} {new Date(campaign.deadline).toLocaleString("id-ID")}
 </p>
 <p className="small">
 Link publik: <a href={`/c/${campaign.id}`}>{typeof window !== "undefined" ? window.location.origin : ""}/c/{campaign.id}</a>
 </p>
 <p className="meta mt">
 {"\u{1F4E5}"} {stats.total} total {"\u2022"} {"\u23F3"} {stats.pending} pending {"\u2022"} {"\u2705"} {stats.approved} approved {"\u2022"} {"\u274C"} {stats.rejected} rejected
 </p>
 </div>

 <div className="card">
 <h2>{"\u{1F3B0}"} Undian</h2>
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
 {drawing ? "Mengundi..." : draw ? " \u{1F504} Redraw" : " \u{1F3B2} Jalankan Undian"}
 </button>
 </div>
 {msg && <div className={`alert alert-${msg.type === "ok" ? "ok" : "error"}`}>{msg.text}</div>}
 </div>

 <div className="card">
 <h2>{"\u{1F4DD}"} Entry Peserta</h2>
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
 {e.wallet.slice(0, 10)}...{e.wallet.slice(-6)}
 </td>
 <td>
 {Object.values(e.evidence || {}).filter(Boolean).map((u, i) => (
 <a key={i} href={u} target="_blank" rel="noreferrer" className="small">[{i + 1}] </a>
 ))}
 </td>
 <td><span className={`badge ${e.status}`}>{e.status}</span></td>
 <td>
 <div className="btn-row" style={{ marginTop: 0 }}>
 {e.status !== "approved" && (
 <button className="btn btn-success" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setStatus(e.id, "approved")}>{"\u2713"}</button>
 )}
 {e.status !== "rejected" && (
 <button className="btn btn-danger" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setStatus(e.id, "rejected")}>{"\u2715"}</button>
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

Write-Host ""
Write-Host "SELESAI! Refresh browser (Ctrl+Shift+R) - emoji tampil cantik." -ForegroundColor Green
