import { NextResponse } from "next/server";
import { X_COOKIE } from "@/lib/xauth";

// POST /api/auth/x/logout (GET juga diterima untuk link sederhana)
export async function logout() {
  const res = NextResponse.json({ ok: true });
  res.cookies.delete(X_COOKIE);
  return res;
}

export const POST = logout;
export const GET = logout;
