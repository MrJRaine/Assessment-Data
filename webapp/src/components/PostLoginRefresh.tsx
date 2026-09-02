'use client'

import { useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'

/**
 * One-time post-login refresh.
 *
 * The root layout (header/nav) only re-renders on a FULL document load, so the capability-gated
 * nav items (Cycles / Ingest, resolved from StaffAppAccess in AppShell) can lag the session that
 * was just established — e.g. a cookie/render race on the OAuth landing, or capabilities that
 * became effective around login time. After the first authenticated render in this browser
 * session we force ONE router.refresh(), which re-runs the server layout and re-resolves
 * capabilities so the nav is correct without a manual reload.
 *
 * Guarded by sessionStorage so it fires at most once per login, and cleared on sign-out so the
 * next login refreshes again. Renders nothing.
 */
const FLAG = 'postLoginRefreshed'

export default function PostLoginRefresh({ authed }: { authed: boolean }) {
  const router = useRouter()
  const ran = useRef(false)

  useEffect(() => {
    if (!authed) {
      // Signed out (or never signed in): reset so the NEXT login triggers a refresh again.
      try {
        sessionStorage.removeItem(FLAG)
      } catch {
        /* sessionStorage blocked (private mode) — nothing to reset */
      }
      ran.current = false
      return
    }

    if (ran.current) return

    let already = false
    try {
      already = sessionStorage.getItem(FLAG) === '1'
    } catch {
      // sessionStorage unavailable — skip the optimization rather than refresh-loop.
      return
    }
    if (already) return

    ran.current = true
    try {
      sessionStorage.setItem(FLAG, '1')
    } catch {
      /* unreachable: getItem above already succeeded */
    }
    router.refresh()
  }, [authed, router])

  return null
}
