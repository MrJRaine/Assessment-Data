import { auth, signIn, signOut } from '@/auth'

// Header identity widget: the signed-in Entra user (or a sign-in button).
export default async function AuthArea() {
  const session = await auth()
  const user = session?.user as ({ upn?: string; email?: string } | undefined)

  if (user) {
    return (
      <form
        className="authform"
        action={async () => {
          'use server'
          await signOut()
        }}
      >
        <span className="muted">{user.upn ?? user.email}</span>
        <button className="btn-ghost">Sign out</button>
      </form>
    )
  }

  return (
    <form
      action={async () => {
        'use server'
        await signIn('microsoft-entra-id')
      }}
    >
      <button className="btn">Sign in</button>
    </form>
  )
}
