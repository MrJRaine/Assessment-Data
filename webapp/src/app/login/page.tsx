'use client'

import { signIn } from 'next-auth/react'
import { Suspense, useEffect } from 'react'
import { useSearchParams } from 'next/navigation'

// Thin redirect page. The middleware sends unauthenticated users here (with ?callbackUrl=<dest>);
// we immediately kick off the Entra sign-in, which returns the user to where they were headed.
function LoginRedirect() {
  const params = useSearchParams()
  const callbackUrl = params.get('callbackUrl') ?? '/'
  useEffect(() => {
    void signIn('microsoft-entra-id', { callbackUrl })
  }, [callbackUrl])
  return (
    <div className="loading">
      <span className="spinner" />
      Redirecting to sign in…
    </div>
  )
}

export default function LoginPage() {
  return (
    <Suspense
      fallback={
        <div className="loading">
          <span className="spinner" />
          Loading…
        </div>
      }
    >
      <LoginRedirect />
    </Suspense>
  )
}
