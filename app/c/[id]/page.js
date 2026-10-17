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
