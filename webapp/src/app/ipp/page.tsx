import { PageHeader, ScaffoldNote, Placeholder } from '@/components/ui'

export const dynamic = 'force-dynamic'

export default function Ipp() {
  return (
    <>
      <PageHeader title="IPPs" subtitle="Individual Program Plan reading flags" />
      <ScaffoldNote>
        Will list students flagged for IPP confirmation and bind to the IPP view + confirm proc.
      </ScaffoldNote>
      <Placeholder label="IPP list + confirm action" />
    </>
  )
}
