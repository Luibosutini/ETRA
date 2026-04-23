import { useEffect, useState } from 'react'
import { signIn, signOut, handleCallback, getUser, isAdmin, onSilentRenewError } from './auth'
import DashboardPage from './pages/DashboardPage'
import WorkspacePage from './pages/WorkspacePage'
import ConnectPage from './pages/ConnectPage'
import AdminPage from './pages/AdminPage'
import LogsPage from './pages/LogsPage'

type Page = 'dashboard' | 'workspace' | 'connect' | 'admin' | 'logs'

function hashPage(): Page {
  const hash = window.location.hash.replace('#', '')
  if (hash === 'workspace') return 'workspace'
  if (hash === 'connect') return 'connect'
  if (hash === 'admin') return 'admin'
  if (hash === 'logs') return 'logs'
  return 'dashboard'
}

export default function App() {
  const [authed, setAuthed] = useState(false)
  const [loading, setLoading] = useState(true)
  const [admin, setAdmin] = useState(false)
  const [page, setPage] = useState<Page>(hashPage())

  useEffect(() => {
    const init = async () => {
      // PKCE コールバック処理
      if (window.location.search.includes('code=')) {
        try {
          await handleCallback()
          // コールバックパラメータを除去
          window.history.replaceState({}, '', window.location.pathname)
        } catch {
          // 処理済みの場合は無視
        }
      }

      const user = await getUser()
      if (user && !user.expired) {
        setAuthed(true)
        setAdmin(await isAdmin())
      } else {
        await signIn()
      }
      setLoading(false)
    }

    init()
  }, [])

  useEffect(() => {
    // リフレッシュトークンも期限切れになった場合は再ログインへ
    onSilentRenewError(() => signIn())
  }, [])

  useEffect(() => {
    const onHash = () => setPage(hashPage())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <p className="text-gray-400 animate-pulse">認証中...</p>
      </div>
    )
  }

  if (!authed) return null

  return (
    <div className="flex flex-col min-h-screen">
      {/* ヘッダー */}
      <header className="bg-gray-900 border-b border-gray-800 px-6 py-3 flex items-center justify-between">
        <span className="text-lg font-bold text-white tracking-wide">ETRA Analysis Portal</span>
        <nav className="flex gap-4 text-sm">
          <a href="#dashboard" className={`hover:text-white ${page === 'dashboard' ? 'text-white font-semibold' : 'text-gray-400'}`}>Dashboard</a>
          <a href="#workspace" className={`hover:text-white ${page === 'workspace' ? 'text-white font-semibold' : 'text-gray-400'}`}>Workspace</a>
          <a href="#connect" className={`hover:text-white ${page === 'connect' ? 'text-white font-semibold' : 'text-gray-400'}`}>Connect</a>
          {admin && (
            <>
              <a href="#admin" className={`hover:text-white ${page === 'admin' ? 'text-white font-semibold' : 'text-gray-400'}`}>Admin</a>
              <a href="#logs" className={`hover:text-white ${page === 'logs' ? 'text-white font-semibold' : 'text-gray-400'}`}>Logs</a>
            </>
          )}
          <button onClick={signOut} className="text-gray-400 hover:text-white">ログアウト</button>
        </nav>
      </header>

      {/* メインコンテンツ */}
      <main className="flex-1 p-6">
        {page === 'dashboard' && <DashboardPage isAdmin={admin} />}
        {page === 'workspace' && <WorkspacePage />}
        {page === 'connect' && <ConnectPage />}
        {page === 'admin' && <AdminPage isAdmin={admin} />}
        {page === 'logs' && <LogsPage isAdmin={admin} />}
      </main>
    </div>
  )
}
