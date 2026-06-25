import 'server-only'

/**
 * Resolve AUTH_MODE, FAILING CLOSED.
 *
 * `dev` mode bypasses Entra sign-in entirely (every request is treated as DEV_FAKE_UPN), so a
 * production container that accidentally booted in dev mode would expose all data with no login.
 * To make that impossible by config slip:
 *   - the default is `entra` (unset AUTH_MODE => real sign-in required), and
 *   - `dev` is honoured ONLY when ALLOW_DEV_AUTH=true is also set (an explicit, separate opt-in).
 * A `dev` value without that opt-in THROWS — the app fails to serve rather than silently running
 * with auth disabled. Set BOTH only in the synthetic dev environment (.env.dev); never on live.
 */
export function authMode(): 'entra' | 'dev' {
  const mode = (process.env.AUTH_MODE ?? 'entra').toLowerCase()
  if (mode === 'dev') {
    if (process.env.ALLOW_DEV_AUTH !== 'true') {
      throw new Error(
        'AUTH_MODE=dev refused: dev mode bypasses Entra sign-in and must be explicitly opted into ' +
          'with ALLOW_DEV_AUTH=true (synthetic dev only). Use AUTH_MODE=entra for any environment with real data.',
      )
    }
    return 'dev'
  }
  return 'entra'
}
