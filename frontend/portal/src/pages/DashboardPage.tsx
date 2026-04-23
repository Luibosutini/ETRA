import { useEffect, useState } from 'react'
import { getComputeStatus, startCompute, stopCompute, InstanceInfo } from '../api'

interface Props {
  isAdmin: boolean
}

const STATE_COLOR: Record<string, string> = {
  running: 'text-green-400',
  stopped: 'text-gray-400',
  pending: 'text-yellow-400',
  stopping: 'text-orange-400',
  terminated: 'text-red-400',
}

export default function DashboardPage({ isAdmin }: Props) {
  const [instances, setInstances] = useState<InstanceInfo[]>([])
  const [loading, setLoading] = useState(true)
  const [actionId, setActionId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const fetchStatus = async () => {
    try {
      const data = await getComputeStatus()
      setInstances(data)
    } catch (e) {
      setError(e instanceof Error ? e.message : '取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchStatus() }, [])

  const handleStart = async (id: string) => {
    setActionId(id)
    setError(null)
    try {
      await startCompute(id)
      await fetchStatus()
    } catch (e) {
      setError(e instanceof Error ? e.message : '起動に失敗しました')
    } finally {
      setActionId(null)
    }
  }

  const handleStop = async (id: string) => {
    if (!confirm(`インスタンス ${id} を停止しますか？`)) return
    setActionId(id)
    setError(null)
    try {
      await stopCompute(id)
      await fetchStatus()
    } catch (e) {
      setError(e instanceof Error ? e.message : '停止に失敗しました')
    } finally {
      setActionId(null)
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold">解析ノード 状態</h1>
        <button onClick={fetchStatus} className="text-sm text-gray-400 hover:text-white border border-gray-700 rounded px-3 py-1">
          更新
        </button>
      </div>

      {error && <p className="mb-4 text-red-400 text-sm">{error}</p>}

      {loading ? (
        <p className="text-gray-400 animate-pulse">読み込み中...</p>
      ) : instances.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-gray-500 mb-4">解析ノードがまだ作成されていません。</p>
          <button
            onClick={() => handleStart('')}
            disabled={actionId !== null}
            className="px-4 py-2 rounded text-sm bg-green-800 hover:bg-green-700 disabled:opacity-40"
          >
            {actionId !== null ? '起動中...' : '解析ノードを起動'}
          </button>
          {error && <p className="mt-3 text-red-400 text-sm">{error}</p>}
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="border-b border-gray-700 text-gray-400 text-left">
                <th className="py-2 pr-4">Instance ID</th>
                <th className="py-2 pr-4">State</th>
                <th className="py-2 pr-4">Type</th>
                <th className="py-2 pr-4">Launch Time</th>
                {isAdmin && <th className="py-2 pr-4">Owner</th>}
                <th className="py-2">操作</th>
              </tr>
            </thead>
            <tbody>
              {instances.map((inst) => (
                <tr key={inst.instance_id} className="border-b border-gray-800 hover:bg-gray-900">
                  <td className="py-2 pr-4 font-mono text-xs">{inst.instance_id}</td>
                  <td className={`py-2 pr-4 font-semibold ${STATE_COLOR[inst.state] ?? 'text-gray-300'}`}>
                    {inst.state}
                  </td>
                  <td className="py-2 pr-4 text-gray-300">{inst.instance_type}</td>
                  <td className="py-2 pr-4 text-gray-400 text-xs">
                    {inst.launch_time ? new Date(inst.launch_time).toLocaleString('ja-JP') : '—'}
                  </td>
                  {isAdmin && (
                    <td className="py-2 pr-4 text-gray-400 text-xs font-mono">{(inst as any).owner || '—'}</td>
                  )}
                  <td className="py-2 flex gap-2">
                    <button
                      onClick={() => handleStart(inst.instance_id)}
                      disabled={actionId === inst.instance_id || inst.state === 'running' || inst.state === 'pending'}
                      className="px-2 py-1 rounded text-xs bg-green-800 hover:bg-green-700 disabled:opacity-40"
                    >
                      起動
                    </button>
                    <button
                      onClick={() => handleStop(inst.instance_id)}
                      disabled={actionId === inst.instance_id || inst.state === 'stopped' || inst.state === 'stopping'}
                      className="px-2 py-1 rounded text-xs bg-red-800 hover:bg-red-700 disabled:opacity-40"
                    >
                      停止
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
