import NextAuth from 'next-auth'
import MicrosoftEntraID from 'next-auth/providers/microsoft-entra-id'
import { authMode } from './lib/authMode'

/**
 * Auth.js (NextAuth v5) config -- Microsoft Entra ID (single tenant).
 *
 * Identity comes from the Entra ID token; we lift the UPN onto the session so the rest of
 * the app (and db.queryAsUser) has the canonical sign-in name.
 *
 * LOGIN vs. DATA app split: the sign-in provider reads AUTH_ENTRA_* credentials — a dedicated
 * Entra app registration for interactive login (redirect URIs + delegated scopes, no data
 * access). These are SEPARATE from the ENTRA_* credentials db.ts uses for the warehouse service
 * principal (the data identity that holds the DB grants). The two never share a secret.
 *
 * trustHost: true so callback URLs resolve correctly behind the container / a reverse proxy.
 */
const loginClientId = process.env.AUTH_ENTRA_CLIENT_ID ?? ''
const loginClientSecret = process.env.AUTH_ENTRA_CLIENT_SECRET ?? ''
const loginTenantId = process.env.AUTH_ENTRA_TENANT_ID

export const { handlers, auth, signIn, signOut } = NextAuth({
  trustHost: true,
  // Where the middleware sends unauthenticated users — a thin page that bounces
  // straight to Entra (see src/app/login/page.tsx), so a protected link never
  // dead-ends on an access error.
  pages: { signIn: '/login' },
  providers: [
    MicrosoftEntraID({
      clientId: loginClientId,
      clientSecret: loginClientSecret,
      issuer: loginTenantId
        ? `https://login.microsoftonline.com/${loginTenantId}/v2.0`
        : undefined,
    }),
  ],
  callbacks: {
    // Route gate used by the middleware. In dev mode there is no Entra session
    // (getCurrentUpn returns DEV_FAKE_UPN), so never gate; in entra mode require a user.
    // authMode() throws if dev mode isn't explicitly opted into — so a misconfigured production
    // container fails closed (500) here rather than silently allowing every request through.
    authorized({ auth }) {
      if (authMode() === 'dev') return true
      return !!auth?.user
    },
    async jwt({ token, profile }) {
      if (profile) {
        const p = profile as { upn?: string; preferred_username?: string }
        token.upn = p.upn ?? p.preferred_username ?? token.email ?? undefined
      }
      return token
    },
    async session({ session, token }) {
      if (session.user) {
        ;(session.user as typeof session.user & { upn?: string }).upn =
          (token.upn as string | undefined) ?? session.user.email ?? undefined
      }
      return session
    },
  },
})
