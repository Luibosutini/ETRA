import { useEffect, useState, useCallback } from 'react'
import CodeMirror from '@uiw/react-codemirror'
import { oneDark } from '@codemirror/theme-one-dark'
import { python } from '@codemirror/lang-python'
import { javascript } from '@codemirror/lang-javascript'
import { json } from '@codemirror/lang-json'
import { markdown } from '@codemirror/lang-markdown'
import { yaml } from '@codemirror/lang-yaml'
import { getDownloadUrl, getUploadUrl } from '../api'
import Dialog from '../components/Dialog'
import { ErrorMessage, StatusMessage } from '../components/Message'

const MAX_EDIT_SIZE = 1024 * 1024 // 1 MB

function getExtension(key: string) {
  const ext = key.split('.').pop()?.toLowerCase() ?? ''
  switch (ext) {
    case 'py': return [python()]
    case 'js': case 'ts': return [javascript({ typescript: ext === 'ts' })]
    case 'json': return [json()]
    case 'md': return [markdown()]
    case 'yaml': case 'yml': return [yaml()]
    default: return []
  }
}

interface Props {
  fileKey: string
  fileSize: number
  onClose: () => void
  onSaved: () => void
}

export default function CodeEditorModal({ fileKey, fileSize, onClose, onSaved }: Props) {
  const [content, setContent] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (fileSize > MAX_EDIT_SIZE) {
      setError(`ファイルサイズが大きすぎます（${(fileSize / 1024 / 1024).toFixed(1)} MB）。1 MB 以下のファイルのみ編集できます。`)
      setLoading(false)
      return
    }
    getDownloadUrl(fileKey)
      .then((url) => fetch(url))
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.text()
      })
      .then((text) => setContent(text))
      .catch((e) => setError(e instanceof Error ? e.message : '読み込みに失敗しました'))
      .finally(() => setLoading(false))
  }, [fileKey, fileSize])

  const handleSave = async () => {
    setSaving(true)
    setError(null)
    try {
      const url = await getUploadUrl(fileKey, 'text/plain; charset=utf-8')
      const res = await fetch(url, {
        method: 'PUT',
        body: content,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      })
      if (!res.ok) throw new Error(`Upload failed: ${res.status}`)
      onSaved()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : '保存に失敗しました')
    } finally {
      setSaving(false)
    }
  }

  const onChange = useCallback((val: string) => setContent(val), [])

  return (
    <Dialog
      open
      onClose={onClose}
      label={`ファイル編集: ${fileKey}`}
      className="h-full w-full bg-gray-950 flex flex-col"
    >
      {/* ヘッダー */}
      <div className="flex items-center justify-between px-4 py-2 bg-gray-900 border-b border-gray-700 shrink-0">
        <span className="font-mono text-xs text-gray-300 truncate max-w-lg">{fileKey}</span>
        <div className="flex items-center gap-3">
          {error && <ErrorMessage className="text-xs">{error}</ErrorMessage>}
          <button
            onClick={handleSave}
            disabled={saving || loading || !!error}
            className="px-3 py-1 rounded text-sm bg-blue-700 hover:bg-blue-600 disabled:opacity-40 text-white"
          >
            {saving ? '保存中...' : '保存'}
          </button>
          <button
            onClick={onClose}
            className="px-3 py-1 rounded text-sm border border-gray-700 text-gray-400 hover:text-white"
          >
            閉じる
          </button>
        </div>
      </div>

      {/* エディタ本体 */}
      <div className="flex-1 overflow-auto">
        {loading ? (
          <StatusMessage className="p-4 text-gray-400 animate-pulse">読み込み中...</StatusMessage>
        ) : !error ? (
          <CodeMirror
            value={content}
            height="100%"
            theme={oneDark}
            extensions={getExtension(fileKey)}
            onChange={onChange}
            style={{ height: '100%', fontSize: '13px' }}
          />
        ) : null}
      </div>
    </Dialog>
  )
}
