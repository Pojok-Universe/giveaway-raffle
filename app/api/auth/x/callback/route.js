import { NextResponse } from "next/server";
import { xConfig, signXUser, X_COOKIE, X_STATE_COOKIE } from "@/lib/xauth";

// GET /api/auth/x/callback?code=...&state=... -> tukar kode, buat sesi
export async function GET(request) {
  const appUrl = (process.env.APP_URL || "").replace(/\/$/, "");
  const fail = (msg) =>
    NextResponse.redirect(
      (appUrl || "/") + "/?xerror=" + encodeURIComponent(msg)
    );

  let cfg;
  try {
    cfg = xConfig();
  } catch (e) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }

  const q = request.nextUrl.searchParams;
  if (q.get("error")) return fail("Login X dibatalkan.");

  const code = q.get("code");
  const state = q.get("state");
  const raw = request.cookies.get(X_STATE_COOKIE)?.value;
  if (!raw || !code || !state) return fail("Sesi login kadaluarsa, coba lagi.");

  let saved;
  try {
    saved = JSON.parse(Buffer.from(raw, "base64").toString("utf8"));
  } catch {
    return fail("Sesi login rusak, coba lagi.");
  }
  if (!saved || saved.state !== state || !saved.verifier)
    return fail("State tidak cocok, coba lagi.");

  // tukar authorization code -> access token
  const body = new URLSearchParams({
    code,
    grant_type: "authorization_code",
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    code_verifier: saved.verifier,
  });
  const headers = { "Content-Type": "application/x-www-form-urlencoded" };
  if (cfg.clientSecret) {
    headers["Authorization"] =
      "Basic " +
      Buffer.from(cfg.clientId + ":" + cfg.clientSecret).toString("base64");
  }
  let tok;
  try {
    const r = await fetch("https://api.twitter.com/2/oauth2/token", {
      method: "POST",
      headers,
      body,
    });
    if (!r.ok) return fail("Gagal tukar kode X.");
    tok = await r.json();
  } catch {
    return fail("Tidak bisa hubungi X, coba lagi.");
  }
  if (!tok.access_token) return fail("Token X tidak diterima.");

  // ambil profil (cukup sekali, lalu buat sesi sendiri)
  let xu;
  try {
    const r = await fetch("https://api.twitter.com/2/users/me", {
      headers: { Authorization: "Bearer " + tok.access_token },
    });
    if (!r.ok) return fail("Gagal baca profil X.");
    const j = await r.json();
    xu = j && j.data;
  } catch {
    return fail("Tidak bisa baca profil X, coba lagi.");
  }
  if (!xu || !xu.id || !xu.username) return fail("Profil X tidak lengkap.");

  const res = NextResponse.redirect(appUrl + saved.returnTo);
  res.cookies.set(X_COOKIE, signXUser(xu.id, xu.username), {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 30, // 30 hari
  });
  res.cookies.delete(X_STATE_COOKIE);
  return res;
}
