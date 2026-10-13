'use client'

import { useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'

/**
 * Keeps the capability-gated nav (Cycles / Ingest / Maintenance, resolved from StaffAppAccess in
 * AppShell) correct on first load. The root layout only re-renders on a FULL document load, so two
 * first-hit races can leave the nav showing only the basic items:
 *   1. entra login race — the session cookie isn't fully readable on the OAuth landing render.
 *   2. caps-query transient — a cold connection pool / token warm-up makes the caps read throw.
 *
 * Fixes, both bounded + guarded (no refresh loops), rendering nothing:
 *   - `enablePostLogin` (entra): ONE refresh after the first authenticated render this session.
 *   - `capsError` (both modes): AppShell couldn't read caps this render → refresh a few times until
 *     it can. A "no row" result is NOT capsError, so a genuinely-no-caps user never loops.
 */
const POST_LOGIN_FLAG = 'postLoginRefreshed'
const CAPS_RETRY_KEY = 'capsRetryCount'
const CAPS_RETRY_MAX = 3

export default function PostLoginRefresh({
  authed,
  capsError,
  enablePostLogin,
}: {
  authed: boolean
  capsError: boolean
  enablePostLogin: boolean
}) {
  const router = useRouter()
  const ranPostLogin = useRef(false)

  // 1) One-time post-login refresh (entra login race).
  useEffect(() => {
    if (!enablePostLogin) return
    if (!authed) {
      try {
        sessionStorage.removeItem(POST_LOGIN_FLAG)
      } catch {
        /* private mode — nothing to reset */
      }
      ranPostLogin.current = false
      return
    }
    if (ranPostLogin.current) return
    let already = false
    try {
      already = sessionStorage.getItem(POST_LOGIN_FLAG) === '1'
    } catch {
      return // sessionStorage unavailable — skip rather than risk a loop
    }
    if (already) return
    ranPostLogin.current = true
    try {
      sessionStorage.setItem(POST_LOGIN_FLAG, '1')
    } catch {
      /* unreachable: getItem above succeeded */
    }
    router.refresh()
  }, [authed, enablePostLogin, router])

  // 2) Bounded caps-error retry (both modes). Reset the counter whenever caps resolve cleanly.
  useEffect(() => {
    if (!capsError) {
      try {
        sessionStorage.removeItem(CAPS_RETRY_KEY)
      } catch {
        /* ignore */
      }
      return
    }
    let count = 0
    try {
      count = Number(sessionStorage.getItem(CAPS_RETRY_KEY) || '0')
    } catch {
      return // no sessionStorage — don't risk an unbounded loop
    }
    if (count >= CAPS_RETRY_MAX) return
    try {
      sessionStorage.setItem(CAPS_RETRY_KEY, String(count + 1))
    } catch {
      return
    }
    const t = setTimeout(() => router.refresh(), 500)
    return () => clearTimeout(t)
  }, [capsError, router])

  return null
}
