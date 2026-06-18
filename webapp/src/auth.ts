import NextAuth from 'next-auth'
import MicrosoftEntraID from 'next-auth/providers/microsoft-entra-id'

/**
 * Auth.js (NextAuth v5) config -- Microsoft Entra ID (single tenant).
 *
 * Identity comes from the Entra ID token; we lift the UPN onto the session so the rest of
 * the app (and db.queryAsUser) has the canonical sign-in name. Credentials are read from the
 * same ENTRA_* env vars the Fabric connection uses.
 *
 * trustHost: true so callback URLs resolve correctly behind the container / a reverse proxy.
 */
export const { handlers, auth, signIn, signOut } = NextAuth({
  trustHost: true,
  providers: [
    MicrosoftEntraID({
      clientId: process.env.ENTRA_CLIENT_ID ?? '',
      clientSecret: process.env.ENTRA_CLIENT_SECRET ?? '',
      issuer: process.env.ENTRA_TENANT_ID
        ? `https://login.microsoftonline.com/${process.env.ENTRA_TENANT_ID}/v2.0`
        : undefined,
    }),
  ],
  callbacks: {
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
