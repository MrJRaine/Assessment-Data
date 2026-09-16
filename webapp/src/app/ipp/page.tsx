import { redirect } from 'next/navigation'

// The IPP screen became "Programming" (IPP + Adaptations) in the 0.5.0 makeover.
// Keep the old path working for bookmarks / links.
export default function IppRedirect() {
  redirect('/programming')
}
