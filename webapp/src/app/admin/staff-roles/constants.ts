// Shared constants for the Role Overrides admin screen. Kept out of actions.ts because a
// 'use server' module may only export async functions — the client component and the server
// action both import these from here.

// Override targets. The first three are DATA-ACCESS role tiers (applied by the staff merge, scope from PS).
// 'Maintenance' is a CAPABILITY-only override — no student data; it carries the maintenance flag
// (StaffAppAccess.CanMaintain), effective immediately and workable with no PS record. Kept in sync with
// StaffRoleOverride's allowed values and usp_SetStaffRoleOverride's 51010 guard.
export const OVERRIDE_ROLES = ['Administrator', 'RegionalAnalyst', 'SpecialistTeacher', 'Maintenance'] as const
export type OverrideRole = (typeof OVERRIDE_ROLES)[number]
