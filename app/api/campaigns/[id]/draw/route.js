import { NextResponse } from "next/server";
import { readDb, writeDb, uid } from "@/lib/db";
import { isAdmin } from "@/lib/auth";
import { drawWinners, newSeed } from "@/lib/raffle";

// GET → hasil undian terbaru + data pemenang (publik)
export async function GET(request, { params }) {
  const db = await readDb();
  const campaign = db.campaigns.find((x) => x.id === params.id);
  if (!campaign) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const draws = db.draws
    .filter((d) => d.campaignId === params.id)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  const draw = draws[0] || null;
  const winners = draw
    ? draw.winnerIds
        .map((wid) => db.entries.find((e) => e.id === wid))
        .filter(Boolean)
    : [];

  return NextResponse.json({ campaign, draw, winners });
}

// POST → jalankan undian (admin). Body: { count }
export async function POST(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = await readDb();
  const campaign = db.campaigns.find((x) => x.id === params.id);
  if (!campaign) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const { count } = await request.json();
  const n = Math.max(1, Number(count) || 1);
  const pool = db.entries.filter(
    (e) => e.campaignId === params.id && e.status === "approved"
  );
  if (pool.length < n) {
    return NextResponse.json(
      { error: `Entry approved (${pool.length}) kurang dari jumlah pemenang (${n}).` },
      { status: 400 }
    );
  }

  const seed = newSeed();
  const winnerIds = drawWinners(pool.map((e) => e.id), n, seed);
  const hadDraw = db.draws.some((d) => d.campaignId === params.id);

  // Hapus draw lama campaign ini (redraw menggantikan)
  db.draws = db.draws.filter((d) => d.campaignId !== params.id);
  const draw = {
    id: uid("drw"),
    campaignId: params.id,
    winnerIds,
    seed,
    count: n,
    redraw: hadDraw,
    createdAt: new Date().toISOString(),
  };
  db.draws.push(draw);
  await writeDb(db);

  const winners = winnerIds.map((wid) => db.entries.find((e) => e.id === wid));
  return NextResponse.json({ draw, winners });
}
