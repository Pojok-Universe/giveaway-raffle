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
 code: "",
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
 const [label, url, ...rest] = line.split("|").map((s) => s.trim());
 const proofType = rest.some((s) => /^(photo|foto|img|image)$/i.test(s)) ? "photo" : "link";
 const showDone = rest.some((s) => /^(done|declare|check|cek)$/i.test(s));
 return { id: `req_${Date.now()}_${i}`, label, url: url || "", proofType, showDone };
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
 code: form.code.trim() || null,
 }),
 });
 if (res.ok) {
 setMsg({ type: "ok", text: "Campaign dibuat! \u{1F389}" });
 setForm({ title: "", description: "", prize: "", deadline: "", requirements: "", code: "" });
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
 <label className="lbl">Task (1 baris = 1 task, format: Label | link | photo? | done?)</label>
 <textarea
 className="textarea"
 value={form.requirements}
 onChange={(e) => setForm({ ...form, requirements: e.target.value })}
 placeholder={"Follow X @proyek | https://x.com/proyek | done\nScreenshot bukti follow | | photo\nReply postingan (wajib kode) | https://x.com/..."}
 />
 <p className="small">Tambah <b>done</b> = tampil tombol Done (buat task follow/like). Tambah <b>photo</b> = bukti berupa foto.</p>
 <label className="lbl">Kode campaign (opsional — wajib dicantumkan di tweet bukti)</label>
 <input className="input" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} placeholder="cth: CLOAKEDXAGUN" />
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
 <Link href={`/admin/c/${c.id}/edit`} className="btn">Edit</Link>
 <Link href={`/c/${c.id}`} className="btn">Lihat Publik</Link>
 <button className="btn btn-danger" onClick={() => remove(c.id)}>Hapus</button>
 </div>
 </div>
 ))}
 </>
 );
}
