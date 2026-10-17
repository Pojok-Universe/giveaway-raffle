import { NextResponse } from "next/server";

// Nama cookie disamakan dengan lib/auth.js (ADMIN_COOKIE).
// Sengaja tidak import dari sana karena middleware (edge runtime)
// tidak boleh menarik next/headers.
const ADMIN_COOKIE = "gr_admin";

// Proteksi halaman admin — cek keberadaan cookie.
// Verifikasi signature dilakukan di API route & server component.
export function middleware(request) {
  const { pathname } = request.nextUrl;
  if (pathname.startsWith("/admin") && pathname !== "/admin") {
    const c = request.cookies.get(ADMIN_COOKIE)?.value;
    if (!c) {
      return NextResponse.redirect(new URL("/admin", request.url));
    }
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*"],
};
