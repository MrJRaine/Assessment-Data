import { bandForAvg, type Mark } from './mathModel'

// Shared read-only cells for the Reports > Math matrix and the oversight roll-up tree's grade blocks.

/** Achievement Level badge for a unit / overall average (IPP, no data and Incomplete included). */
export function BandCell({ avg, ipp, incomplete }: { avg: number | null; ipp: boolean; incomplete: boolean }) {
  if (avg == null) return <span className={`mband ${ipp ? 'bipp' : 'inc'}`}>{ipp ? 'IPP' : '—'}</span>
  if (incomplete) return <span className="mband inc">Incomplete</span>
  const b = bandForAvg(avg)
  return <span className={`mband ${b.cls}`}>{b.label}</span>
}

/** A single task cell, drawn identically to the entry grid but not interactive. */
export function TaskCell({ v }: { v: Mark }) {
  const cls = v === '1' ? 'yes' : v === '0' ? 'no' : v === 'ipp' ? 'ipp' : 'blank'
  return (
    <span className={`mtoggle ${cls}`} aria-hidden={v === 'blank'}>
      {v === '0' ? <span className="ring" /> : v === '1' ? (
        <svg className="check" viewBox="0 0 24 24">
          <path className="edge" d="M3.6 12.6 Q8.06 14.43 9.6 19 Q13.1 10.53 20.4 5" />
          <path className="fill" d="M3.6 12.6 Q8.06 14.43 9.6 19 Q13.1 10.53 20.4 5" />
        </svg>
      ) : v === 'ipp' ? 'IPP' : ''}
    </span>
  )
}
