import 'server-only'

/** Thrown for intentional, user-facing validation failures in app code (e.g. "file too large",
 *  "Regional Analysts only"). toUserMessage() passes these through verbatim in any environment. */
export class UserError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'UserError'
  }
}

/**
 * Map a thrown error to a CLIENT-SAFE message.
 *
 * Intentional app-validation THROWs (SQL error numbers 51000-51999, surfaced by mssql as
 * RequestError.number) are user-facing by design — pass them through. Everything else
 * (connection/driver/SQL internals) is genericized in production so we don't leak server or
 * schema details to the browser; the raw message is shown only in the explicit dev-diagnostic mode.
 */
export function toUserMessage(err: unknown): string {
  if (err instanceof UserError) return err.message
  const e = err as { number?: unknown; message?: unknown }
  const num = typeof e?.number === 'number' ? e.number : undefined
  if (num !== undefined && num >= 51000 && num < 52000 && typeof e.message === 'string') {
    return e.message
  }
  if (process.env.AUTH_MODE === 'dev' && process.env.ALLOW_DEV_AUTH === 'true' && typeof e?.message === 'string') {
    return e.message
  }
  return 'Something went wrong. Please retry; if it persists, contact your administrator.'
}
