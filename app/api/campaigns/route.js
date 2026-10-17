import { NextResponse } from "next/server";
import { readDb, writeDb, uid } from "@/lib/db";
import { isAdmin } from "@/lib/auth";

// GET /api/campaigns → publik (published saja); ?all=1 → admin (semua)
export async function GET(request) {
  const db = await readDb();
  const all = request.nextUrl.searchParams.get("all");
  if (all) {
    if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    return NextResponse.json(db.campaigns);
  }
  return NextResponse.json(db.campaigns.filter((c) => c.published));
}

// POST /api/campaigns → buat campaign (admin)
export async function POST(request) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const body = await request.json();
  if (!body.title || !body.prize || !body.deadline) {
    return NextResponse.json({ error: "title, prize, deadline wajib diisi." }, { status: 400 });
  }
  const db = await readDb();
  const campaign = {
    id: uid("cmp"),
    title: body.title,
    description: body.description || "",
    prize: body.prize,
    deadline: body.deadline,
    requirements: Array.isArray(body.requirements) ? body.requirements : [],
    code: (body.code || "").trim() || null, // kode unik yg wajib ada di tweet bukti
    published: true,
    createdAt: new Date().toISOString(),
  };
  db.campaigns.push(campaign);
  await writeDb(db);
  return NextResponse.json(campaign, { status: 201 });
}
