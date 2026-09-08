'use client'

import { useState } from 'react'
import { CardLink } from '@/components/ui'
import type { TeacherGroup } from '@/lib/data'

/**
 * Group cards for the choose-a-group screen, with a collapsible SCHOOL filter that appears only
 * when the signed-in user's groups span more than one school (admins / regional analysts).
 * Teachers see a single school, so the filter is hidden and this renders a plain card grid. Mirrors
 * the small-group student picker (collapsible mfilter panel + checkboxes + Select all/Clear all);
 * filtering is client-side over the already-loaded groups (no re-fetch).
 */
export default function GroupCards({ groups, windowId }: { groups: TeacherGroup[]; windowId: string }) {
  const schools = [...new Set(groups.map((g) => g.schoolName).filter((s): s is string => !!s))].sort()
  const multi = schools.length > 1

  const [shown, setShown] = useState<Set<string>>(() => new Set(schools))
  const [open, setOpen] = useState(false)

  const visible = multi ? groups.filter((g) => g.schoolName != null && shown.has(g.schoolName)) : groups

  function toggle(s: string) {
    setShown((prev) => {
      const next = new Set(prev)
      if (next.has(s)) next.delete(s)
      else next.add(s)
      return next
    })
  }

  return (
    <>
      {multi && (
        <div className="mfilter">
          <button className="mfilter-summary" onClick={() => setOpen(!open)}>
            <span className="chev">{open ? '▾' : '▸'}</span> Schools{' '}
            <span className="muted">({shown.size} of {schools.length} shown)</span>
          </button>
          {open && (
            <div className="mfilter-body">
              <div className="mfilter-actions">
                <button type="button" className="btn-ghost" onClick={() => setShown(new Set(schools))}>Select all</button>
                <button type="button" className="btn-ghost" onClick={() => setShown(new Set())}>Clear all</button>
                <span className="muted small">Filter the cards to one or more schools.</span>
              </div>
              <div className="chips">
                {schools.map((s) => (
                  <label key={s} className="schip">
                    <input type="checkbox" checked={shown.has(s)} onChange={() => toggle(s)} />
                    {s} <span className="muted">· {groups.filter((g) => g.schoolName === s).length}</span>
                  </label>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      <div className="card-grid">
        {visible.map((g) => (
          <CardLink
            key={g.key}
            href={`/enter/${windowId}/${g.key}`}
            title={g.label}
            desc={g.schoolName ?? undefined}
            meta={`${g.enteredCount}/${g.applicableCount} entered`}
          />
        ))}
      </div>
    </>
  )
}
