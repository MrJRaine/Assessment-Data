// Writing-trait DISPLAY ORDER — a single source of truth shared by the writing entry grid and the
// writing report so the four traits appear in the same order everywhere.
//
// The four traits are stored INDEPENDENTLY in FactAssessmentWriting
// (IdeasScore / OrganizationScore / LanguageScore / ConventionsScore); this module changes only the
// ORDER they are shown in, never their identity or any stored value. Two modes:
//   COIL = Conventions, Organization, Ideas, Language  (the DEFAULT, 2026-10)
//   IOLC = Ideas, Organization, Language, Conventions  (the legacy order)

export type WritingTraitKey = 'ideas' | 'organization' | 'language' | 'conventions'
export type TraitOrderMode = 'COIL' | 'IOLC'

export interface TraitMeta {
  key: WritingTraitKey
  label: string // compact column header
}

const META: Record<WritingTraitKey, TraitMeta> = {
  conventions: { key: 'conventions', label: 'Conv.' },
  organization: { key: 'organization', label: 'Org.' },
  ideas: { key: 'ideas', label: 'Ideas' },
  language: { key: 'language', label: 'Lang.' },
}

const ORDERS: Record<TraitOrderMode, WritingTraitKey[]> = {
  COIL: ['conventions', 'organization', 'ideas', 'language'],
  IOLC: ['ideas', 'organization', 'language', 'conventions'],
}

export const DEFAULT_TRAIT_ORDER: TraitOrderMode = 'COIL'

// Order-independent set of the four trait keys — for membership / exclusion checks (never for display).
export const WRITING_TRAIT_KEYS: ReadonlySet<WritingTraitKey> = new Set(Object.keys(META) as WritingTraitKey[])

// The four traits as {key,label}, in the given mode's order. The grid/report map over this.
export function traitsInOrder(mode: TraitOrderMode): TraitMeta[] {
  return ORDERS[mode].map((k) => META[k])
}
