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