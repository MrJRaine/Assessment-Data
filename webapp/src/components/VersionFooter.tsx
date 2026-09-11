'use client'

import { useEffect, useState } from 'react'
import { APP_VERSION, CURRENT_MINOR, currentMinorNotes } from '@/lib/patchNotes'

// ISO date ("2026-09-11") -> "MM/DD/YYYY". Split the string rather than new Date() to avoid a
// timezone shift moving the day.
function fmtDate(iso: string): string {
  const [y, m, d] = iso.split('-')
  return `${m}/${d}/${y}`
}

// Right-aligned version tag in the app footer. Clicking it opens a "What's new" popup listing the
// patch notes for the current minor line (the .0 release plus any hotfixes — e.g. all of 0.4.x).
export default function VersionFooter() {
  const [open, setOpen] = useState(false)
  const notes = currentMinorNotes()
  // Newest note in the minor line (notes are newest-first) = when this line was last updated.
  const lastUpdated = notes.length ? fmtDate(notes[0].date) : null

  // Close on Escape while the popup is open.
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  return (
    <footer className="app-footer">
      <button className="version-tag" onClick={() => setOpen(true)} aria-haspopup="dialog">
        v{APP_VERSION}
      </button>

      {open && (
        <div className="modal-backdrop" role="presentation" onClick={() => setOpen(false)}>
          <div
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="whatsnew-title"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="modal-head">
              <h2 id="whatsnew-title">
                What&rsquo;s new in {CURRENT_MINOR}
                {lastUpdated ? <span className="whatsnew-updated"> (Updated on {lastUpdated})</span> : null}
              </h2>
              <button className="modal-close" onClick={() => setOpen(false)} aria-label="Close" autoFocus>
                &times;
              </button>
            </div>
            <div className="modal-body">
              {notes.length === 0 ? (
                <p className="muted">No notes for this version yet.</p>
              ) : (
                <ul className="patch-notes">
                  {notes.map((n, i) => (
                    <li key={i}>
                      <span className={`patch-kind patch-kind-${n.kind}`}>
                        {n.kind === 'feature' ? 'New' : 'Fix'}
                      </span>
                      <span className="patch-ver">v{n.version}</span>
                      <span className="patch-text">{n.summary}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </div>
      )}
    </footer>
  )
}
