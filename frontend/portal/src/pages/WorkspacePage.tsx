import { useEffect, useRef, useState } from 'react'
import { listWorkspace, getDownloadUrl, deleteWorkspaceItem, uploadFile, WorkspaceItem } from '../api'
import { getUser } from '../auth'
import CodeEditorModal from './CodeEditorModal'

const EDITABLE_EXTENSIONS = new Set([
  'py', 'm', 'js', 'ts', 'json', 'yaml', 'yml', 'txt', 'md', 'sh', 'r', 'jl', 'csv',
])

function isEditable(item: WorkspaceItem): boolean {
  if (item.size === null) return false
  const ext = item.key.split('.').pop()?.toLowerCase() ?? ''
  return EDITABLE_EXTENSIONS.has(ext)
}

const PREFIXES = [
  { label: 'Personal', key: 'personal' },
  { label: 'Shared / Dropbox', key: 'shared/dropbox/' },
  { label: 'Shared / Templates', key: 'shared/templates/' },
  { label: 'Results', key: 'results' },
]

function formatSize(bytes: number | null): string {
  if (bytes === null) return '—'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}

export default function WorkspacePage() {
  const [userId, setUserId] = useState('')
  const [activePrefix, setActivePrefix] = useState('personal')
  const [items, setItems] = useState<WorkspaceItem[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [uploadKey, setUploadKey] = useState('')
  const [editingItem, setEditingItem] = useState<WorkspaceItem | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    getUser().then((u) => {
      if (u?.profile.sub) setUserId(u.profile.sub)
    })
  }, [])

  const resolvedPrefix = (key: string) => {
    if (key === 'personal') return `personal/${userId}/`
    if (key === 'results') return `results/${userId}/`
    return key
  }

  const fetchItems = async (prefixKey: string) => {
    if (!userId) return
    setLoading(true)
    setError(null)
    try {
      const data = await listWorkspace(resolvedPrefix(prefixKey))
      setItems(data)
    } catch (e) {
      setError(e instanceof Error ? e.message : '取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (userId) fetchItems(activePrefix)
  }, [userId, activePrefix])

  const handleDownload = async (item: WorkspaceItem) => {
    if (item.size === null) return // ディレクトリ
    try {
      const url = await getDownloadUrl(item.key)
      window.open(url, '_blank')
    } catch (e) {
      alert(e instanceof Error ? e.message : 'ダウンロードに失敗しました')
    }
  }

  const handleDelete = async (item: WorkspaceItem) => {
    if (!confirm(`削除しますか？\n${item.key}`)) return
    try {
      await deleteWorkspaceItem(item.key)
      await fetchItems(activePrefix)
    } catch (e) {
      alert(e instanceof Error ? e.message : '削除に失敗しました')
    }
  }

  const handleUpload = async () => {
    const file = fileRef.current?.files?.[0]
    if (!file || !uploadKey) { alert('ファイルとキーを指定してください'); return }
    try {
      await uploadFile(uploadKey, file)
      setUploadKey('')
      if (fileRef.current) fileRef.current.value = ''
      await fetchItems(activePrefix)
    } catch (e) {
      alert(e instanceof Error ? e.message : 'アップロードに失敗しました')
    }
  }

  return (
    <div>
      <h1 className="text-xl font-bold mb-4">ワークスペース</h1>

      {/* プレフィックス切り替え */}
      <div className="flex gap-2 mb-4 flex-wrap">
        {PREFIXES.map((p) => (
          <button
            key={p.key}
            onClick={() => setActivePrefix(p.key)}
            className={`px-3 py-1 rounded text-sm border ${
              activePrefix === p.key
                ? 'bg-blue-700 border-blue-600 text-white'
                : 'border-gray-700 text-gray-400 hover:text-white'
            }`}
          >
            {p.label}
          </button>
        ))}
      </div>

      {/* アップロード */}
      <div className="flex gap-2 mb-4 flex-wrap items-center">
        <input
          ref={fileRef}
          type="file"
          className="text-sm text-gray-400"
          onChange={(e) => {
            const file = e.target.files?.[0]
            if (file) setUploadKey(resolvedPrefix(activePrefix) + file.name)
          }}
        />
        <input
          type="text"
          placeholder="アップロード先キー（ファイル選択で自動入力）"
          value={uploadKey}
          onChange={(e) => setUploadKey(e.target.value)}
          className="flex-1 min-w-48 bg-gray-800 border border-gray-700 rounded px-3 py-1 text-sm text-white"
        />
        <button onClick={handleUpload} className="px-3 py-1 bg-blue-700 hover:bg-blue-600 rounded text-sm text-white">
          アップロード
        </button>
      </div>

      {error && <p className="mb-3 text-red-400 text-sm">{error}</p>}

      {loading ? (
        <p className="text-gray-400 animate-pulse">読み込み中...</p>
      ) : (
        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b border-gray-700 text-gray-400 text-left">
              <th className="py-2 pr-4">キー</th>
              <th className="py-2 pr-4">サイズ</th>
              <th className="py-2 pr-4">更新日時</th>
              <th className="py-2">操作</th>
            </tr>
          </thead>
          <tbody>
            {items.length === 0 && (
              <tr>
                <td colSpan={4} className="py-4 text-gray-500 text-center">ファイルがありません</td>
              </tr>
            )}
            {items.map((item) => (
              <tr key={item.key} className="border-b border-gray-800 hover:bg-gray-900">
                <td className="py-2 pr-4 font-mono text-xs truncate max-w-xs">{item.key}</td>
                <td className="py-2 pr-4 text-gray-400">{formatSize(item.size)}</td>
                <td className="py-2 pr-4 text-gray-400 text-xs">
                  {item.last_modified ? new Date(item.last_modified).toLocaleString('ja-JP') : '—'}
                </td>
                <td className="py-2 flex gap-2">
                  {item.size !== null && (
                    <button
                      onClick={() => handleDownload(item)}
                      className="px-2 py-0.5 rounded text-xs bg-gray-700 hover:bg-gray-600"
                    >
                      DL
                    </button>
                  )}
                  {isEditable(item) && (
                    <button
                      onClick={() => setEditingItem(item)}
                      className="px-2 py-0.5 rounded text-xs bg-indigo-800 hover:bg-indigo-700"
                    >
                      編集
                    </button>
                  )}
                  <button
                    onClick={() => handleDelete(item)}
                    className="px-2 py-0.5 rounded text-xs bg-red-900 hover:bg-red-800"
                  >
                    削除
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editingItem && (
        <CodeEditorModal
          fileKey={editingItem.key}
          fileSize={editingItem.size ?? 0}
          onClose={() => setEditingItem(null)}
          onSaved={() => fetchItems(activePrefix)}
        />
      )}
    </div>
  )
}
