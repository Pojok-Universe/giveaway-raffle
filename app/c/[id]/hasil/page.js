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
