$ErrorActionPreference = "Stop"

function Write-File([string]$Path, [string]$Content) {
  $dir = Split-Path $Path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
  Write-Host "OK: $Path"
}

Write-File "lib/antispam.js" @'
// Anti-spam bukti task - tanpa X API berbayar.
// Verifikasi memakai oEmbed publik X (tidak butuh API key).
// Prinsip: bot menandai (flag), admin yang memutuskan diskualifikasi.

const X_DOMAINS = new Set([
  "x.com",
  "www.x.com",
  "twitter.com",
  "www.twitter.com",
  "mobile.twitter.com",
]);

export function isXUrl(url) {
  try {
    const u = new URL(url);
    return X_DOMAINS.has(u.hostname.toLowerCase());
  } catch {
    return false;
  }
}

export function extractStatusId(url) {
  const m = String(url).match(/(?:x\.com|twitter\.com)\/\w+\/status\/(\d+)/i);
  return m ? m[1] : null;
}

// Cek satu URL bukti. Return { status, author, reason }.
// status: "valid" | "invalid" | "unchecked"
export async function checkEvidenceUrl(url, xUsername) {
  const u = (url || "").trim();
  if (!u) return { status: "invalid", reason: "bukti kosong" };
  if (!/^https?:\/\//i.test(u))
    return { status: "invalid", reason: "bukan URL valid" };
  if (!isXUrl(u)) return { status: "invalid", reason: "bukan link X/Twitter" };

  const statusId = extractStatusId(u);
  if (!statusId) {
    // Link profil dsb: tidak bisa dicek otomatis -> netral
    return { status: "unchecked", reason: "tipe link tidak bisa dicek otomatis" };
  }

  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 6000);
    const r = await fetch(
      "https://publish.x.com/oembed?url=" +
        encodeURIComponent("https://x.com/i/status/" + statusId),
      { signal: ctrl.signal }
    );
    clearTimeout(t);
    if (r.status === 404)
      return { status: "invalid", reason: "tweet tidak ditemukan / link salah" };
    if (!r.ok)
      return { status: "unchecked", reason: "X tidak merespons saat dicek" };
    const j = await r.json();
    const am = String(j.author_url || "").match(
      /(?:x\.com|twitter\.com)\/(\w+)/i
    );
    const author = am ? am[1].toLowerCase() : null;
    if (author && xUsername && author !== String(xUsername).toLowerCase()) {
      return {
        status: "invalid",
        author,
        reason: "tweet milik @" + author + ", bukan @" + xUsername,
      };
    }
    return { status: "valid", author, reason: "tweet valid" };
  } catch {
    return { status: "unchecked", reason: "gagal menghubungi X" };
  }
}

// Nilai satu entry -> { flags: [string], clean: bool }.
// entries = semua entry campaign (untuk deteksi bukti duplikat).
export function scoreEntry(entry, campaign, entries) {
  const flags = [];
  const reqs = (campaign && campaign.requirements) || [];
  const ev = entry.evidence || {};
  const chk = entry.evidenceCheck || {};

  for (const r of reqs) {
    const url = (ev[r.id] || "").trim();
    if (!url) {
      flags.push("bukti kosong: " + r.label);
      continue;
    }
    const c = chk[r.id];
    if (c && c.status === "invalid") {
      flags.push("bukti bermasalah (" + r.label + "): " + c.reason);
    }
  }

  // Bukti yang sama dipakai entry lain = indikasi kuat curang
  const urls = Object.values(ev)
    .map((s) => (s || "").trim().toLowerCase())
    .filter(Boolean);
  if (urls.length > 0) {
    for (const other of entries || []) {
      if (other.id === entry.id) continue;
      if (other.campaignId !== entry.campaignId) continue;
      const oUrls = Object.values(other.evidence || {}).map((s) =>
        (s || "").trim().toLowerCase()
      );
      if (urls.some((u) => oUrls.includes(u))) {
        flags.push("link bukti dipakai juga oleh @" + other.xUsername);
        break;
      }
    }
  }

  return { flags, clean: flags.length === 0 };
}
'@

Write-File "app/api/campaigns/[id]/entries/route.js" @'
import { NextResponse } from "next/server";
import { readDb, writeDb, uid } from "@/lib/db";
import { isAdmin } from "@/lib/auth";
import { checkEvidenceUrl } from "@/lib/antispam";

// GET -> daftar entry (admin)
export async function GET(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = readDb();
  return NextResponse.json(
    db.entries
      .filter((e) => e.campaignId === params.id)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
  );
}

// POST -> submit entry (publik)
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

  // Bukti wajib untuk SEMUA task + cek otomatis via oEmbed X
  const reqs = c.requirements || [];
  const evidence = body.evidence || {};
  for (const r of reqs) {
    if (!(evidence[r.id] || "").trim()) {
      return NextResponse.json({ error: `Link bukti untuk "${r.label}" wajib diisi.` }, { status: 400 });
    }
  }
  const evidenceCheck = {};
  await Promise.all(
    reqs.map(async (r) => {
      evidenceCheck[r.id] = await checkEvidenceUrl(evidence[r.id], xUsername);
    })
  );
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
    evidence,
    evidenceCheck,
    status: "pending",
    createdAt: new Date().toISOString(),
  };
  db.entries.push(entry);
  writeDb(db);
  return NextResponse.json(entry, { status: 201 });
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
 const [wallet, setWallet] = useState("");
 const [xUsername, setXUsername] = useState("");
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
 const noProof = reqs.filter((r) => !(evidence[r.id] || "").trim());
 if (noProof.length > 0) {
 setMsg({ type: "error", text: `Isi link bukti untuk: ${noProof.map((r) => r.label).join(", ")}` });
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
 <Link href={`/c/${id}/hasil`}>Lihat hasil undian {"\u2192"}</Link>
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
 placeholder="Link bukti (wajib) - cth: https://x.com/username/status/..."
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
 1 akun X = 1 entry. Wallet / username duplikat otomatis ditolak. Bukti dicek otomatis oleh bot anti-spam.
 </p>
 </form>
 </div>
 )}
 </>
 );
}
'@

Write-File "app/admin/c/[id]/page.js" @'
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { scoreEntry } from "@/lib/antispam";

export default function ManageCampaign() {
 const { id } = useParams();
 const router = useRouter();
 const [campaign, setCampaign] = useState(null);
 const [entries, setEntries] = useState([]);
 const [filter, setFilter] = useState("all");
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

 const scored = entries.map((e) => ({ e, s: scoreEntry(e, campaign, entries) }));
 const flaggedCount = scored.filter((x) => !x.s.clean).length;
 const shown =
 filter === "flagged"
 ? scored.filter((x) => !x.s.clean)
 : filter === "clean"
 ? scored.filter((x) => x.s.clean)
 : scored;

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
 {entries.length > 0 && (
 <>
 <div className="btn-row" style={{ marginBottom: 8 }}>
 <button className={`btn ${filter === "all" ? "btn-primary" : ""}`} style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setFilter("all")}>Semua ({entries.length})</button>
 <button className={`btn ${filter === "flagged" ? "btn-primary" : ""}`} style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setFilter("flagged")}>{"\u{1F6A9}"} Bermasalah ({flaggedCount})</button>
 <button className={`btn ${filter === "clean" ? "btn-primary" : ""}`} style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setFilter("clean")}>Bersih ({entries.length - flaggedCount})</button>
 </div>
 <div className="table-wrap">
 <table className="tbl">
 <thead>
 <tr>
 <th>X</th><th>Wallet</th><th>Bukti + Cek Bot</th><th>Status</th><th>Aksi</th>
 </tr>
 </thead>
 <tbody>
 {shown.map(({ e, s }) => (
 <tr key={e.id}>
 <td>@{e.xUsername}</td>
 <td style={{ fontFamily: "monospace", fontSize: 12 }}>
 {e.wallet.slice(0, 10)}...{e.wallet.slice(-6)}
 </td>
 <td>
 {(campaign.requirements || []).map((r) => {
 const url = (e.evidence || {})[r.id];
 const c = (e.evidenceCheck || {})[r.id];
 return (
 <span key={r.id} style={{ marginRight: 8 }} title={r.label}>
 {url ? (
 <a href={url} target="_blank" rel="noreferrer" className="small">[{r.label.slice(0, 12)}]</a>
 ) : (
 <span className="badge flag">no proof</span>
 )}{" "}
 {c && c.status === "valid" && <span className="badge ok" title={c.reason}>{"\u2713"}</span>}
 {c && c.status === "invalid" && <span className="badge flag" title={c.reason}>{"\u2715"}</span>}
 {(!c || c.status === "unchecked") && <span className="badge na" title={(c && c.reason) || "belum dicek"}>?</span>}
 </span>
 );
 })}
 {s.flags.length > 0 && (
 <div style={{ marginTop: 4 }}>
 {s.flags.map((f, i) => (
 <div key={i} className="small" style={{ color: "#e74c3c" }}>{"\u26A0"} {f}</div>
 ))}
 </div>
 )}
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
 </>
 )}
 </div>
 </>
 );
}
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
.badge.ok { background: #0d3327; color: var(--accent2); }
.badge.flag { background: #3a1418; color: var(--danger); }
.badge.na { background: #2a2f45; color: var(--muted); }

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

Write-File "README.md" @'
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

Write-Host ""
Write-Host "Selesai! Bot anti-spam terpasang." -ForegroundColor Green
Write-Host "Restart npm run dev, lalu cek halaman Kelola." -ForegroundColor Yellow
