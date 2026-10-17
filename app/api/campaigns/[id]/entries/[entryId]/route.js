import { NextResponse } from "next/server";
import { readDb, writeDb } from "@/lib/db";
import { isAdmin } from "@/lib/auth";

// PATCH → approve / reject entry (admin)
export async function PATCH(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const { status } = await request.json();
  if (!["pending", "approved", "rejected"].includes(status)) {
    return NextResponse.json({ error: "Status tidak valid." }, { status: 400 });
  }
  const db = await readDb();
  const e = db.entries.find(
    (x) => x.id === params.entryId && x.campaignId === params.id
  );
  if (!e) return NextResponse.json({ error: "Entry tidak ditemukan." }, { status: 404 });
  e.status = status;
  await writeDb(db);
  return NextResponse.json(e);
}
