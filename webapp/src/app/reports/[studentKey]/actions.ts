'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getStudentHistory, getStudentHistoryWriting, type HistoryRow, type WritingHistoryRow } from '@/lib/data'

/**
 * Fetch one student's reading history. Called from the detail view for client-side prev/next
 * paging: the current student's history and both neighbours' are loaded + cached, so navigation
 * is instant. UPN is resolved server-side (the TVF scopes to what the caller may see), so passing
 * a studentKey outside scope simply returns no rows.
 */
export async function loadStudentHistory(studentKey: string): Promise<HistoryRow[]> {
  const upn = await getCurrentUpn()
  return getStudentHistory(upn, studentKey)
}

/** Writing counterpart of loadStudentHistory (same prev/next prefetch path, Writing tab). */
export async function loadStudentHistoryWriting(studentKey: string): Promise<WritingHistoryRow[]> {
  const upn = await getCurrentUpn()
  return getStudentHistoryWriting(upn, studentKey)
}
