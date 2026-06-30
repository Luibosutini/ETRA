import { getAccessToken } from './auth'
import { getConfig } from './config'

async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const token = await getAccessToken()
  const { apiEndpoint } = getConfig()
  const res = await fetch(`${apiEndpoint}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...init.headers,
    },
  })
  if (!res.ok) {
    const body = await res.text().catch(() => res.statusText)
    throw new Error(`API error ${res.status}: ${body}`)
  }
  return res
}

// ─── Compute ───────────────────────────────────────────

export interface InstanceInfo {
  instance_id: string
  state: string
  instance_type: string
  launch_time?: string
  ssm_connected?: boolean
  owner?: string
}

export async function getComputeStatus(): Promise<InstanceInfo[]> {
  const res = await apiFetch('/compute/status')
  const data = await res.json()
  return data.instances ?? []
}

export async function startCompute(instanceId?: string): Promise<void> {
  await apiFetch('/compute/start', {
    method: 'POST',
    body: JSON.stringify({ instance_id: instanceId }),
  })
}

export async function stopCompute(instanceId?: string): Promise<void> {
  await apiFetch('/compute/stop', {
    method: 'POST',
    body: JSON.stringify({ instance_id: instanceId }),
  })
}

export async function restartJupyter(instanceId?: string): Promise<void> {
  await apiFetch('/compute/restart-jupyter', {
    method: 'POST',
    body: JSON.stringify({ instance_id: instanceId }),
  })
}

// ─── Workspace ─────────────────────────────────────────

export interface WorkspaceItem {
  key: string
  size: number | null
  last_modified: string | null
}

export async function listWorkspace(prefix: string): Promise<WorkspaceItem[]> {
  const res = await apiFetch(`/workspace?prefix=${encodeURIComponent(prefix)}`)
  const data = await res.json()
  return data.items ?? []
}

/** S3 キーをAPIパスに変換する。スラッシュはパス区切りとして保持し、各セグメントのみエンコードする。*/
function encodeWorkspaceKey(key: string): string {
  return key.split('/').map(encodeURIComponent).join('/')
}

export async function getDownloadUrl(key: string): Promise<string> {
  const res = await apiFetch(`/workspace/${encodeWorkspaceKey(key)}`)
  const data = await res.json()
  return data.url as string
}

export async function getUploadUrl(key: string, contentType = 'application/octet-stream'): Promise<string> {
  const res = await apiFetch(
    `/workspace/${encodeWorkspaceKey(key)}?content_type=${encodeURIComponent(contentType)}`,
    { method: 'PUT' }
  )
  const data = await res.json()
  return data.url as string
}

export async function deleteWorkspaceItem(key: string): Promise<void> {
  await apiFetch(`/workspace/${encodeWorkspaceKey(key)}`, { method: 'DELETE' })
}

export async function uploadFile(key: string, file: File): Promise<void> {
  const uploadUrl = await getUploadUrl(key, file.type || 'application/octet-stream')
  const res = await fetch(uploadUrl, {
    method: 'PUT',
    body: file,
    headers: { 'Content-Type': file.type || 'application/octet-stream' },
  })
  if (!res.ok) throw new Error(`Upload failed: ${res.status}`)
}

// ─── Admin ─────────────────────────────────────────

export interface UserInfo {
  username: string
  email: string
  status: string
  enabled: boolean
  groups: string[]
  created: string | null
}

export async function listUsers(): Promise<UserInfo[]> {
  const res = await apiFetch('/admin/users')
  const data = await res.json()
  return data.users ?? []
}

export async function addUserToGroup(username: string, group: string): Promise<void> {
  await apiFetch(`/admin/users/${encodeURIComponent(username)}/groups/${encodeURIComponent(group)}`, {
    method: 'POST',
  })
}

export async function removeUserFromGroup(username: string, group: string): Promise<void> {
  await apiFetch(`/admin/users/${encodeURIComponent(username)}/groups/${encodeURIComponent(group)}`, {
    method: 'DELETE',
  })
}

export async function terminateInstance(instanceId: string): Promise<void> {
  await apiFetch(`/admin/instances/${encodeURIComponent(instanceId)}/terminate`, {
    method: 'POST',
  })
}

// ─── Connect ───────────────────────────────────────

export interface ConnectCredentials {
  access_key_id: string
  secret_access_key: string
  session_token: string
  expiration: string
  region: string
}

export async function getConnectCredentials(): Promise<ConnectCredentials> {
  const res = await apiFetch('/connect/credentials')
  return res.json()
}

export async function getDcvToken(): Promise<{ url: string; password: string; username: string; expires_in: number }> {
  const res = await apiFetch('/connect/dcv-token')
  return res.json()
}

// ─── DICOM ─────────────────────────────────────────

export interface DicomStudy {
  image_set_id: string
  version: number | null
  study_instance_uid: string | null
  patient_id: string | null
  patient_name: string | null
  study_date: string | null
  study_description: string | null
  series_count: number | null
  instance_count: number | null
  is_primary: boolean | null
  created_at: string | null
  updated_at: string | null
}

export interface DicomStudyList {
  studies: DicomStudy[]
  next_token: string | null
}

export async function listDicomStudies(options: {
  nextToken?: string
  patientId?: string
} = {}): Promise<DicomStudyList> {
  const params = new URLSearchParams()
  if (options.nextToken) params.set('next_token', options.nextToken)
  if (options.patientId) params.set('patient_id', options.patientId)
  const qs = params.toString()
  const res = await apiFetch(`/dicom/studies${qs ? `?${qs}` : ''}`)
  const data = await res.json()
  return { studies: data.studies ?? [], next_token: data.next_token ?? null }
}

// ─── Logs ──────────────────────────────────────────

export interface LogEvent {
  timestamp: number
  message: string
  stream: string
}

export async function listLogGroups(): Promise<string[]> {
  const res = await apiFetch('/logs')
  const data = await res.json()
  return data.groups ?? []
}

export async function getLogEvents(group: string, limit = 50): Promise<LogEvent[]> {
  const res = await apiFetch(
    `/logs/events?group=${encodeURIComponent(group)}&limit=${limit}`
  )
  const data = await res.json()
  return data.events ?? []
}
