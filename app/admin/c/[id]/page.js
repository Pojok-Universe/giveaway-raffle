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
 <span className="badge ok" title="Self-declared Done">Done âœ“</span>
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