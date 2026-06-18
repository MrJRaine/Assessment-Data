// PLACEHOLDER DATA -- lets the navigation/layout scaffold be clickable end to end.
// Each export is to be replaced by a `queryAsUser(...)` call against a secured view
// once Fabric access is wired (Phase 3b / B3). Do NOT ship to users.

export interface MockWindow { id: string; name: string; scale: string; status: string }
export interface MockGroup { key: string; label: string; count: number }
export interface MockStudent { key: string; name: string; grade: string }

export const MOCK_WINDOWS: MockWindow[] = [
  { id: 'W-EN-READ-SP2026', name: 'EN Reading -- Spring 2026', scale: 'EN_Reading', status: 'Open' },
  { id: 'W-FR-READ-SP2026', name: 'FR Reading -- Spring 2026', scale: 'FR_Reading', status: 'Open' },
]

export function mockGroups(windowId: string): MockGroup[] {
  // windowId would scope the query; placeholder returns a fixed set.
  void windowId
  return [
    { key: 'HR-3A', label: 'Homeroom 3A', count: 22 },
    { key: 'HR-3B', label: 'Homeroom 3B', count: 24 },
  ]
}

export const MOCK_STUDENTS: MockStudent[] = [
  { key: '1001', name: 'Sample Student A', grade: '3' },
  { key: '1002', name: 'Sample Student B', grade: '3' },
  { key: '1003', name: 'Sample Student C', grade: '3' },
]
