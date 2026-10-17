import { NextResponse } from "next/server";
import { supabase as getSupabase, PROOFS_BUCKET, MAX_PHOTO_BYTES, isImageFile } from "@/lib/supabase";
import { uid } from "@/lib/db";

// POST /api/upload -> upload foto bukti ke Supabase Storage.
// Body: multipart/form-data, field "file". Return { url }.
export async function POST(request) {
  const sb = getSupabase();
  if (!sb) {
    return NextResponse.json(
      { error: "Upload belum dikonfigurasi (SUPABASE_URL / SUPABASE_SERVICE_KEY)." },
      { status: 503 }
    );
  }

  let file = null;
  try {
    const form = await request.formData();
    file = form.get("file");
  } catch {
    return NextResponse.json({ error: "Body harus multipart/form-data." }, { status: 400 });
  }

  if (!file || typeof file === "string") {
    return NextResponse.json({ error: "File tidak ditemukan." }, { status: 400 });
  }
  if (!isImageFile(file)) {
    return NextResponse.json({ error: "File harus gambar (jpg/png/webp)." }, { status: 400 });
  }
  if (file.size > MAX_PHOTO_BYTES) {
    return NextResponse.json({ error: "Ukuran foto maksimal 2MB." }, { status: 400 });
  }

  const ext = (file.name || "").split(".").pop()?.toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
  const safeExt = ["jpg", "jpeg", "png", "webp", "gif"].includes(ext) ? ext : "jpg";
  const path = `${uid("proof")}.${safeExt}`;
  const buf = Buffer.from(await file.arrayBuffer());

  const { error } = await sb.storage.from(PROOFS_BUCKET).upload(path, buf, {
    contentType: file.type,
    upsert: false,
  });
  if (error) {
    return NextResponse.json({ error: "Upload gagal: " + error.message }, { status: 500 });
  }

  const { data } = sb.storage.from(PROOFS_BUCKET).getPublicUrl(path);
  return NextResponse.json({ url: data.publicUrl });
}
