'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getCallerCapabilities } from '@/lib/data'
import { execProc } from '@/lib/db'
import { toUserMessage, UserError } from '@/lib/errors'
import { invalidateAllIdentities } from '@/lib/identityCache'
import { invalidateAllGroups } from '@/lib/groupCache'
import { uploadImportFile, IMPORT_TOPICS, type ImportTopic } from '@/lib/onelake'
import { revalidatePath } from 'next/cache'
import { INGEST_NOTICE_MINUTES } from './constants'

// Ingest requires the CanRunIngest capability (StaffAppAccess allowlist). Resolved server-side so a
// crafted request can't bypass it; the upload writes PS PII to OneLake, so this gate matters.
async function assertIngestAdmin(): Promise<string> {
  const upn = await getCurrentUpn()
  // fresh: authorization must never come from a cached capability — see lib/identityCache.
  const caps = await getCallerCapabilities(upn, { fresh: true })
  if (!caps.canRunIngest) {
    throw new UserError('You do not have permission to run ingest. Contact an administrator if a PowerSchool refresh is needed.')
  }
  return upn
}

export interface UploadResult {
  ok: boolean
  topic: string
  filename?: string
  message?: string
}

/** Upload one PowerSchool export into Files/imports/{topic}/ (replaces the folder's contents). */
export async function uploadIngestFile(topic: string, formData: FormData): Promise<UploadResult> {
  try {
    await assertIngestAdmin()
    if (!IMPORT_TOPICS.includes(topic as ImportTopic)) throw new UserError(`Unknown ingest topic: ${topic}`)
    const file = formData.get('file')
    if (!(file instanceof File) || file.size === 0) throw new UserError('No file provided.')
    // Cap upload size: the whole file is buffered in memory before the OneLake write, so an
    // unbounded upload could OOM the container. 25 MB comfortably covers a full-rollout export.
    const MAX_UPLOAD_BYTES = 25 * 1024 * 1024
    if (file.size > MAX_UPLOAD_BYTES) {
      throw new UserError(`File is ${(file.size / 1048576).toFixed(1)} MB; the limit is 25 MB.`)
    }
    await uploadImportFile(topic as ImportTopic, file.name, await file.arrayBuffer())
    revalidatePath('/ingest')
    return { ok: true, topic, filename: file.name }
  } catch (e) {
    return { ok: false, topic, message: toUserMessage(e) }
  }
}

export interface RunResult {
  ok: boolean
  message: string
}

export interface NoticeResult { ok: boolean; at?: string; error?: string }

/**
 * Put the app into maintenance ahead of an ingest.
 *
 * WHY THIS EXISTS: the save path re-resolves the caller's roster as a scope gate, so if an ingest
 * moves a student between sections while a teacher has a roster open, their save comes back
 * "Not in your roster for this window/group -- not saved." They lose the entry and the message reads
 * as though they did something wrong. Maintenance mode's staged banner -> lock -> AUTO-SAVE is
 * exactly the fix: it flushes in-flight work before the data shifts underneath it.
 *
 * NOTE ON PERMISSIONS: usp_SetMaintenanceWindow throws 51040 unless the caller is a SYSADMIN, which
 * is a different capability from CanRunIngest. An ingest admin who is not also a sysadmin gets a
 * clear message rather than a raw SQL error -- see the runbook for the SQL fallback.
 */
export async function scheduleIngestMaintenance(): Promise<NoticeResult> {
  let upn: string
  try {
    upn = await assertIngestAdmin()
  } catch (e) {
    return { ok: false, error: toUserMessage(e) }
  }
  const at = new Date(Date.now() + INGEST_NOTICE_MINUTES * 60_000)
  try {
    await execProc('usp_SetMaintenanceWindow', {
      MaintenanceAt: at.toISOString().slice(0, 19).replace('T', ' '),
      Message: 'Student data is being updated. Your work is saved automatically before the app pauses.',
      CallerUPN: upn,
    })
    revalidatePath('/ingest')
    return { ok: true, at: at.toISOString() }
  } catch (e) {
    const msg = toUserMessage(e)
    return {
      ok: false,
      error: /51040|sysadmin/i.test(msg)
        ? 'Scheduling maintenance needs sysadmin rights, which this account does not have. Ask a sysadmin, or set the window in SQL (see docs/ingest-runbook.md).'
        : msg,
    }
  }
}

export async function runIngestCycle(skipCoTeachers: boolean): Promise<RunResult> {
  try {
    const upn = await assertIngestAdmin()
    await execProc('usp_TriggerIngestCycle', { SkipCoTeachers: skipCoTeachers ? 1 : 0, CallerUPN: upn })
    // The ingest rewrites DimStaff and StaffAppAccess-adjacent data, so every cached role and
    // capability is now potentially wrong. Clearing here is what makes the 1h TTL on those caches
    // safe: they can only be stale until the data behind them actually changes, and this is that
    // moment. Rosters too — group membership is exactly what an ingest moves.
    invalidateAllIdentities()
    invalidateAllGroups()

    // Bring the app back up. Only on a CLEAN finish: usp_TriggerIngestCycle surfaces excluded rows
    // per run rather than throwing, so "completed with some rows skipped" still lands here and the
    // warehouse is consistent. A THROW does not — it lands in catch below and maintenance stays ON
    // deliberately, because resuming over a half-applied ingest is the exact thing the window exists
    // to prevent (it is also why the window no longer auto-expires).
    let cleared = true
    try {
      await execProc('usp_ClearMaintenanceWindow', { CallerUPN: upn })
    } catch {
      cleared = false // e.g. not a sysadmin; the run itself was fine, so say so and move on
    }
    revalidatePath('/ingest')
    return {
      ok: true,
      message: cleared
        ? 'Ingest cycle completed. The app is back up.'
        : 'Ingest cycle completed, but maintenance could not be cleared automatically — clear it on the Maintenance page.',
    }
  } catch (e) {
    return {
      ok: false,
      message: (e instanceof Error ? e.message : String(e))
        + ' — maintenance has been left ON deliberately, so nobody writes against a half-applied ingest. Clear it once you have checked the warehouse.',
    }
  }
}
