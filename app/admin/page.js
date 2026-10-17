"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function AdminLogin() {
 const router = useRouter();
 const [password, setPassword] = useState("");
 const [error, setError] = useState("");
 const [sending, setSending] = useState(false);

 async function submit(e) {
 e.preventDefault();
 setError("");
 setSending(true);
 const res = await fetch("/api/admin/login", {
 method: "POST",
 headers: { "Content-Type": "application/json" },
 body: JSON.stringify({ password }),
 });
 setSending(false);
 if (res.ok) {
 router.push("/admin/dashboard");
 } else {
 setError("Password salah!");
 }
 }

 return (
 <div className="card" style={{ maxWidth: 420, margin: "40px auto" }}>
 <h2>{"\u{1F510}"} Admin Login</h2>
 <form onSubmit={submit}>
 <label className="lbl">Password Admin</label>
 <input
 type="password"
 className="input"
 value={password}
 onChange={(e) => setPassword(e.target.value)}
 placeholder="Masukkan password admin"
 />
 {error && <div className="alert alert-error">{error}</div>}
 <div className="btn-row">
 <button className="btn btn-primary" disabled={sending}>
 {sending ? "Masuk..." : "Masuk"}
 </button>
 </div>
 </form>
 </div>
 );
}
