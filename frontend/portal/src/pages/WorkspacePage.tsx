import { useEffect, useRef, useState } from 'react'
import { listWorkspace, getDownloadUrl, deleteWorkspaceItem, uploadFile, WorkspaceItem } from '../api'
import { getUser } from '../auth'
import { useConfirm } from '../components/ConfirmProvider'
import Field from '../components/Field'
import { ErrorMessage, StatusMessage } from '../components/Message'
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
  const [uploadValidationError, setUploadValidationError] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)
  const [uploadKey, setUploadKey] = useState('')
  const [editingItem, setEditingItem] = useState<WorkspaceItem | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const { confirm } = useConfirm()
  const uploadFileId = 'workspace-upload-file'
  const uploadKeyId = 'workspace-upload-key'
  const uploadErrorId = 'workspace-upload-error'

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
    setError(null)
    try {
      const url = await getDownloadUrl(item.key)
      window.open(url, '_blank')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ダウンロードに失敗しました')
    }
  }

  const handleDelete = async (item: WorkspaceItem) => {
    if (!(await confirm({
      title: '削除しますか？',
      message: item.key,
      confirmLabel: '削除',
      danger: true,
    }))) return
    setError(null)
    try {
      await deleteWorkspaceItem(item.key)
      await fetchItems(activePrefix)
    } catch (e) {
      setError(e instanceof Error ? e.message : '削除に失敗しました')
    }
  }

  const handleUpload = async () => {
    const file = fileRef.current?.files?.[0]
    if (!file || !uploadKey) {
      setUploadValidationError('ファイルとキーを指定してください')
      return
    }
    setError(null)
    setUploadValidationError(null)
    setUploading(true)
    try {
      await uploadFile(uploadKey, file)
      setUploadKey('')
      if (fileRef.current) fileRef.current.value = ''
      await fetchItems(activePrefix)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'アップロードに失敗しました')
    } finally {
      setUploading(false)
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
        <Field label="アップロードするファイル" htmlFor={uploadFileId} labelHidden>
          <input
            id={uploadFileId}
            ref={fileRef}
            type="file"
            aria-invalid={uploadValidationError ? true : undefined}
            aria-describedby={uploadValidationError ? uploadErrorId : undefined}
            className="text-sm text-gray-400"
            onChange={(e) => {
              const file = e.target.files?.[0]
              if (file) setUploadKey(resolvedPrefix(activePrefix) + file.name)
              setUploadValidationError(null)
            }}
          />
        </Field>
        <Field label="アップロード先キー" htmlFor={uploadKeyId} labelHidden className="flex-1 min-w-48">
          <input
            id={uploadKeyId}
            type="text"
            placeholder="アップロード先キー（ファイル選択で自動入力）"
            value={uploadKey}
            aria-invalid={uploadValidationError ? true : undefined}
            aria-describedby={uploadValidationError ? uploadErrorId : undefined}
            onChange={(e) => {
              setUploadKey(e.target.value)
              setUploadValidationError(null)
            }}
            className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-1 text-sm text-white"
          />
        </Field>
        <button
          onClick={handleUpload}
          disabled={uploading}
          className="px-3 py-1 bg-blue-700 hover:bg-blue-600 rounded text-sm text-white disabled:opacity-50"
        >
          {uploading ? 'アップロード中...' : 'アップロード'}
        </button>
      </div>

      {uploadValidationError && (
        <ErrorMessage id={uploadErrorId} className="-mt-2 mb-4">
          {uploadValidationError}
        </ErrorMessage>
      )}

      {error && <ErrorMessage className="mb-3">{error}</ErrorMessage>}

      {loading ? (
        <StatusMessage className="text-gray-400 animate-pulse">読み込み中...</StatusMessage>
      ) : (
        <table className="w-full text-sm border-collapse">
          <caption className="sr-only">ワークスペースのファイル一覧</caption>
          <thead>
            <tr className="border-b border-gray-700 text-gray-400 text-left">
              <th scope="col" className="py-2 pr-4">キー</th>
              <th scope="col" className="py-2 pr-4">サイズ</th>
              <th scope="col" className="py-2 pr-4">更新日時</th>
              <th scope="col" className="py-2">操作</th>
            </tr>
          </thead>
          <tbody>
            {items.length === 0 && (
              <tr>
                <td colSpan={4} className="py-4 text-gray-400 text-center">ファイルがありません</td>
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
                      aria-label={`${item.key} をダウンロード`}
                      className="px-2 py-0.5 rounded text-xs bg-gray-700 hover:bg-gray-600"
                    >
                      DL
                    </button>
                  )}
                  {isEditable(item) && (
                    <button
                      onClick={() => setEditingItem(item)}
                      aria-label={`${item.key} を編集`}
                      className="px-2 py-0.5 rounded text-xs bg-indigo-800 hover:bg-indigo-700"
                    >
                      編集
                    </button>
                  )}
                  <button
                    onClick={() => handleDelete(item)}
                    aria-label={`${item.key} を削除`}
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
