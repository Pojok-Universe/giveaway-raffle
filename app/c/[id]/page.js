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

 // Verifikasi task terikat ke username â€” ganti username = reset verifikasi link.
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
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: "Isi X username dulu di atas." } });
 return;
 }
 if (!url) {
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: "Paste link postingan kamu dulu." } });
 return;
 }
 setTaskState({ ...taskState, [r.id]: { state: "busy", msg: "Memverifikasi..." } });
 try {
 const res = await fetch(`/api/campaigns/${id}/verify-task`, {
 method: "POST",
 headers: { "Content-Type": "application/json" },
 body: JSON.stringify({ reqId: r.id, xUsername: user, url }),
 });
 const data = await res.json();
 if (data.ok) {
 setTaskState({ ...taskState, [r.id]: { state: "ok", msg: "Terverifikasi âœ“", url } });
 } else {
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: data.reason || "Verifikasi gagal." } });
 }
 } catch {
 setTaskState({ ...taskState, [r.id]: { state: "err", msg: "Gagal menghubungi server." } });
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
 setMsg({ type: "error", text: "Isi X username dan wallet address!" });
 return;
 }
 const notDone = reqs.filter((r) => !isTaskDone(r));
 if (notDone.length > 0) {
 setMsg({ type: "error", text: `Selesaikan dulu: ${notDone.map((r) => r.label).join(", ")}` });
 return;
 }

 // Upload foto dulu (task photo â€” dormant)
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
 setMsg({ type: "ok", text: "Entry terkirim! Tunggu verifikasi admin. Good luck!" });
 setXUsername("");
 setWallet("");
 setDoneMap({});
 setTaskState({});
 setTaskUrl({});
 setPhotoFiles({});
 setExpandedTask(null);
 setOpenedMap({});
 } else {
 setMsg({ type: "error", text: data.error || "Gagal mengirim entry." });
 }
 }

 if (loading) return <div className="empty">Loading...</div>;
 if (!campaign) return <div className="empty">Giveaway tidak ditemukan </div>;

 const closed = new Date(campaign.deadline) < new Date();

 function statusBadge(r) {
 if (isTaskDone(r)) return <span className="badge ok">OK âœ“</span>;
 const st = taskState[r.id]?.state;
 if (st === "busy") return <span className="badge na">...</span>;
 if (st === "err") return <span className="badge flag">Gagal</span>;
 return <span className="badge na">Todo</span>;
 }

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
 Hadiah: {campaign.prize} &nbsp;â€¢&nbsp; Deadline:{" "}
 {new Date(campaign.deadline).toLocaleString("id-ID")}
 </p>
 {campaign.code && (
 <p className="alert alert-info" style={{ marginTop: 8 }}>
 Kode campaign: <b>{campaign.code}</b> â€” wajib ada di tweet bukti kamu.
 </p>
 )}
 <p style={{ fontSize: 14, whiteSpace: "pre-wrap" }}>{campaign.description}</p>
 </div>

 {closed ? (
 <div className="alert alert-info">
 Pendaftaran sudah ditutup.{" "}
 <Link href={`/c/${id}/hasil`}>Lihat hasil undian â†’</Link>
 </div>
 ) : (
 <div className="card">
 <h2>Form Pendaftaran</h2>

 <label className="lbl">X Username (tanpa @) â€” isi dulu sebelum verifikasi task</label>
 <input
 className="input"
 placeholder="cth: agunverse"
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

 <label className="lbl">Selesaikan task berikut (klik tiap task untuk mengerjakan):</label>
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
 <span className="small">{expanded ? "â–²" : "â–¼"}</span>
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
 Buka â†—
 </a>
 )}

 {r.showDone && (openedMap[r.id] || !r.url) && (
 <button
 type="button"
 className={`btn ${done ? "btn-success" : ""}`}
 style={{ marginTop: 8, width: "100%" }}
 onClick={() => setDoneMap({ ...doneMap, [r.id]: !doneMap[r.id] })}
 >
 {done ? "Done â€” sudah dikerjakan" : "Saya sudah kerjakan"}
 </button>
 )}
 {r.showDone && !openedMap[r.id] && r.url && !done && (
 <p className="small" style={{ marginTop: 8 }}>
 Klik "Buka" di atas dulu dan kerjakan task-nya â€” tombol Done muncul setelah itu.
 </p>
 )}

 {!r.showDone && r.proofType !== "photo" && (
 <div style={{ marginTop: 8 }}>
 {campaign.code && (
 <div className="payload-box">
 <span className="small">PAYLOAD</span>
 <code style={{ flex: 1, wordBreak: "break-all" }}>{campaign.code}</code>
 <button type="button" className="btn" style={{ fontSize: 12, padding: "4px 10px" }} onClick={copyPayload}>
 {copied ? "Copied âœ“" : "Copy"}
 </button>
 </div>
 )}
 <p className="small" style={{ marginBottom: 6 }}>
 {campaign.code
 ? "Sertakan kode di atas di reply kamu, lalu paste link-nya:"
 : "Paste link reply kamu:"}
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
 <span className="small"><b>{doneCount}/{reqs.length}</b> task selesai</span>
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
 {uploading ? "Mengupload foto..." : sending ? "Mengirim..." : allDone ? "Kirim Entry" : `Selesaikan ${reqs.length - doneCount} task dulu`}
 </button>
 </div>
 </form>
 <p className="small mt">
 1 akun X = 1 entry. Wallet / username duplikat otomatis ditolak. Task reply/quote dicek otomatis saat kamu tekan Verify Post.
 </p>
 </div>
 )}
 </>
 );
}