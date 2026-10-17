// DB layer dual-backend:
// - Production (Vercel): pakai Upstash Redis (via Vercel Marketplace integration)
//   — filesystem Vercel read-only, jadi JSON file tidak bisa dipakai.
//   Env var otomatis terisi saat integration di-connect:
//   UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN
//   (fallback: KV_REST_API_URL + KV_REST_API_TOKEN untuk store lama)
// - Local dev: JSON file di data/db.json (tanpa setup apapun).
//
// readDb/writeDb ASYNC — semua pemanggil wajib await.

import fs from "node:fs";
import path from "node:path";

const REDIS_URL = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL || "";
const REDIS_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN || "";
const USE_REDIS = !!(REDIS_URL && REDIS_TOKEN);
const REDIS_KEY = "raffle:db:v1";

const DB_PATH = path.join(process.cwd(), "data", "db.json");

const emptyDb = () => ({ campaigns: [], entries: [], draws: [] });

let redisClient = null;
async function getRedis() {
  if (redisClient) return redisClient;
  const { Redis } = await import("@upstash/redis");
  redisClient = new Redis({ url: REDIS_URL, token: REDIS_TOKEN });
  return redisClient;
}

function ensureLocal() {
  const dir = path.dirname(DB_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  if (!fs.existsSync(DB_PATH)) {
    fs.writeFileSync(DB_PATH, JSON.stringify(emptyDb(), null, 2));
  }
}

export async function readDb() {
  if (USE_REDIS) {
    const redis = await getRedis();
    const db = await redis.get(REDIS_KEY);
    return db || emptyDb();
  }
  ensureLocal();
  try {
    return JSON.parse(fs.readFileSync(DB_PATH, "utf8"));
  } catch {
    return emptyDb();
  }
}

export async function writeDb(db) {
  if (USE_REDIS) {
    const redis = await getRedis();
    await redis.set(REDIS_KEY, db);
    return;
  }
  ensureLocal();
  fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2));
}

// Rate limit sederhana: max N aksi per key per window detik.
// Di Vercel pakai Redis (atomic incr + expire). Lokal: Map in-memory.
const memBuckets = new Map();

export async function hitRateLimit(key, maxHits, windowSecs) {
  const now = Math.floor(Date.now() / 1000);
  if (USE_REDIS) {
    const redis = await getRedis();
    const k = `raffle:rl:${key}`;
    const count = await redis.incr(k);
    if (count === 1) await redis.expire(k, windowSecs);
    const ttl = await redis.ttl(k);
    return { limited: count > maxHits, remaining: Math.max(0, maxHits - count), resetIn: ttl };
  }
  // fallback lokal
  const bucket = Math.floor(now / windowSecs);
  const mk = `${key}:${bucket}`;
  const count = (memBuckets.get(mk) || 0) + 1;
  memBuckets.set(mk, count);
  if (memBuckets.size > 1000) {
    const first = memBuckets.keys().next().value;
    memBuckets.delete(first);
  }
  return { limited: count > maxHits, remaining: Math.max(0, maxHits - count), resetIn: windowSecs - (now % windowSecs) };
}

export function uid(prefix = "id") {
  return (
    prefix +
    "_" +
    Date.now().toString(36) +
    "_" +
    Math.random().toString(36).slice(2, 8)
  );
}
