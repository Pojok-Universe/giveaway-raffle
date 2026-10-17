import crypto from "node:crypto";
import { cookies } from "next/headers";

export const ADMIN_COOKIE = "gr_admin";

function signature() {
  const secret = process.env.ADMIN_PASSWORD || "";
  return crypto
    .createHmac("sha256", secret)
    .update("giveaway-raffle-admin")
    .digest("hex");
}

export function adminCookieValue() {
  return signature();
}

// Dipakai di API route & server component
export async function isAdmin() {
  if (!process.env.ADMIN_PASSWORD) return false;
  const c = cookies().get(ADMIN_COOKIE)?.value;
  if (!c) return false;
  const expected = signature();
  if (c.length !== expected.length) return false;
  return crypto.timingSafeEqual(Buffer.from(c), Buffer.from(expected));
}
