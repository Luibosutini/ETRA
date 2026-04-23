import { useEffect, useState } from 'react'
import { listUsers, addUserToGroup, removeUserFromGroup, UserInfo } from '../api'

const MANAGED_GROUPS = ['admin', 'user']

export default function AdminPage({ isAdmin }: { isAdmin: boolean }) {
  const [users, setUsers] = useState<UserInfo[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchUsers = async () => {
    setLoading(true)
    setError(null)
    try {
      setUsers(await listUsers())
    } catch (e) {
      setError(e instanceof Error ? e.message : '取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (isAdmin) fetchUsers()
  }, [isAdmin])

  if (!isAdmin) {
    return <p className="text-red-400 mt-4">このページは管理者のみ表示できます。</p>
  }

  const toggleGroup = async (username: string, group: string, hasGroup: boolean) => {
    try {
      if (hasGroup) {
        await removeUserFromGroup(username, group)
      } else {
        await addUserToGroup(username, group)
      }
      await fetchUsers()
    } catch (e) {
      alert(e instanceof Error ? e.message : '操作に失敗しました')
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold">ユーザー管理</h1>
        <button
          onClick={fetchUsers}
          className="px-3 py-1 rounded text-sm bg-gray-700 hover:bg-gray-600"
        >
          更新
        </button>
      </div>

      {error && <p className="mb-3 text-red-400 text-sm">{error}</p>}

      {loading ? (
        <p className="text-gray-400 animate-pulse">読み込み中...</p>
      ) : (
        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b border-gray-700 text-gray-400 text-left">
              <th className="py-2 pr-4">メール</th>
              <th className="py-2 pr-4">ステータス</th>
              <th className="py-2 pr-4">グループ</th>
              <th className="py-2">操作</th>
            </tr>
          </thead>
          <tbody>
            {users.length === 0 && (
              <tr>
                <td colSpan={4} className="py-4 text-gray-500 text-center">
                  ユーザーがいません
                </td>
              </tr>
            )}
            {users.map((u) => (
              <tr key={u.username} className="border-b border-gray-800 hover:bg-gray-900">
                <td className="py-2 pr-4 font-mono text-xs">
                  <div>{u.email || u.username}</div>
                  <div className="text-gray-500">{u.username}</div>
                </td>
                <td className="py-2 pr-4">
                  <span
                    className={`px-2 py-0.5 rounded text-xs ${
                      u.enabled ? 'bg-green-900 text-green-300' : 'bg-red-900 text-red-300'
                    }`}
                  >
                    {u.status}
                  </span>
                </td>
                <td className="py-2 pr-4">
                  <div className="flex gap-1 flex-wrap">
                    {u.groups.map((g) => (
                      <span key={g} className="px-2 py-0.5 rounded text-xs bg-blue-900 text-blue-300">
                        {g}
                      </span>
                    ))}
                    {u.groups.length === 0 && (
                      <span className="text-gray-500 text-xs">なし</span>
                    )}
                  </div>
                </td>
                <td className="py-2">
                  <div className="flex gap-1 flex-wrap">
                    {MANAGED_GROUPS.map((g) => {
                      const has = u.groups.includes(g)
                      return (
                        <button
                          key={g}
                          onClick={() => toggleGroup(u.username, g, has)}
                          className={`px-2 py-0.5 rounded text-xs ${
                            has
                              ? 'bg-red-900 hover:bg-red-800 text-red-200'
                              : 'bg-gray-700 hover:bg-gray-600 text-gray-200'
                          }`}
                        >
                          {has ? `${g} 削除` : `${g} 追加`}
                        </button>
                      )
                    })}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
