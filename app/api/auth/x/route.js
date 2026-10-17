import { NextResponse } from "next/server";
import {
  xConfig,
  newState,
  newVerifier,
  codeChallenge,
  X_STATE_COOKIE,
} from "@/lib/xauth";

// GET /api/auth/x?return_to=/c/xxx -> mulai login X (redirect ke twitter.com)
export async function GET(request) {
  let cfg;
  try {
    cfg = xConfig();
  } catch (e) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }

  const asked = request.nextUrl.searchParams.get("return_to") || "/";
  const returnTo =
    asked.startsWith("/") && !asked.startsWith("//") ? asked : "/";

  const state = newState();
  const verifier = newVerifier();
  const params = new URLSearchParams({
    response_type: "code",
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    scope: "users.read tweet.read",
    state,
    code_challenge: codeChallenge(verifier),
    code_challenge_method: "S256",
  });

  const res = NextResponse.redirect(
    "https://twitter.com/i/oauth2/authorize?" + params.toString()
  );
  const payload = Buffer.from(
    JSON.stringify({ state, verifier, returnTo })
  ).toString("base64");
  res.cookies.set(X_STATE_COOKIE, payload, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 600, // 10 menit
  });
  return res;
}
