'use server'

import { getCurrentUpn } from '@/lib/auth'
import { getCallerAccessLevel } from '@/lib/data'
import { execProc } from '@/lib/db'
import { toUserMessage, UserError } from '@/lib/errors'
import { uploadImportFile, IMPORT_TOPICS, type ImportTopic } from '@/lib/onelake'
import { revalidatePath } from 'next/cache'

// Ingest is Regional-Analyst-only (same gate as usp_TriggerIngestCycle). Resolved server-side so a
// crafted request can't bypass it; the upload writes PS PII to OneLake, so this gate matters.
async function assertAnalyst(): Promise<string> {
  const upn = await getCurrentUpn()
  const role = await getCallerAccessLevel(upn)
  if (role !== 'RegionalAnalyst') {
    throw new UserError('Only Regional Analysts can run ingest. Contact a regional analyst if a PowerSchool refresh is needed.')
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
    await assertAnalyst()
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

/**
 * Run the full ingest cycle via usp_TriggerIngestCycle (UPN passed as @CallerUPN for the analyst
 * role gate, since CURRENT_USER is the SP). The orchestrator's data-quality gate still applies —
 * a failure (bad data, missing staging file) bubbles up as the proc's THROW message.
 */
export async function runIngestCycle(skipCoTeachers: boolean): Promise<RunResult> {
  try {
    const upn = await assertAnalyst()
    await execProc('usp_TriggerIngestCycle', { SkipCoTeachers: skipCoTeachers ? 1 : 0, CallerUPN: upn })
    revalidatePath('/ingest')
    return { ok: true, message: 'Ingest cycle completed successfully.' }
  } catch (e) {
    return { ok: false, message: e instanceof Error ? e.message : String(e) }
  }
}
