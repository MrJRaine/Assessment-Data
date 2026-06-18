/**
 * Surrogate keys are Fabric BIGINT IDENTITY (up to 19 digits) and EXCEED JavaScript
 * Number's 16-significant-digit safe range -- the exact same trap that bit the Power Fx
 * layer (Number is IEEE 754 double in both). Keep surrogate keys as STRINGS end to end.
 *
 * The warehouse views/procs already cast keys to VARCHAR(20) for the Power Apps layer;
 * the web app consumes those same string-typed keys. Never parse a surrogate key into a
 * number for storage, comparison, or round-tripping.
 */

export type SurrogateKey = string & { readonly __brand: 'SurrogateKey' }

/** Validate and brand a value as a surrogate key (1-20 digit string). */
export function toKey(v: string): SurrogateKey {
  if (!/^\d{1,20}$/.test(v)) {
    throw new Error(`Invalid surrogate key (expected 1-20 digit string): ${v}`)
  }
  return v as SurrogateKey
}

/** True only if the value would survive a round-trip through a JS number. Most 19-digit
 *  keys will NOT -- this exists to assert the danger, not to license number conversion. */
export function isSafeAsNumber(v: string): boolean {
  return Number.isSafeInteger(Number(v))
}
