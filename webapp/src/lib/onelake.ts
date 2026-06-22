import 'server-only'
import { getCredential } from './db'

/**
 * OneLake upload (SERVER-ONLY) for the in-app ingest screen.
 *
 * The ingest orchestrator's load procs COPY INTO from the OneLake landing lakehouse
 * (Assessment_Landing) at Files/imports/{topic}/*. Power Apps/Power Automate couldn't push files
 * there (the Entra HTTP connector is text-only / base64 -- see feedback_webcontents_no_binary).
 * The web app can: we mint a STORAGE-scoped token with the same service-principal credential the
 * DB uses and write via the ADLS Gen2 REST API (OneLake is ADLS Gen2-compatible). Pure HTTPS +
 * @azure/identity -- no premium connector, $0. Requires the SP to have workspace Contributor
 * (OneLake read+write); the COPY INTO source read uses the same access.
 *
 * RESIDENCY (PIIDPA): real PS exports are student PII and flow THROUGH this server on the way to
 * OneLake, so the container must run in a Canadian region (same bar as the DB connection).
 */

const STORAGE_SCOPE = 'https://storage.azure.com/.default'
const DFS_HOST = 'https://onelake.dfs.fabric.microsoft.com'
const API_VERSION = '2023-11-03'

// Folder names under Files/imports/ — MUST match the COPY INTO paths in the usp_Load*Staging procs.
export const IMPORT_TOPICS = ['students', 'staff', 'sections', 'enrollments', 'section-teachers'] as const
export type ImportTopic = (typeof IMPORT_TOPICS)[number]

function ids(): { workspace: string; lakehouse: string } {
  const workspace = process.env.ONELAKE_WORKSPACE
  const lakehouse = process.env.ONELAKE_LANDING_LAKEHOUSE
  if (!workspace || !lakehouse) {
    throw new Error('ONELAKE_WORKSPACE and ONELAKE_LANDING_LAKEHOUSE must be set (workspace + Assessment_Landing lakehouse GUIDs)')
  }
  return { workspace, lakehouse }
}

async function authHeader(): Promise<string> {
  const token = await getCredential().getToken(STORAGE_SCOPE)
  if (!token?.token) throw new Error('Failed to acquire a OneLake (storage) access token')
  return `Bearer ${token.token}`
}

// Full DFS URL for a path within the workspace filesystem (path is relative to the lakehouse).
function url(lakehousePath: string, query = ''): string {
  const { workspace } = ids()
  return `${DFS_HOST}/${workspace}/${lakehousePath}${query}`
}

async function dfs(method: string, fullUrl: string, body?: BodyInit): Promise<Response> {
  const headers: Record<string, string> = {
    Authorization: await authHeader(),
    'x-ms-version': API_VERSION,
  }
  if (body) headers['Content-Type'] = 'application/octet-stream'
  return fetch(fullUrl, { method, headers, body })
}

async function ok(res: Response, ...acceptable: number[]): Promise<void> {
  if (res.ok || acceptable.includes(res.status)) return
  const detail = await res.text().catch(() => '')
  throw new Error(`OneLake ${res.status} ${res.statusText}${detail ? `: ${detail.slice(0, 300)}` : ''}`)
}

/**
 * Replace the contents of Files/imports/{topic}/ with a single uploaded file. Clears the folder
 * first (the loaders wildcard-union every file in the folder, so a stale file would duplicate
 * rows), then writes the new one via ADLS Gen2 create -> append -> flush.
 */
export async function uploadImportFile(topic: ImportTopic, filename: string, bytes: ArrayBuffer): Promise<void> {
  const { lakehouse } = ids()
  const dir = `${lakehouse}/Files/imports/${topic}`
  const safeName = filename.replace(/[^A-Za-z0-9._-]/g, '_') || `${topic}.csv`

  // 1. Ensure the topic directory exists (409 = already there).
  await ok(await dfs('PUT', url(dir, '?resource=directory')), 409)

  // 2. Clear existing files in the folder.
  const list = await dfs(
    'GET',
    `${DFS_HOST}/${ids().workspace}?resource=filesystem&recursive=false&directory=${encodeURIComponent(dir)}`,
  )
  await ok(list, 404)
  if (list.ok) {
    const json = (await list.json()) as { paths?: { name: string; isDirectory?: string }[] }
    for (const p of json.paths ?? []) {
      if (p.isDirectory === 'true') continue
      await ok(await dfs('DELETE', `${DFS_HOST}/${ids().workspace}/${p.name}`), 404)
    }
  }

  // 3. Create (truncates if present), append the bytes, flush to commit.
  const target = `${dir}/${safeName}`
  await ok(await dfs('PUT', url(target, '?resource=file')))
  await ok(await dfs('PATCH', url(target, '?action=append&position=0'), bytes))
  await ok(await dfs('PATCH', url(target, `?action=flush&position=${bytes.byteLength}`)))
}
