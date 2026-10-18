$ErrorActionPreference = "Stop"

function Write-File([string]$Path, [string]$Content) {
  $dir = Split-Path $Path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
  Write-Host "OK: $Path"
}

Write-File "app/api/campaigns/[id]/verify-task/route.js" @'
import { NextResponse } from "next/server";
import { readDb, hitRateLimit } from "@/lib/db";
import { checkEvidenceUrl, tweetContainsCode } from "@/lib/antispam";

function clientIp(request) {
  const fwd = request.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0].trim();
  return request.headers.get("x-real-ip") || "unknown";
}

// POST -> verifikasi satu task (tanpa membuat entry).
// Body: { reqId, xUsername, url }
export async function POST(request, { params }) {
  // Rate limit ringan: 30x per jam per IP per campaign (user boleh retry).
  const rl = await hitRateLimit(`verify:${params.id}:${clientIp(request)}`, 30, 3600);
  if (rl.limited) {
    return NextResponse.json(
      { ok: false, reason: "Terlalu banyak percobaan. Tunggu sebentar." },
      { status: 429 }
    );
  }

  const db = await readDb();
  const c = db.campaigns.find((x) => x.id === params.id && x.published);
  if (!c) return NextResponse.json({ ok: false, reason: "Giveaway tidak ditemukan." }, { status: 404 });
  if (new Date(c.deadline) < new Date()) {
    return NextResponse.json({ ok: false, reason: "Pendaftaran sudah ditutup." }, { status: 400 });
  }

  const body = await request.json();
  const reqId = (body.reqId || "").trim();
  const xUsername = (body.xUsername || "").trim().replace(/^@/, "").toLowerCase();
  const url = (body.url || "").trim();

  if (!reqId || !xUsername || !url) {
    return NextResponse.json({ ok: false, reason: "Data tidak lengkap." }, { status: 400 });
  }
  if (!/^[a-z0-9_]{1,15}$/.test(xUsername)) {
    return NextResponse.json({ ok: false, reason: "Format X username tidak valid." }, { status: 400 });
  }

  const req = (c.requirements || []).find((r) => r.id === reqId);
  if (!req) return NextResponse.json({ ok: false, reason: "Task tidak ditemukan." }, { status: 404 });
  if (req.showDone) {
    return NextResponse.json({ ok: false, reason: "Task ini cukup tandai Done." }, { status: 400 });
  }
  if (req.proofType === "photo") {
    return NextResponse.json({ ok: false, reason: "Task ini memakai bukti foto." }, { status: 400 });
  }

  const check = await checkEvidenceUrl(url, xUsername);
  if (check.status === "invalid") {
    return NextResponse.json({ ok: false, reason: check.reason }, { status: 200 });
  }

  if (c.code) {
    const hasCode = await tweetContainsCode(url, c.code);
    if (hasCode === false) {
      return NextResponse.json(
        { ok: false, reason: `Tweet harus memuat kode "${c.code}".` },
        { status: 200 }
      );
    }
  }

  return NextResponse.json({ ok: true, author: check.author || xUsername });
}
'@

Write-File "app/api/campaigns/[id]/entries/route.js" @'
import { NextResponse } from "next/server";
import { readDb, writeDb, uid, hitRateLimit } from "@/lib/db";
import { isAdmin } from "@/lib/auth";
import { checkEvidenceUrl, tweetContainsCode } from "@/lib/antispam";

// Ambil IP client (hormati proxy/CDN)
function clientIp(request) {
  const fwd = request.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0].trim();
  return request.headers.get("x-real-ip") || "unknown";
}

// GET -> daftar entry (admin)
export async function GET(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = await readDb();
  return NextResponse.json(
    db.entries
      .filter((e) => e.campaignId === params.id)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
  );
}

// POST -> submit entry (publik)
export async function POST(request, { params }) {
  const db = await readDb();
  const c = db.campaigns.find((x) => x.id === params.id && x.published);
  if (!c) return NextResponse.json({ error: "Giveaway tidak ditemukan." }, { status: 404 });
  if (new Date(c.deadline) < new Date()) {
    return NextResponse.json({ error: "Pendaftaran sudah ditutup." }, { status: 400 });
  }

  // Rate limit: maks 1 submit per IP per campaign per 24 jam
  const rl = await hitRateLimit(`entry:${params.id}:${clientIp(request)}`, 1, 86400);
  if (rl.limited) {
    return NextResponse.json(
      { error: "Terlalu banyak pendaftaran dari jaringan ini. Coba lagi nanti." },
      { status: 429 }
    );
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
  if (!/^[a-z0-9_]{1,15}$/.test(xUsername)) {
    return NextResponse.json({ error: "Format X username tidak valid." }, { status: 400 });
  }

  // Bukti wajib untuk task yang bisa diverifikasi.
  // - Task link (reply/quote): cek otomatis via oEmbed X
  // - Task photo: URL dari Supabase Storage, skip oEmbed -> review manual
  // - Task showDone (follow/like): self-declared, tanpa bukti link
  const reqs = c.requirements || [];
  const evidence = body.evidence || {};
  for (const r of reqs) {
    if (r.showDone) continue;
    if (!(evidence[r.id] || "").trim()) {
      return NextResponse.json({ error: `Bukti untuk "${r.label}" wajib diisi.` }, { status: 400 });
    }
    if (r.proofType === "photo") {
      const u = (evidence[r.id] || "").trim();
      if (!/^https?:\/\//i.test(u)) {
        return NextResponse.json({ error: `Bukti foto "${r.label}" tidak valid. Upload ulang.` }, { status: 400 });
      }
    }
  }
  const evidenceCheck = {};
  await Promise.all(
    reqs.map(async (r) => {
      if (r.showDone) {
        evidenceCheck[r.id] = { status: "unchecked", reason: "self-declared (Done)" };
        return;
      }
      if (r.proofType === "photo") {
        evidenceCheck[r.id] = { status: "manual", reason: "foto — perlu review manual" };
        return;
      }
      evidenceCheck[r.id] = await checkEvidenceUrl(evidence[r.id], xUsername);
    })
  );
  const badProof = reqs.find((r) => evidenceCheck[r.id] && evidenceCheck[r.id].status === "invalid");
  if (badProof) {
    return NextResponse.json(
      { error: `Bukti "${badProof.label}" bermasalah: ${evidenceCheck[badProof.id].reason}` },
      { status: 400 }
    );
  }

  // Kode campaign: minimal 1 bukti tweet harus memuat kode (anti copas link asal)
  if (c.code) {
    const urls = reqs.map((r) => (evidence[r.id] || "").trim()).filter(Boolean);
    let codeFound = false;
    let codeCheckable = false;
    for (const u of urls) {
      const res = await tweetContainsCode(u, c.code);
      if (res === true) { codeFound = true; break; }
      if (res !== "unchecked") codeCheckable = true;
    }
    if (!codeFound && codeCheckable) {
      return NextResponse.json(
        { error: `Bukti tweet harus memuat kode "${c.code}".` },
        { status: 400 }
      );
    }
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
  await writeDb(db);
  return NextResponse.json(entry, { status: 201 });
}
'@

Write-File "app/c/[id]/page.js" @'
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";

// Status per task: todo | busy | ok | err
export default function CampaignPage() {
 const { id } = useParams();
 const [campaign, setCampaign] = useState(null);
 const [loading, setLoading] = useState(true);
 const [wallet, setWallet] = useState("");
 const [xUsername, setXUsername] = useState("");
 const [doneMap, setDoneMap] = useState({});
 const [taskState, setTaskState] = useState({});
 const [taskUrl, setTaskUrl] = useState({});
 const [photoFiles, setPhotoFiles] = useState({});
 const [expandedTask, setExpandedTask] = useState(null);
 const [openedMap, setOpenedMap] = useState({});
 const [copied, setCopied] = useState(false);
 const [msg, setMsg] = useState(null);
 const [sending, setSending] = useState(false);
 const [uploading, setUploading] = useState(false);

 useEffect(() => {
 fetch(`/api/campaigns/${id}`)
 .then((r) => (r.ok ? r.json() : null))
 .then((d) => {
 setCampaign(d);
 setLoading(false);
 });
 }, [id]);

 const reqs = campaign?.requirements || [];

 // Verifikasi task terikat ke username — ganti username = reset verifikasi link.
 function onUsernameChange(v) {
 setXUsername(v);
 setTaskState({});
 }

 function isTaskDone(r) {
 if (r.showDone) return !!doneMap[r.id];
 if (r.proofType === "photo") return !!photoFiles[r.id];
 return taskState[r.id]?.state === "ok";
 }

 const doneCount = reqs.filter(isTaskDone).length;
 const allDone = reqs.length > 0 && doneCount === reqs.length;

 async function verifyTask(r) {
 const url = (taskUrl[r.id] || "").trim();
 const user = xUsername.trim().replace(/^@/, "");
 if (!user) {
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: "Fill in your X username above first." } });
 return;
 }
 if (!url) {
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: "Paste your post link first." } });
 return;
 }
 setTaskState({ ...taskState, [r.id]: { state: "busy", msg: "Verifying..." } });
 try {
 const res = await fetch(`/api/campaigns/${id}/verify-task`, {
 method: "POST",
 headers: { "Content-Type": "application/json" },
 body: JSON.stringify({ reqId: r.id, xUsername: user, url }),
 });
 const data = await res.json();
 if (data.ok) {
 setTaskState({ ...taskState, [r.id]: { state: "ok", msg: "Verified ✓", url } });
 } else {
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: data.reason || "Verifikasi gagal." } });
 }
 } catch {
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: "Failed to reach the server." } });
 }
 }

 function copyPayload() {
 const t = campaign?.code || "";
 if (!t) return;
 if (navigator.clipboard) {
 navigator.clipboard.writeText(t).then(() => {
 setCopied(true);
 setTimeout(() => setCopied(false), 1500);
 });
 }
 }

 async function submit(e) {
 e.preventDefault();
 setMsg(null);
 const user = xUsername.trim().replace(/^@/, "");
 if (!user || !wallet.trim()) {
 setMsg({ type: "error", text: "Fill in your X username and wallet address!" });
 return;
 }
 const notDone = reqs.filter((r) => !isTaskDone(r));
 if (notDone.length > 0) {
 setMsg({ type: "error", text: `Finish first: ${notDone.map((r) => r.label).join(", ")}` });
 return;
 }

 // Upload foto dulu (task photo — dormant)
 setUploading(true);
 const finalEvidence = {};
 for (const r of reqs) {
 if (r.proofType === "photo" && photoFiles[r.id]) {
 const fd = new FormData();
 fd.append("file", photoFiles[r.id]);
 try {
 const up = await fetch("/api/upload", { method: "POST", body: fd });
 const ud = await up.json();
 if (!up.ok) throw new Error(ud.error || "Upload foto gagal.");
 finalEvidence[r.id] = ud.url;
 } catch (err) {
 setUploading(false);
 setMsg({ type: "error", text: err.message });
 return;
 }
 } else if (!r.showDone && taskState[r.id]?.url) {
 finalEvidence[r.id] = taskState[r.id].url;
 }
 }
 setUploading(false);

 setSending(true);
 const res = await fetch(`/api/campaigns/${id}/entries`, {
 method: "POST",
 headers: { "Content-Type": "application/json" },
 body: JSON.stringify({ xUsername: user, wallet: wallet.trim(), evidence: finalEvidence }),
 });
 const data = await res.json();
 setSending(false);
 if (res.ok) {
 setMsg({ type: "ok", text: "Entry submitted! Awaiting admin review. Good luck!" });
 setXUsername("");
 setWallet("");
 setDoneMap({});
 setTaskState({});
 setTaskUrl({});
 setPhotoFiles({});
 setExpandedTask(null);
 setOpenedMap({});
 } else {
 setMsg({ type: "error", text: data.error || "Failed to submit entry." });
 }
 }

 if (loading) return <div className="empty">Loading...</div>;
 if (!campaign) return <div className="empty">Giveaway not found </div>;

 const closed = new Date(campaign.deadline) < new Date();

 function statusBadge(r) {
 if (isTaskDone(r)) return <span className="badge ok">OK ✓</span>;
 const st = taskState[r.id]?.state;
 if (st === "busy") return <span className="badge na">...</span>;
 if (st === "err") return <span className="badge flag">Failed</span>;
 return <span className="badge na">Todo</span>;
 }

 return (
 <>
 <div className="card">
 <div className="row-between">
 <h2>{campaign.title}</h2>
 <span className={`badge ${closed ? "closed" : "open"}`}>
 {closed ? "Closed" : "Live"}
 </span>
 </div>
 <p className="meta">
 Prize: {campaign.prize} &nbsp;•&nbsp; Deadline:{" "}
 {new Date(campaign.deadline).toLocaleString("en-US")}
 </p>
 {campaign.code && (
 <p className="alert alert-info" style={{ marginTop: 8 }}>
 Campaign code: <b>{campaign.code}</b> — must be included in your proof tweet.
 </p>
 )}
 <p style={{ fontSize: 14, whiteSpace: "pre-wrap" }}>{campaign.description}</p>
 </div>

 {closed ? (
 <div className="alert alert-info">
 Registration is closed.{" "}
 <Link href={`/c/${id}/hasil`}>View draw results →</Link>
 </div>
 ) : (
 <div className="card">
 <h2>Entry Form</h2>

 <label className="lbl">X username (without @) — fill this in before verifying tasks</label>
 <input
 className="input"
 placeholder="e.g. agunverse"
 value={xUsername}
 onChange={(e) => onUsernameChange(e.target.value)}
 />

 <label className="lbl">Wallet Address</label>
 <input
 className="input"
 placeholder="0x..."
 value={wallet}
 onChange={(e) => setWallet(e.target.value)}
 />

 <label className="lbl">Complete the tasks below (click each task):</label>
 {reqs.map((r, i) => {
 const st = taskState[r.id];
 const done = isTaskDone(r);
 const expanded = expandedTask === r.id;
 return (
 <div className={`task-card ${done ? "ok" : st?.state === "err" ? "err" : ""}`} key={r.id}>
 <div
 className="task-head"
 onClick={() => setExpandedTask(expanded ? null : r.id)}
 style={{ cursor: "pointer", marginBottom: expanded ? 8 : 0 }}
 >
 <b>{i + 1}. {r.label}</b>
 <span style={{ display: "flex", gap: 8, alignItems: "center" }}>
 {statusBadge(r)}
 <span className="small">{expanded ? "▲" : "▼"}</span>
 </span>
 </div>

 {expanded && (
 <div className="task-body">
 {r.url && (
 <a
 href={r.url}
 target="_blank"
 rel="noreferrer"
 className="btn"
 style={{ fontSize: 12, padding: "6px 12px" }}
 onClick={() => setOpenedMap({ ...openedMap, [r.id]: true })}
 >
 Open ↗
 </a>
 )}

 {r.showDone && (openedMap[r.id] || !r.url) && (
 <button
 type="button"
 className={`btn ${done ? "btn-success" : ""}`}
 style={{ marginTop: 8, width: "100%" }}
 onClick={() => setDoneMap({ ...doneMap, [r.id]: !doneMap[r.id] })}
 >
 {done ? "Done" : "I've done this"}
 </button>
 )}
 {r.showDone && !openedMap[r.id] && r.url && !done && (
 <p className="small" style={{ marginTop: 8 }}>
 Click "Open" above and complete the task first — the Done button appears after that.
 </p>
 )}

 {!r.showDone && r.proofType !== "photo" && (
 <div style={{ marginTop: 8 }}>
 {campaign.code && (
 <div className="payload-box">
 <span className="small">PAYLOAD</span>
 <code style={{ flex: 1, wordBreak: "break-all" }}>{campaign.code}</code>
 <button type="button" className="btn" style={{ fontSize: 12, padding: "4px 10px" }} onClick={copyPayload}>
 {copied ? "Copied ✓" : "Copy"}
 </button>
 </div>
 )}
 <p className="small" style={{ marginBottom: 6 }}>
 {campaign.code
 ? "Include the code above in your reply, then paste the link:"
 : "Paste your reply link:"}
 </p>
 <div style={{ display: "flex", gap: 8 }}>
 <input
 className="input"
 style={{ margin: 0 }}
 placeholder="https://x.com/username/status/..."
 value={taskUrl[r.id] || ""}
 onChange={(e) => {
 setTaskUrl({ ...taskUrl, [r.id]: e.target.value });
 if (st?.state === "err" || st?.state === "ok") {
 setTaskState({ ...taskState, [r.id]: { state: "todo" } });
 }
 }}
 />
 <button
 type="button"
 className="btn btn-primary"
 style={{ whiteSpace: "nowrap" }}
 disabled={st?.state === "busy"}
 onClick={() => verifyTask(r)}
 >
 {st?.state === "busy" ? "..." : done ? "Re-verify" : "Verify Post"}
 </button>
 </div>
 </div>
 )}

 {r.proofType === "photo" && (
 <div style={{ marginTop: 8 }}>
 <input
 type="file"
 accept="image/*"
 className="input"
 onChange={(e) => setPhotoFiles({ ...photoFiles, [r.id]: e.target.files?.[0] || null })}
 />
 {photoFiles[r.id] && (
 <p className="small" style={{ marginTop: 4 }}>{photoFiles[r.id].name}</p>
 )}
 </div>
 )}

 {st?.msg && st.state !== "todo" && (
 <p className="small" style={{ marginTop: 6, color: st.state === "ok" ? "#22d3a5" : st.state === "err" ? "#ff5d6c" : "#9aa4c0" }}>
 {st.msg}
 </p>
 )}
 </div>
 )}
 </div>
 );
 })}

 <div className="mt">
 <div className="row-between">
 <span className="small">Progress</span>
 <span className="small"><b>{doneCount}/{reqs.length}</b> tasks done</span>
 </div>
 <div className="progress-wrap">
 <div className="progress-fill" style={{ width: reqs.length ? `${(doneCount / reqs.length) * 100}%` : "0%" }} />
 </div>
 </div>

 {msg && (
 <div className={`alert alert-${msg.type === "ok" ? "ok" : "error"}`}>
 {msg.text}
 </div>
 )}

 <form onSubmit={submit}>
 <div className="btn-row">
 <button className="btn btn-success" disabled={sending || uploading || !allDone} style={{ width: "100%" }}>
 {uploading ? "Uploading photo..." : sending ? "Sending..." : allDone ? "Submit Entry" : `Finish ${reqs.length - doneCount} tasks first`}
 </button>
 </div>
 </form>
 <p className="small mt">
 1 X account = 1 entry. Duplicate wallets/usernames are rejected automatically. Reply tasks are checked when you press Verify Post.
 </p>
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
 const isPhoto = r.proofType === "photo";
 return (
 <span key={r.id} style={{ marginRight: 8 }} title={r.label}>
 {url ? (
 isPhoto ? (
 <a href={url} target="_blank" rel="noreferrer">
 <img src={url} alt={r.label} style={{ width: 64, height: 64, objectFit: "cover", borderRadius: 8, verticalAlign: "middle" }} />
 </a>
 ) : (
 <a href={url} target="_blank" rel="noreferrer" className="small">[{r.label.slice(0, 12)}]</a>
 )
 ) : r.showDone ? (
 <span className="badge ok" title="Self-declared Done">Done ✓</span>
 ) : (
 <span className="badge flag">no proof</span>
 )}{" "}
 {c && c.status === "valid" && <span className="badge ok" title={c.reason}>{"\u2713"}</span>}
 {c && c.status === "invalid" && <span className="badge flag" title={c.reason}>{"\u2715"}</span>}
 {c && c.status === "manual" && <span className="badge na" title={c.reason}>{"\u{1F4F7}"}</span>}
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

// Cek apakah tweet berisi kode campaign (case-insensitive).
// Return true / false / "unchecked" (oEmbed gagal atau bukan link status).
export async function tweetContainsCode(url, code) {
  if (!code) return true;
  const statusId = extractStatusId(url);
  if (!statusId) return "unchecked";
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 6000);
    const r = await fetch(
      "https://publish.x.com/oembed?url=" +
        encodeURIComponent("https://x.com/i/status/" + statusId),
      { signal: ctrl.signal }
    );
    clearTimeout(t);
    if (!r.ok) return "unchecked";
    const j = await r.json();
    const text = String(j.html || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"');
    return text.toLowerCase().includes(String(code).toLowerCase());
  } catch {
    return "unchecked";
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
      // Task showDone = self-declared, tanpa bukti link -> bukan flag.
      if (!r.showDone) flags.push("bukti kosong: " + r.label);
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

/* Guided task verification flow */
.task-card {
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 14px;
  margin: 10px 0;
  background: var(--bg2);
  transition: border-color 0.2s;
}
.task-card.ok { border-color: var(--accent2); }
.task-card.err { border-color: var(--danger); }
.task-head {
  display: flex; justify-content: space-between; align-items: center;
  gap: 8px; margin-bottom: 6px;
}
.payload-box {
  display: flex; gap: 8px; align-items: center;
  background: var(--bg);
  border: 1px dashed var(--accent);
  border-radius: 8px;
  padding: 10px 12px;
  margin: 8px 0;
}
.payload-box code { font-size: 14px; color: var(--accent2); font-weight: 700; }
.progress-wrap {
  background: var(--bg2);
  border: 1px solid var(--border);
  border-radius: 999px;
  height: 12px;
  overflow: hidden;
  margin: 8px 0;
}
.progress-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--accent), var(--accent2));
  transition: width 0.3s;
  border-radius: 999px;
}
'@

Write-File "app/page.js" @'
import Link from "next/link";
import { readDb } from "@/lib/db";

export const dynamic = "force-dynamic";

function timeLeft(deadline) {
 const ms = new Date(deadline) - Date.now();
 if (ms <= 0) return "Closed";
 const d = Math.floor(ms / 86400000);
 const h = Math.floor((ms % 86400000) / 3600000);
 if (d > 0) return `${d}d ${h}h left`;
 const m = Math.floor((ms % 3600000) / 60000);
 return `${h}h ${m}m left`;
}

export default async function Home() {
 const db = await readDb();
 const campaigns = db.campaigns
 .filter((c) => c.published)
 .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

 return (
 <>
 <div className="hero">
 <h1>Live Giveaways</h1>
 <p>Join giveaways, complete tasks, win prizes. Winners drawn transparently.</p>
 </div>

 {campaigns.length === 0 && (
 <div className="empty">No live giveaways yet. Check back later!</div>
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
 {closed ? "Closed" : "Live"}
 </span>
 </div>
 <p className="meta">
 {c.prize} &nbsp;{"\u2022"}&nbsp; {n} qualified &nbsp;{"\u2022"}&nbsp;{" "}
 {timeLeft(c.deadline)}
 </p>
 <p style={{ fontSize: 14, color: "#c4cbe2" }}>
 {c.description?.slice(0, 140)}
 {c.description?.length > 140 ? "..." : ""}
 </p>
 <div className="btn-row">
 <Link href={`/c/${c.id}`} className="btn btn-primary">
 Join Giveaway
 </Link>
 <Link href={`/c/${c.id}/hasil`} className="btn">
 View Results
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

Write-File "app/layout.js" @'
import "./globals.css";

export const metadata = {
 title: "Giveaway Raffle",
 description: "Join transparent giveaways & raffles for NFT projects",
};

export default function RootLayout({ children }) {
 return (
 <html lang="en">
 <head>
 <meta charSet="utf-8" />
 </head>
 <body>
 <div className="container">
 <nav className="nav">
 <a href="/" className="logo">
 Giveaway<span>Raffle</span>
 </a>
 </nav>
 {children}
 <div className="footer">
 Giveaway Raffle - transparent draws with verifiable seed
 </div>
 </div>
 </body>
 </html>
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
 if (!data) return <div className="empty">Giveaway not found</div>;

 const { campaign, draw, winners } = data;

 return (
 <>
 <div className="card">
 <h2>Draw Results - {campaign.title}</h2>
 <p className="meta">Prize: {campaign.prize}</p>
 </div>

 {!draw ? (
 <div className="alert alert-info">
 The draw has not happened yet. Winners will be announced here after the admin runs the draw.
 </div>
 ) : (
 <div className="card">
 <h2>Winners ({winners.length})</h2>
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
 Drawn on: {new Date(draw.createdAt).toLocaleString("en-US")}
 {draw.redraw ? " (redraw)" : ""}
 </p>
 <label className="lbl">Draw seed (verifiable):</label>
 <div className="seed-box">{draw.seed}</div>
 <div className="btn-row">
 <Link href={`/c/${id}`} className="btn">
 {"\u2190"} Back to Giveaway
 </Link>
 </div>
 </div>
 )}
 </>
 );
}
'@

Write-Host ""
Write-Host "Selesai! Lanjut: git add -A; git commit -m \"english ui, no admin button\"; git push"
