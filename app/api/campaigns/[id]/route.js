import { NextResponse } from "next/server";
import { readDb, writeDb } from "@/lib/db";
import { isAdmin } from "@/lib/auth";

// GET /api/campaigns/[id] → detail campaign (publik; draft hanya admin via ?all=1)
export async function GET(request, { params }) {
  const db = await readDb();
  const c = db.campaigns.find((x) => x.id === params.id);
  if (!c) return NextResponse.json({ error: "Not found" }, { status: 404 });
  if (!c.published) {
    const all = request.nextUrl.searchParams.get("all");
    if (!all || !(await isAdmin())) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
  }
  return NextResponse.json(c);
}

// PATCH /api/campaigns/[id] → update (admin)
export async function PATCH(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = await readDb();
  const c = db.campaigns.find((x) => x.id === params.id);
  if (!c) return NextResponse.json({ error: "Not found" }, { status: 404 });
  const body = await request.json();
  for (const k of ["title", "description", "prize", "deadline", "requirements", "published", "code"]) {
    if (body[k] !== undefined) c[k] = body[k];
  }
  await writeDb(db);
  return NextResponse.json(c);
}

// DELETE /api/campaigns/[id] → hapus + entry & draw terkait (admin)
export async function DELETE(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = await readDb();
  db.campaigns = db.campaigns.filter((x) => x.id !== params.id);
  db.entries = db.entries.filter((x) => x.campaignId !== params.id);
  db.draws = db.draws.filter((x) => x.campaignId !== params.id);
  await writeDb(db);
  return NextResponse.json({ ok: true });
}
