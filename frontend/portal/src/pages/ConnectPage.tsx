import { useEffect, useState } from 'react'
import { getComputeStatus, getConnectCredentials, getDcvToken, InstanceInfo } from '../api'
import { getConfig } from '../config'
import { ErrorMessage, StatusMessage } from '../components/Message'

type OS = 'windows' | 'mac'

// ─── ファイルダウンロードユーティリティ ──────────────────────────

function downloadFile(content: string, filename: string, mime: string) {
  const blob = new Blob([content], { type: mime })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

// ─── 自動セットアップ（各スクリプト共通ヘッダー） ────────────────

const SETUP_BAT_LINES = [
  'where aws >nul 2>&1',
  'if %errorlevel% neq 0 (',
  '  echo [1/2] AWS CLI が見つかりません。インストールします...',
  '  winget install --id Amazon.AWSCLI -e --silent',
  '  if %errorlevel% neq 0 (',
  '    echo インストールに失敗しました。https://aws.amazon.com/jp/cli/ から手動でインストールしてください。',
  '    pause',
  '    exit /b 1',
  '  )',
  '  set "PATH=%PATH%;C:\\Program Files\\Amazon\\AWSCLIV2"',
  ')',
  'where session-manager-plugin >nul 2>&1',
  'if %errorlevel% neq 0 (',
  '  echo [2/2] Session Manager Plugin が見つかりません。インストールします...',
  '  set PLUGIN_TMP=%TEMP%\\SessionManagerPluginSetup.exe',
  '  curl -L -o "%PLUGIN_TMP%" "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe"',
  '  if exist "%PLUGIN_TMP%" (',
  '    "%PLUGIN_TMP%" /S',
  '    del "%PLUGIN_TMP%"',
  '    set "PATH=%PATH%;C:\\Program Files\\Amazon\\SessionManagerPlugin\\bin"',
  '  ) else (',
  '    echo Plugin のダウンロードに失敗しました。手動でインストールしてください。',
  '    pause',
  '    exit /b 1',
  '  )',
  ')',
  'echo.',
]

const SETUP_SH_LINES = [
  'if ! command -v aws &>/dev/null; then',
  '  echo "[1/2] AWS CLI が見つかりません。インストールします..."',
  '  if command -v brew &>/dev/null; then',
  '    brew install awscli',
  '  else',
  '    echo "Homebrew が見つかりません。手動でインストールしてください: https://aws.amazon.com/jp/cli/"',
  '    exit 1',
  '  fi',
  'fi',
  'if ! command -v session-manager-plugin &>/dev/null; then',
  '  echo "[2/2] Session Manager Plugin が見つかりません。インストールします..."',
  '  if command -v brew &>/dev/null; then',
  '    brew install --cask session-manager-plugin',
  '  else',
  '    echo "Plugin のインストールに失敗しました。手動でインストールしてください。"',
  '    exit 1',
  '  fi',
  'fi',
]

// ─── 接続スクリプト生成 ───────────────────────────────────────────

type Creds = { access_key_id: string; secret_access_key: string; session_token: string; expiration: string }

function connectBat(instanceId: string, localPort: number, remotePort: number, region: string, label: string, creds: Creds): string {
  return [
    '@echo off',
    '@chcp 65001 >nul',
    ...SETUP_BAT_LINES,
    `echo ${label} への接続を開始します...`,
    `echo 有効期限: ${creds.expiration} (UTC)`,
    'echo 接続後、このウィンドウを閉じないでください。',
    'echo.',
    `set AWS_ACCESS_KEY_ID=${creds.access_key_id}`,
    `set AWS_SECRET_ACCESS_KEY=${creds.secret_access_key}`,
    `set AWS_SESSION_TOKEN=${creds.session_token}`,
    `set AWS_DEFAULT_REGION=${region}`,
    'aws ssm start-session ^',
    `  --target ${instanceId} ^`,
    '  --document-name AWS-StartPortForwardingSession ^',
    `  --parameters "{\\"portNumber\\":[\\"${remotePort}\\"],\\"localPortNumber\\":[\\"${localPort}\\"]}" ^`,
    `  --region ${region}`,
    'pause',
  ].join('\r\n')
}

function connectSh(instanceId: string, localPort: number, remotePort: number, region: string, label: string, creds: Creds): string {
  return [
    '#!/bin/bash',
    ...SETUP_SH_LINES,
    `echo "${label} への接続を開始します..."`,
    `echo "有効期限: ${creds.expiration} (UTC)"`,
    'echo "接続後、このウィンドウを閉じないでください。"',
    `export AWS_ACCESS_KEY_ID="${creds.access_key_id}"`,
    `export AWS_SECRET_ACCESS_KEY="${creds.secret_access_key}"`,
    `export AWS_SESSION_TOKEN="${creds.session_token}"`,
    `export AWS_DEFAULT_REGION="${region}"`,
    'aws ssm start-session \\',
    `  --target ${instanceId} \\`,
    '  --document-name AWS-StartPortForwardingSession \\',
    `  --parameters '{"portNumber":["${remotePort}"],"localPortNumber":["${localPort}"]}' \\`,
    `  --region ${region}`,
  ].join('\n')
}

function consoleBat(instanceId: string, region: string, creds: Creds): string {
  return [
    '@echo off',
    '@chcp 65001 >nul',
    ...SETUP_BAT_LINES,
    'echo EC2 コンソールへの接続を開始します...',
    `echo 有効期限: ${creds.expiration} (UTC)`,
    'echo.',
    `set AWS_ACCESS_KEY_ID=${creds.access_key_id}`,
    `set AWS_SECRET_ACCESS_KEY=${creds.secret_access_key}`,
    `set AWS_SESSION_TOKEN=${creds.session_token}`,
    `set AWS_DEFAULT_REGION=${region}`,
    `aws ssm start-session --target ${instanceId} --region ${region}`,
    'pause',
  ].join('\r\n')
}

function consoleSh(instanceId: string, region: string, creds: Creds): string {
  return [
    '#!/bin/bash',
    ...SETUP_SH_LINES,
    'echo "EC2 コンソールへの接続を開始します..."',
    `echo "有効期限: ${creds.expiration} (UTC)"`,
    `export AWS_ACCESS_KEY_ID="${creds.access_key_id}"`,
    `export AWS_SECRET_ACCESS_KEY="${creds.secret_access_key}"`,
    `export AWS_SESSION_TOKEN="${creds.session_token}"`,
    `export AWS_DEFAULT_REGION="${region}"`,
    `aws ssm start-session --target ${instanceId} --region ${region}`,
  ].join('\n')
}

// ─── DCV 接続ボタン ───────────────────────────────────────────

function DcvConnectButton({ ssmReady }: { ssmReady: boolean }) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [cred, setCred] = useState<{ url: string; username: string; password: string } | null>(null)

  const handleConnect = async () => {
    setLoading(true)
    setError(null)
    setCred(null)
    try {
      const data = await getDcvToken()
      setCred({ url: data.url, username: data.username, password: data.password })
      window.open(data.url, '_blank')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'URL の取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs text-gray-300">② DCV に接続</p>
          <p className="text-xs text-gray-400">ブラウザで DCV が開きます（5分有効）</p>
          {error && <ErrorMessage className="text-xs mt-1">{error}</ErrorMessage>}
        </div>
        <button
          onClick={handleConnect}
          disabled={loading || !ssmReady}
          className="px-3 py-1.5 rounded text-xs bg-purple-800 hover:bg-purple-700 disabled:opacity-50 text-white whitespace-nowrap"
        >
          {loading ? '取得中...' : '接続URLを開く'}
        </button>
      </div>
      {cred && (
        <div role="status" className="mt-2 bg-gray-800 rounded p-2 text-xs">
          <p className="text-gray-400 mb-1">DCV ログイン情報（5分有効）</p>
          <p className="text-gray-300">ユーザー名: <span className="text-white font-mono">{cred.username}</span></p>
          <p className="text-gray-300">パスワード: <span className="text-white font-mono select-all">{cred.password}</span></p>
        </div>
      )}
    </div>
  )
}

// ─── コマンドコピー行（Mac/Linux 用）─────────────────────────

function CopyCommand({ filename }: { filename: string }) {
  const [copied, setCopied] = useState(false)
  const cmd = `bash ~/Downloads/${filename}`
  const handleCopy = () => {
    navigator.clipboard.writeText(cmd).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }
  return (
    <div className="mt-2 flex items-center gap-2 bg-gray-800 rounded px-2 py-1">
      <code className="text-xs font-mono text-gray-300 flex-1 select-all">{cmd}</code>
      <button
        onClick={handleCopy}
        className="text-xs text-gray-400 hover:text-white whitespace-nowrap"
      >
        <span aria-live="polite">{copied ? 'コピー済み' : 'コピー'}</span>
      </button>
    </div>
  )
}

// ─── 接続カード ────────────────────────────────────────────────

function ConnectionCard({ inst, os, region }: { inst: InstanceInfo; os: OS; region: string }) {
  const isWin = os === 'windows'
  const ext = isWin ? 'bat' : 'sh'
  const mime = isWin ? 'application/bat' : 'application/x-sh'
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const ssmReady = inst.ssm_connected === true

  const handleDownload = async (localPort: number, remotePort: number, label: string) => {
    setLoading(true)
    setError(null)
    try {
      const creds = await getConnectCredentials()
      const content = isWin
        ? connectBat(inst.instance_id, localPort, remotePort, region, label, creds)
        : connectSh(inst.instance_id, localPort, remotePort, region, label, creds)
      downloadFile(content, `connect-${label.toLowerCase()}.${ext}`, mime)
    } catch (e) {
      setError(e instanceof Error ? e.message : '認証情報の取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  const handleConsoleDownload = async () => {
    setLoading(true)
    setError(null)
    try {
      const creds = await getConnectCredentials()
      const content = isWin
        ? consoleBat(inst.instance_id, region, creds)
        : consoleSh(inst.instance_id, region, creds)
      downloadFile(content, `console.${ext}`, mime)
    } catch (e) {
      setError(e instanceof Error ? e.message : '認証情報の取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="mb-6 border border-gray-800 rounded p-4">
      <p className="text-sm text-gray-300 mb-4">
        <span className="text-white font-semibold">{inst.instance_id}</span>
        <span className="ml-2 text-gray-400 text-xs">{inst.instance_type}</span>
      </p>

      {!ssmReady && (
        <StatusMessage className="text-yellow-400 text-xs mb-3 animate-pulse">SSM に接続中です。1〜3 分後に再度確認してください...</StatusMessage>
      )}
      {error && <ErrorMessage className="text-xs mb-3">{error}</ErrorMessage>}

      {/* JupyterLab */}
      <div className="mb-3 bg-gray-900 rounded p-3">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm text-white font-semibold">JupyterLab</h2>
            <p className="text-xs text-gray-400">接続後 → ブラウザで http://localhost:8888 を開く</p>
          </div>
          <button
            onClick={() => handleDownload(8888, 8888, 'JupyterLab')}
            disabled={loading || !ssmReady}
            className="px-3 py-1.5 rounded text-xs bg-blue-800 hover:bg-blue-700 disabled:opacity-50 text-white whitespace-nowrap"
          >
            {loading ? '取得中...' : `.${ext} をダウンロード`}
          </button>
        </div>
        {!isWin && <CopyCommand filename="connect-jupyterlab.sh" />}
      </div>

      {/* Amazon DCV */}
      <div className="mb-3 bg-gray-900 rounded p-3">
        <h2 className="text-sm text-white font-semibold mb-3">Amazon DCV（MATLAB GUI）</h2>
        <div className="flex items-center justify-between mb-2">
          <div>
            <p className="text-xs text-gray-300">① ポートフォワードを起動</p>
            <p className="text-xs text-gray-400">ウィンドウは接続中、閉じないでください</p>
          </div>
          <button
            onClick={() => handleDownload(8443, 8443, 'DCV')}
            disabled={loading || !ssmReady}
            className="px-3 py-1.5 rounded text-xs bg-blue-800 hover:bg-blue-700 disabled:opacity-50 text-white whitespace-nowrap"
          >
            {loading ? '取得中...' : `.${ext} をダウンロード`}
          </button>
        </div>
        {!isWin && <CopyCommand filename="connect-dcv.sh" />}
        <div className="mt-2">
          <DcvConnectButton ssmReady={ssmReady} />
        </div>
      </div>

      {/* コンソール接続 */}
      <div className="bg-gray-900 rounded p-3">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm text-white font-semibold">コンソール接続（トラブルシュート用）</h2>
            <p className="text-xs text-gray-400">EC2 に直接ログインしてサービス状態を確認できます</p>
          </div>
          <button
            onClick={handleConsoleDownload}
            disabled={loading || !ssmReady}
            className="px-3 py-1.5 rounded text-xs bg-gray-700 hover:bg-gray-600 disabled:opacity-50 text-white whitespace-nowrap"
          >
            {loading ? '取得中...' : `.${ext} をダウンロード`}
          </button>
        </div>
        {!isWin && <CopyCommand filename="console.sh" />}
      </div>

      <p className="text-xs text-gray-400 mt-3">
        * 接続スクリプトには1時間有効の一時認証情報が含まれます。AWS CLI 未インストールの場合は自動でインストールします。
      </p>
    </div>
  )
}

// ─── メインページ ─────────────────────────────────────────────

export default function ConnectPage() {
  const [instances, setInstances] = useState<InstanceInfo[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [os, setOs] = useState<OS>('windows')

  useEffect(() => {
    getComputeStatus()
      .then(setInstances)
      .catch((e) => setError(e instanceof Error ? e.message : 'インスタンス情報の取得に失敗しました'))
      .finally(() => setLoading(false))
  }, [])

  const region = getConfig().region
  const running = instances.filter((i) => i.state === 'running')

  return (
    <div className="max-w-2xl">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-bold">解析ノードへの接続</h1>
        <div className="flex rounded border border-gray-700 overflow-hidden text-sm">
          <button
            onClick={() => setOs('windows')}
            aria-pressed={os === 'windows'}
            className={`px-4 py-1.5 ${os === 'windows' ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white'}`}
          >
            Windows
          </button>
          <button
            onClick={() => setOs('mac')}
            aria-pressed={os === 'mac'}
            className={`px-4 py-1.5 ${os === 'mac' ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white'}`}
          >
            Mac / Linux
          </button>
        </div>
      </div>

      {loading ? (
        <StatusMessage className="text-gray-400 animate-pulse">読み込み中...</StatusMessage>
      ) : error ? (
        <ErrorMessage className="text-base">{error}</ErrorMessage>
      ) : running.length === 0 ? (
        <div className="border border-gray-800 rounded p-6 text-center">
          <p className="text-gray-400 text-sm">実行中のインスタンスがありません。</p>
          <p className="text-gray-400 text-xs mt-1">Dashboard タブからインスタンスを起動してください。</p>
        </div>
      ) : (
        running.map((inst) => (
          <ConnectionCard key={inst.instance_id} inst={inst} os={os} region={region} />
        ))
      )}
    </div>
  )
}
