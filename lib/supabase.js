// Supabase client (server-side). Butuh env:
//   SUPABASE_URL, SUPABASE_SERVICE_KEY
// Bucket: "proofs" (public)

import { createClient } from "@supabase/supabase-js";

let client = null;

export function supabase() {
  if (client) return client;
  const url = process.env.SUPABASE_URL || "";
  const key = process.env.SUPABASE_SERVICE_KEY || "";
  if (!url || !key) return null;
  client = createClient(url, key, { auth: { persistSession: false } });
  return client;
}

export const PROOFS_BUCKET = "proofs";
export const MAX_PHOTO_BYTES = 2 * 1024 * 1024; // 2MB

export function isImageFile(file) {
  return file && typeof file.type === "string" && file.type.startsWith("image/");
}
