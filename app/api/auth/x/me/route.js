import { NextResponse } from "next/server";
import { getXUser } from "@/lib/xauth";

// GET /api/auth/x/me -> user X yang sedang login (atau 401)
export async function GET() {
  const u = await getXUser();
  if (!u) return NextResponse.json({ error: "Not logged in" }, { status: 401 });
  return NextResponse.json({ user: u });
}
