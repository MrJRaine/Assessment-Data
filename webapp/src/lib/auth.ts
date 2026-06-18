import 'server-only'

/**
 * Identity resolution (SERVER-ONLY). Two modes, selected by AUTH_MODE:
 *  - 'dev'   : returns DEV_FAKE_UPN so the app runs end to end before Entra is wired.
 *              LOCAL ONLY -- never deploy with this.
 *  - 'entra' : MSAL on-behalf-of flow -> validate the signed-in teacher's token and pull
 *              their UPN. NOT WIRED YET (blocked on the Entra app registration from IT,
 *              the same critical-path dependency tracked for the bridge).
 *
 * The resolved UPN flows into db.queryAsUser() as the @UPN parameter the secured views
 * filter on.
 */
export function getCurrentUpn(): string {
  const mode = process.env.AUTH_MODE ?? 'dev'

  if (mode === 'dev') {
    const upn = process.env.DEV_FAKE_UPN
    if (!upn) throw new Error('AUTH_MODE=dev requires DEV_FAKE_UPN to be set')
    return upn
  }

  // TODO(entra): wire @azure/msal-node OBO; resolve UPN from the validated access token.
  throw new Error('AUTH_MODE=entra is not wired yet (MSAL OBO pending the Entra app registration)')
}
