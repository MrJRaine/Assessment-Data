// Shared constants for the Role Overrides admin screen. Kept out of actions.ts because a
// 'use server' module may only export async functions — the client component and the server
// action both import these from here.

// The three data-access role tiers that may be assigned as an override. Kept in sync with
// StaffRoleOverride's allowed values and usp_SetStaffRoleOverride's 51010 guard.
export const OVERRIDE_ROLES = ['Administrator', 'RegionalAnalyst', 'SpecialistTeacher'] as const
export type OverrideRole = (typeof OVERRIDE_ROLES)[number]
