// Presentational progress cue for the Programming section: two chips (IPPs, Adaptations) coloured
// by how much is done — red < 50%, yellow 50–<100%, green 100% — so remaining work is obvious no
// matter which view you're on (even if you miss the IPP/Adaptations toggle). No hooks: safe in both
// server (picker landing) and client (roster grid) trees.
export interface ProgStat {
  confirmed: number
  total: number
}

function tone(s: ProgStat): 'red' | 'yellow' | 'green' {
  const p = s.confirmed / s.total
  if (p >= 1) return 'green'
  if (p >= 0.5) return 'yellow'
  return 'red'
}

function Chip({ label, verb, stat }: { label: string; verb: string; stat: ProgStat }) {
  if (stat.total === 0) return <span className="pgm-chip pgm-none">No {label} on record</span>
  return (
    <span className={`pgm-chip pgm-${tone(stat)}`}>
      {stat.confirmed} of {stat.total} {label} {verb}
    </span>
  )
}

export default function ProgrammingProgress({ ipp, adaptation }: { ipp: ProgStat; adaptation: ProgStat }) {
  return (
    <div className="pgm-progress">
      <Chip label="IPPs" verb="confirmed" stat={ipp} />
      <Chip label="Adaptations" verb="confirmed" stat={adaptation} />
    </div>
  )
}
