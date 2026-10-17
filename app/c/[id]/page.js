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
 const [photoFiles, setPhotoFiles] = useState({});
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

 async function submit(e) {
 e.preventDefault();
 setMsg(null);

 const reqs = campaign.requirements || [];
 const unchecked = reqs.filter((r) => r.showDone && !checks[r.id]);
 if (unchecked.length > 0) {
 setMsg({ type: "error", text: "Klik tombol Done di semua task bertanda Done dulu!" });
 return;
 }
 const noProof = reqs.filter((r) => {
 if (r.proofType === "photo") return !photoFiles[r.id] && !(evidence[r.id] || "").trim();
 return !(evidence[r.id] || "").trim();
 });
 if (noProof.length > 0) {
 setMsg({ type: "error", text: `Isi bukti untuk: ${noProof.map((r) => r.label).join(", ")}` });
 return;
 }
 if (!xUsername.trim() || !wallet.trim()) {
 setMsg({ type: "error", text: "Isi X username dan wallet address!" });
 return;
 }

 // Upload foto dulu, baru submit
 setUploading(true);
 const finalEvidence = { ...evidence };
 try {
 for (const r of reqs) {
 if (r.proofType === "photo" && photoFiles[r.id] && !finalEvidence[r.id]) {
 const fd = new FormData();
 fd.append("file", photoFiles[r.id]);
 const up = await fetch("/api/upload", { method: "POST", body: fd });
 const ud = await up.json();
 if (!up.ok) throw new Error(ud.error || "Upload foto gagal.");
 finalEvidence[r.id] = ud.url;
 }
 }
 } catch (err) {
 setUploading(false);
 setMsg({ type: "error", text: err.message });
 return;
 }
 setUploading(false);

 setSending(true);
 const res = await fetch(`/api/campaigns/${id}/entries`, {
 method: "POST",
 headers: { "Content-Type": "application/json" },
 body: JSON.stringify({
 xUsername: xUsername.trim().replace(/^@/, ""),
 wallet: wallet.trim(),
 evidence: finalEvidence,
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
 setPhotoFiles({});
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
 {campaign.code && (
 <p className="alert alert-info" style={{ marginTop: 8 }}>
 {"\u{1F511}"} Cantumkan kode <b>{campaign.code}</b> di tweet bukti kamu.
 </p>
 )}
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
 <div className="req-body" style={{ width: "100%" }}>
 <b>{r.label}</b>
 {r.proofType === "photo" && <span className="badge" style={{ marginLeft: 8 }}>{"\u{1F4F7}"} foto</span>}
 {r.url && (
 <a href={r.url} target="_blank" rel="noreferrer" className="btn" style={{ fontSize: 12, padding: "6px 12px", marginLeft: 8 }}>
 Buka {"\u2197"}
 </a>
 )}
 <div style={{ marginTop: 8 }}>
 {r.proofType === "photo" ? (
 <>
 <input
 type="file"
 accept="image/*"
 className="input"
 onChange={(e) => setPhotoFiles({ ...photoFiles, [r.id]: e.target.files?.[0] || null })}
 />
 {photoFiles[r.id] && (
 <p className="small" style={{ marginTop: 4 }}>{"\u{1F4CE}"} {photoFiles[r.id].name}</p>
 )}
 </>
 ) : (
 <input
 className="input"
 placeholder="Link bukti (wajib) - cth: https://x.com/username/status/..."
 value={evidence[r.id] || ""}
 onChange={(e) => setEvidence({ ...evidence, [r.id]: e.target.value })}
 />
 )}
 </div>
 {r.showDone && (
 <>
 <button
 type="button"
 className={`btn ${checks[r.id] ? "btn-success" : ""}`}
 style={{ marginTop: 8, width: "100%" }}
 onClick={() => setChecks({ ...checks, [r.id]: !checks[r.id] })}
 >
 {checks[r.id] ? "\u2705 Done — sudah dikerjakan" : "Tandai sebagai Done"}
 </button>
 <p className="small" style={{ marginTop: 4, color: "#888" }}>
 Klik tombol di atas setelah kamu selesai mengerjakan task ini.
 </p>
 </>
 )}
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
 <button className="btn btn-success" disabled={sending || uploading}>
 {uploading ? "Mengupload foto..." : sending ? "Mengirim..." : "Kirim Entry \u{1F680}"}
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
