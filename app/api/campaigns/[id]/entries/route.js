import { NextResponse } from "next/server";
import { readDb, writeDb, uid, hitRateLimit } from "@/lib/db";
import { isAdmin } from "@/lib/auth";
import { checkEvidenceUrl, tweetContainsCode } from "@/lib/antispam";

// Ambil IP client (hormati proxy/CDN)
function clientIp(request) {
  const fwd = request.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0].trim();
  return request.headers.get("x-real-ip") || "unknown";
}

// GET -> daftar entry (admin)
export async function GET(request, { params }) {
  if (!(await isAdmin())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const db = await readDb();
  return NextResponse.json(
    db.entries
      .filter((e) => e.campaignId === params.id)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
  );
}

// POST -> submit entry (publik)
export async function POST(request, { params }) {
  const db = await readDb();
  const c = db.campaigns.find((x) => x.id === params.id && x.published);
  if (!c) return NextResponse.json({ error: "Giveaway tidak ditemukan." }, { status: 404 });
  if (new Date(c.deadline) < new Date()) {
    return NextResponse.json({ error: "Pendaftaran sudah ditutup." }, { status: 400 });
  }

  // Rate limit: maks 1 submit per IP per campaign per 24 jam
  const rl = await hitRateLimit(`entry:${params.id}:${clientIp(request)}`, 1, 86400);
  if (rl.limited) {
    return NextResponse.json(
      { error: "Terlalu banyak pendaftaran dari jaringan ini. Coba lagi nanti." },
      { status: 429 }
    );
  }

  const body = await request.json();
  const xUsername = (body.xUsername || "").trim().replace(/^@/, "").toLowerCase();
  const wallet = (body.wallet || "").trim().toLowerCase();

  if (!xUsername || !wallet) {
    return NextResponse.json({ error: "X username dan wallet wajib diisi." }, { status: 400 });
  }
  if (!/^0x[a-f0-9]{40}$/.test(wallet)) {
    return NextResponse.json({ error: "Format wallet address tidak valid." }, { status: 400 });
  }
  if (!/^[a-z0-9_]{1,15}$/.test(xUsername)) {
    return NextResponse.json({ error: "Format X username tidak valid." }, { status: 400 });
  }

  // Bukti wajib untuk task yang bisa diverifikasi.
  // - Task link (reply/quote): cek otomatis via oEmbed X
  // - Task photo: URL dari Supabase Storage, skip oEmbed -> review manual
  // - Task showDone (follow/like): self-declared, tanpa bukti link
  const reqs = c.requirements || [];
  const evidence = body.evidence || {};
  for (const r of reqs) {
    if (r.showDone) continue;
    if (!(evidence[r.id] || "").trim()) {
      return NextResponse.json({ error: `Bukti untuk "${r.label}" wajib diisi.` }, { status: 400 });
    }
    if (r.proofType === "photo") {
      const u = (evidence[r.id] || "").trim();
      if (!/^https?:\/\//i.test(u)) {
        return NextResponse.json({ error: `Bukti foto "${r.label}" tidak valid. Upload ulang.` }, { status: 400 });
      }
    }
  }
  const evidenceCheck = {};
  await Promise.all(
    reqs.map(async (r) => {
      if (r.showDone) {
        evidenceCheck[r.id] = { status: "unchecked", reason: "self-declared (Done)" };
        return;
      }
      if (r.proofType === "photo") {
        evidenceCheck[r.id] = { status: "manual", reason: "foto — perlu review manual" };
        return;
      }
      evidenceCheck[r.id] = await checkEvidenceUrl(evidence[r.id], xUsername);
    })
  );
  const badProof = reqs.find((r) => evidenceCheck[r.id] && evidenceCheck[r.id].status === "invalid");
  if (badProof) {
    return NextResponse.json(
      { error: `Bukti "${badProof.label}" bermasalah: ${evidenceCheck[badProof.id].reason}` },
      { status: 400 }
    );
  }

  // Kode campaign: minimal 1 bukti tweet harus memuat kode (anti copas link asal)
  if (c.code) {
    const urls = reqs.map((r) => (evidence[r.id] || "").trim()).filter(Boolean);
    let codeFound = false;
    let codeCheckable = false;
    for (const u of urls) {
      const res = await tweetContainsCode(u, c.code);
      if (res === true) { codeFound = true; break; }
      if (res !== "unchecked") codeCheckable = true;
    }
    if (!codeFound && codeCheckable) {
      return NextResponse.json(
        { error: `Bukti tweet harus memuat kode "${c.code}".` },
        { status: 400 }
      );
    }
  }

  // Anti-duplikat: 1 wallet / 1 username per campaign
  const dupe = db.entries.find(
    (e) =>
      e.campaignId === params.id &&
      (e.wallet.toLowerCase() === wallet || e.xUsername.toLowerCase() === xUsername)
  );
  if (dupe) {
    return NextResponse.json({ error: "Wallet / X username ini sudah terdaftar." }, { status: 409 });
  }

  const entry = {
    id: uid("ent"),
    campaignId: params.id,
    xUsername,
    wallet: body.wallet.trim(),
    evidence,
    evidenceCheck,
    status: "pending",
    createdAt: new Date().toISOString(),
  };
  db.entries.push(entry);
  await writeDb(db);
  return NextResponse.json(entry, { status: 201 });
}