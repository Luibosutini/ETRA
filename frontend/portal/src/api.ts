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

export async function getDownloadUrl(key: string): Promise<string> {
  const res = await apiFetch(`/workspace/${encodeURIComponent(key)}`)
  const data = await res.json()
  return data.url as string
}

export async function getUploadUrl(key: string, contentType = 'application/octet-stream'): Promise<string> {
  const res = await apiFetch(
    `/workspace/${encodeURIComponent(key)}?content_type=${encodeURIComponent(contentType)}`,
    { method: 'PUT' }
  )
  const data = await res.json()
  return data.url as string
}

export async function deleteWorkspaceItem(key: string): Promise<void> {
  await apiFetch(`/workspace/${encodeURIComponent(key)}`, { method: 'DELETE' })
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
