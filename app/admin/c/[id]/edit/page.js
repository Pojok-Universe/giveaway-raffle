"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";

function reqToLine(r) {
 const parts = [r.label || "", r.url || ""];
 if (r.proofType === "photo") parts.push("photo");
 if (r.showDone) parts.push("done");
 return parts.join(" | ");
}

function toLocalInput(iso) {
 const d = new Date(iso);
 const p = (n) => String(n).padStart(2, "0");
 return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

export default function EditCampaign() {
 const { id } = useParams();
 const router = useRouter();
 const [loading, setLoading] = useState(true);
 const [existingIds, setExistingIds] = useState([]);
 const [hasEntries, setHasEntries] = useState(false);
 const [form, setForm] = useState({ title: "", description: "", prize: "", deadline: "", requirements: "", code: "" });
 const [msg, setMsg] = useState(null);
 const [saving, setSaving] = useState(false);

 useEffect(() => {
 Promise.all([
 fetch(`/api/campaigns/${id}?all=1`).then((r) => {
 if (r.status === 401) {
 router.push("/admin");
 return null;
 }
 return r.ok ? r.json() : null;
 }),
 fetch(`/api/campaigns/${id}/entries`).then((r) => (r.ok ? r.json() : [])),
 ]).then(([c, e]) => {
 if (c) {
 setExistingIds((c.requirements || []).map((r) => r.id));
 setHasEntries((e || []).length > 0);
 setForm({
 title: c.title || "",
 description: c.description || "",
 prize: c.prize || "",
 deadline: c.deadline ? toLocalInput(c.deadline) : "",
 requirements: (c.requirements || []).map(reqToLine).join("\n"),
 code: c.code || "",
 });
 }
 setLoading(false);
 });
 }, [id, router]);

 async function save(e) {
 e.preventDefault();
 setMsg(null);
 setSaving(true);
 const requirements = form.requirements
 .split("\n")
 .map((s) => s.trim())
 .filter(Boolean)
 .map((line, i) => {
 const [label, url, ...rest] = line.split("|").map((s) => s.trim());
 const proofType = rest.some((s) => /^(photo|foto|img|image)$/i.test(s)) ? "photo" : "link";
 const showDone = rest.some((s) => /^(done|declare|check|cek)$/i.test(s));
 return { id: existingIds[i] || `req_${Date.now()}_${i}`, label, url: url || "", proofType, showDone };
 });
 const res = await fetch(`/api/campaigns/${id}`, {
 method: "PATCH",
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
 setSaving(false);
 if (res.ok) {
 setMsg({ type: "ok", text: "Campaign diperbarui! 🎉" });
 } else {
 const d = await res.json().catch(() => ({}));
 setMsg({ type: "error", text: d.error || "Gagal menyimpan." });
 }
 }

 if (loading) return <div className="empty">Loading...</div>;

 return (
 <>
 <Link href={`/admin/c/${id}`} className="btn">{"\u2190"} Kembali</Link>
 <div className="card">
 <h2>{"\u270F\uFE0F"} Edit Giveaway</h2>
 {hasEntries && (
 <div className="alert alert-error">
 Sudah ada peserta — tambah task baru di baris paling bawah saja, jangan ubah urutan/hapus baris yang ada.
 </div>
 )}
 <form onSubmit={save}>
 <label className="lbl">Judul</label>
 <input className="input" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} required />
 <label className="lbl">Deskripsi</label>
 <textarea className="textarea" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
 <label className="lbl">Hadiah</label>
 <input className="input" value={form.prize} onChange={(e) => setForm({ ...form, prize: e.target.value })} required />
 <label className="lbl">Deadline</label>
 <input type="datetime-local" className="input" value={form.deadline} onChange={(e) => setForm({ ...form, deadline: e.target.value })} required />
 <label className="lbl">Task (1 baris = 1 task, format: Label | link | photo? | done?)</label>
 <textarea className="textarea" rows="6" value={form.requirements} onChange={(e) => setForm({ ...form, requirements: e.target.value })} />
 <p className="small">Tambah <b>done</b> = tampil tombol Done (buat task follow/like). Tambah <b>photo</b> = bukti berupa foto.</p>
 <label className="lbl">Kode campaign</label>
 <input className="input" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} placeholder="cth: GLOOMYXAGUN" />
 {msg && <div className={`alert alert-${msg.type === "ok" ? "ok" : "error"}`}>{msg.text}</div>}
 <div className="btn-row">
 <button className="btn btn-primary" disabled={saving}>{saving ? "Menyimpan..." : "Simpan Perubahan"}</button>
 <Link href={`/admin/c/${id}`} className="btn">Batal</Link>
 </div>
 </form>
 </div>
 </>
 );
}