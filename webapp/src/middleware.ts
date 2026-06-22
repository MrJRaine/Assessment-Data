// Auth.js (NextAuth v5) middleware. Runs the `authorized` callback in src/auth.ts for the
// matched routes: an unauthenticated request to a protected page is redirected to the sign-in
// page (pages.signIn = '/login'), which bounces straight to Entra — so clicking any functional
// link signs the user in rather than throwing an access error. Dev mode bypasses (see authorized()).
export { auth as middleware } from '@/auth'

export const config = {
  // Protect the functional routes that read live Fabric data (all call getCurrentUpn()).
  // The landing page (/) stays public so the header's Sign in entry point is reachable;
  // NextAuth's own /api/auth/* endpoints, /login, and static assets are intentionally excluded.
  matcher: ['/enter/:path*', '/students/:path*', '/ipp/:path*', '/ingest/:path*'],
}
