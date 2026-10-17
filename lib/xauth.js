import crypto from "node:crypto";
import { cookies } from "next/headers";

export const X_COOKIE = "gr_xuser";
export const X_STATE_COOKIE = "gr_xstate";

function secret() {
  return process.env.ADMIN_PASSWORD || "";
}

function b64url(buf) {
  return Buffer.from(buf)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

export function newState() {
  return b64url(crypto.randomBytes(16));
}

// PKCE code_verifier: 64 char dari set yang diizinkan
export function newVerifier() {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
  const r = crypto.randomBytes(64);
  let s = "";
  for (let i = 0; i < 64; i++) s += chars[r[i] % chars.length];
  return s;
}

export function codeChallenge(verifier) {
  return b64url(crypto.createHash("sha256").update(verifier).digest());
}

export function xConfig() {
  const clientId = process.env.X_CLIENT_ID || "";
  const clientSecret = process.env.X_CLIENT_SECRET || "";
  const appUrl = (process.env.APP_URL || "").replace(/\/$/, "");
  if (!clientId) throw new Error("X_CLIENT_ID belum diset di .env.local");
  if (!appUrl) throw new Error("APP_URL belum diset di .env.local");
  return {
    clientId,
    clientSecret,
    appUrl,
    redirectUri: appUrl + "/api/auth/x/callback",
  };
}

// Session milik kita sendiri (tidak menyimpan token X)
export function signXUser(id, username) {
  const data = `${id}.${username}`;
  const sig = crypto
    .createHmac("sha256", secret())
    .update("xuser:" + data)
    .digest("hex");
  return `${data}.${sig}`;
}

export async function getXUser() {
  if (!secret()) return null;
  const c = cookies().get(X_COOKIE)?.value;
  if (!c) return null;
  const parts = c.split(".");
  if (parts.length !== 3) return null;
  const [id, username, sig] = parts;
  if (!id || !username || !sig) return null;
  const expect = crypto
    .createHmac("sha256", secret())
    .update(`xuser:${id}.${username}`)
    .digest("hex");
  if (sig.length !== expect.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expect)))
    return null;
  return { id, username };
}
