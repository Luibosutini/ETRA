import { useEffect, useState } from 'react'
import { listLogGroups, getLogEvents, LogEvent } from '../api'

export default function LogsPage({ isAdmin }: { isAdmin: boolean }) {
  const [groups, setGroups] = useState<string[]>([])
  const [selectedGroup, setSelectedGroup] = useState('')
  const [events, setEvents] = useState<LogEvent[]>([])
  const [loadingGroups, setLoadingGroups] = useState(false)
  const [loadingEvents, setLoadingEvents] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!isAdmin) return
    setLoadingGroups(true)
    listLogGroups()
      .then((g) => {
        setGroups(g)
        if (g.length > 0) setSelectedGroup(g[0])
      })
      .catch((e) => setError(e instanceof Error ? e.message : '取得に失敗しました'))
      .finally(() => setLoadingGroups(false))
  }, [isAdmin])

  const fetchEvents = async (group: string) => {
    if (!group) return
    setLoadingEvents(true)
    setError(null)
    try {
      setEvents(await getLogEvents(group, 50))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ログ取得に失敗しました')
    } finally {
      setLoadingEvents(false)
    }
  }

  useEffect(() => {
    if (selectedGroup) fetchEvents(selectedGroup)
  }, [selectedGroup])

  if (!isAdmin) {
    return <p className="text-red-400 mt-4">このページは管理者のみ表示できます。</p>
  }

  return (
    <div>
      <h1 className="text-xl font-bold mb-4">実行ログ</h1>

      <div className="flex gap-2 mb-4 items-center flex-wrap">
        {loadingGroups ? (
          <span className="text-gray-400 text-sm animate-pulse">ロードグループ取得中...</span>
        ) : (
          <select
            value={selectedGroup}
            onChange={(e) => setSelectedGroup(e.target.value)}
            className="bg-gray-800 border border-gray-700 rounded px-3 py-1 text-sm text-white"
          >
            {groups.map((g) => (
              <option key={g} value={g}>
                {g}
              </option>
            ))}
          </select>
        )}
        <button
          onClick={() => fetchEvents(selectedGroup)}
          disabled={!selectedGroup}
          className="px-3 py-1 rounded text-sm bg-gray-700 hover:bg-gray-600 disabled:opacity-50"
        >
          更新
        </button>
      </div>

      {error && <p className="mb-3 text-red-400 text-sm">{error}</p>}

      {loadingEvents ? (
        <p className="text-gray-400 animate-pulse">読み込み中...</p>
      ) : (
        <div className="font-mono text-xs bg-gray-900 rounded border border-gray-700 overflow-auto max-h-[70vh]">
          {events.length === 0 ? (
            <p className="p-4 text-gray-500">ログがありません（直近 24 時間）</p>
          ) : (
            events.map((e, i) => (
              <div
                key={i}
                className="px-4 py-1 border-b border-gray-800 hover:bg-gray-800 flex gap-3"
              >
                <span className="text-gray-500 shrink-0 w-44">
                  {new Date(e.timestamp).toLocaleString('ja-JP')}
                </span>
                <span className="text-gray-300 break-all">{e.message}</span>
              </div>
            ))
          )}
        </div>
      )}
    </div>
  )
}
