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