import { NextResponse } from "next/server";
import crypto from "node:crypto";
import { ADMIN_COOKIE, adminCookieValue } from "@/lib/auth";

// POST /api/admin/login → { password }
export async function POST(request) {
  const { password } = await request.json();
  const expected = process.env.ADMIN_PASSWORD || "";
  if (!expected || !password) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const a = Buffer.from(password);
  const b = Buffer.from(expected);
  const ok = a.length === b.length && crypto.timingSafeEqual(a, b);
  if (!ok) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const res = NextResponse.json({ ok: true });
  res.cookies.set(ADMIN_COOKIE, adminCookieValue(), {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7, // 7 hari
  });
  return res;
}
