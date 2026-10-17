// Anti-spam bukti task - tanpa X API berbayar.
// Verifikasi memakai oEmbed publik X (tidak butuh API key).
// Prinsip: bot menandai (flag), admin yang memutuskan diskualifikasi.

const X_DOMAINS = new Set([
  "x.com",
  "www.x.com",
  "twitter.com",
  "www.twitter.com",
  "mobile.twitter.com",
]);

export function isXUrl(url) {
  try {
    const u = new URL(url);
    return X_DOMAINS.has(u.hostname.toLowerCase());
  } catch {
    return false;
  }
}

export function extractStatusId(url) {
  const m = String(url).match(/(?:x\.com|twitter\.com)\/\w+\/status\/(\d+)/i);
  return m ? m[1] : null;
}

// Cek satu URL bukti. Return { status, author, reason }.
// status: "valid" | "invalid" | "unchecked"
export async function checkEvidenceUrl(url, xUsername) {
  const u = (url || "").trim();
  if (!u) return { status: "invalid", reason: "bukti kosong" };
  if (!/^https?:\/\//i.test(u))
    return { status: "invalid", reason: "bukan URL valid" };
  if (!isXUrl(u)) return { status: "invalid", reason: "bukan link X/Twitter" };

  const statusId = extractStatusId(u);
  if (!statusId) {
    // Link profil dsb: tidak bisa dicek otomatis -> netral
    return { status: "unchecked", reason: "tipe link tidak bisa dicek otomatis" };
  }

  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 6000);
    const r = await fetch(
      "https://publish.x.com/oembed?url=" +
        encodeURIComponent("https://x.com/i/status/" + statusId),
      { signal: ctrl.signal }
    );
    clearTimeout(t);
    if (r.status === 404)
      return { status: "invalid", reason: "tweet tidak ditemukan / link salah" };
    if (!r.ok)
      return { status: "unchecked", reason: "X tidak merespons saat dicek" };
    const j = await r.json();
    const am = String(j.author_url || "").match(
      /(?:x\.com|twitter\.com)\/(\w+)/i
    );
    const author = am ? am[1].toLowerCase() : null;
    if (author && xUsername && author !== String(xUsername).toLowerCase()) {
      return {
        status: "invalid",
        author,
        reason: "tweet milik @" + author + ", bukan @" + xUsername,
      };
    }
    return { status: "valid", author, reason: "tweet valid" };
  } catch {
    return { status: "unchecked", reason: "gagal menghubungi X" };
  }
}

// Cek apakah tweet berisi kode campaign (case-insensitive).
// Return true / false / "unchecked" (oEmbed gagal atau bukan link status).
export async function tweetContainsCode(url, code) {
  if (!code) return true;
  const statusId = extractStatusId(url);
  if (!statusId) return "unchecked";
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 6000);
    const r = await fetch(
      "https://publish.x.com/oembed?url=" +
        encodeURIComponent("https://x.com/i/status/" + statusId),
      { signal: ctrl.signal }
    );
    clearTimeout(t);
    if (!r.ok) return "unchecked";
    const j = await r.json();
    const text = String(j.html || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"');
    return text.toLowerCase().includes(String(code).toLowerCase());
  } catch {
    return "unchecked";
  }
}

// Nilai satu entry -> { flags: [string], clean: bool }.
// entries = semua entry campaign (untuk deteksi bukti duplikat).
export function scoreEntry(entry, campaign, entries) {
  const flags = [];
  const reqs = (campaign && campaign.requirements) || [];
  const ev = entry.evidence || {};
  const chk = entry.evidenceCheck || {};

  for (const r of reqs) {
    const url = (ev[r.id] || "").trim();
    if (!url) {
      flags.push("bukti kosong: " + r.label);
      continue;
    }
    const c = chk[r.id];
    if (c && c.status === "invalid") {
      flags.push("bukti bermasalah (" + r.label + "): " + c.reason);
    }
  }

  // Bukti yang sama dipakai entry lain = indikasi kuat curang
  const urls = Object.values(ev)
    .map((s) => (s || "").trim().toLowerCase())
    .filter(Boolean);
  if (urls.length > 0) {
    for (const other of entries || []) {
      if (other.id === entry.id) continue;
      if (other.campaignId !== entry.campaignId) continue;
      const oUrls = Object.values(other.evidence || {}).map((s) =>
        (s || "").trim().toLowerCase()
      );
      if (urls.some((u) => oUrls.includes(u))) {
        flags.push("link bukti dipakai juga oleh @" + other.xUsername);
        break;
      }
    }
  }

  return { flags, clean: flags.length === 0 };
}
