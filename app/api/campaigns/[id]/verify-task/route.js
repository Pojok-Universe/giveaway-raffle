import { NextResponse } from "next/server";
import { readDb, hitRateLimit } from "@/lib/db";
import { checkEvidenceUrl, tweetContainsCode } from "@/lib/antispam";

function clientIp(request) {
  const fwd = request.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0].trim();
  return request.headers.get("x-real-ip") || "unknown";
}

// POST -> verifikasi satu task (tanpa membuat entry).
// Body: { reqId, xUsername, url }
export async function POST(request, { params }) {
  // Rate limit ringan: 30x per jam per IP per campaign (user boleh retry).
  const rl = await hitRateLimit(`verify:${params.id}:${clientIp(request)}`, 30, 3600);
  if (rl.limited) {
    return NextResponse.json(
      { ok: false, reason: "Terlalu banyak percobaan. Tunggu sebentar." },
      { status: 429 }
    );
  }

  const db = await readDb();
  const c = db.campaigns.find((x) => x.id === params.id && x.published);
  if (!c) return NextResponse.json({ ok: false, reason: "Giveaway tidak ditemukan." }, { status: 404 });
  if (new Date(c.deadline) < new Date()) {
    return NextResponse.json({ ok: false, reason: "Pendaftaran sudah ditutup." }, { status: 400 });
  }

  const body = await request.json();
  const reqId = (body.reqId || "").trim();
  const xUsername = (body.xUsername || "").trim().replace(/^@/, "").toLowerCase();
  const url = (body.url || "").trim();

  if (!reqId || !xUsername || !url) {
    return NextResponse.json({ ok: false, reason: "Data tidak lengkap." }, { status: 400 });
  }
  if (!/^[a-z0-9_]{1,15}$/.test(xUsername)) {
    return NextResponse.json({ ok: false, reason: "Format X username tidak valid." }, { status: 400 });
  }

  const req = (c.requirements || []).find((r) => r.id === reqId);
  if (!req) return NextResponse.json({ ok: false, reason: "Task tidak ditemukan." }, { status: 404 });
  if (req.showDone) {
    return NextResponse.json({ ok: false, reason: "Task ini cukup tandai Done." }, { status: 400 });
  }
  if (req.proofType === "photo") {
    return NextResponse.json({ ok: false, reason: "Task ini memakai bukti foto." }, { status: 400 });
  }

  const check = await checkEvidenceUrl(url, xUsername);
  if (check.status === "invalid") {
    return NextResponse.json({ ok: false, reason: check.reason }, { status: 200 });
  }

  if (c.code) {
    const hasCode = await tweetContainsCode(url, c.code);
    if (hasCode === false) {
      return NextResponse.json(
        { ok: false, reason: `Tweet harus memuat kode "${c.code}".` },
        { status: 200 }
      );
    }
  }

  return NextResponse.json({ ok: true, author: check.author || xUsername });
}