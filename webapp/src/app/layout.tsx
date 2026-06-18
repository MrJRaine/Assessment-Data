import './globals.css'
import type { Metadata } from 'next'
import AppShell from '@/components/AppShell'

export const metadata: Metadata = {
  title: 'Assessment Data Platform',
  description: 'Regional Student Assessment Data Platform',
}

// Auth lives in the shell (reads cookies) -> render dynamically.
export const dynamic = 'force-dynamic'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <AppShell>{children}</AppShell>
      </body>
    </html>
  )
}
