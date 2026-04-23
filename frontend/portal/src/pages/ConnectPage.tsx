import { useEffect, useState } from 'react'
import { getComputeStatus, getConnectCredentials, InstanceInfo } from '../api'
import { getConfig } from '../config'

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

// ─── 案A: セットアップスクリプト（クレデンシャル不要・即DL） ────

function setupBat(): string {
  return [
    '@echo off',
    'echo ETRA 接続環境セットアップを開始します...',
    'echo.',
    'echo [1/2] AWS CLI をインストール中...',
    'winget install --id Amazon.AWSCLI -e --silent',
    'if %errorlevel% neq 0 (',
    '  echo 警告: winget が利用できません。',
    '  echo https://aws.amazon.com/jp/cli/ から手動でインストールしてください。',
    ')',
    'echo.',
    'echo [2/2] Session Manager Plugin をインストール中...',
    'set PLUGIN_URL=https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe',
    'set PLUGIN_TMP=%TEMP%\\SessionManagerPluginSetup.exe',
    'curl -L -o "%PLUGIN_TMP%" "%PLUGIN_URL%"',
    'if exist "%PLUGIN_TMP%" (',
    '  "%PLUGIN_TMP%" /S',
    '  del "%PLUGIN_TMP%"',
    ') else (',
    '  echo 警告: Plugin のダウンロードに失敗しました。',
    '  echo 手動でインストールしてください:',
    '  echo https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html',
    ')',
    'echo.',
    'echo セットアップが完了しました。',
    'echo 次回からはポータルの「接続スクリプトをダウンロード」ボタンを使って接続してください。',
    'pause',
  ].join('\r\n')
}

function setupSh(): string {
  return [
    '#!/bin/bash',
    'set -e',
    'echo "ETRA 接続環境セットアップを開始します..."',
    'echo',
    'if command -v brew &>/dev/null; then',
    '  echo "[1/2] AWS CLI をインストール中..."',
    '  brew install awscli',
    '  echo "[2/2] Session Manager Plugin をインストール中..."',
    '  brew install --cask session-manager-plugin',
    'else',
    '  echo "Homebrew が見つかりません。手動でインストールしてください:"',
    '  echo "  AWS CLI: https://aws.amazon.com/jp/cli/"',
    '  echo "  Plugin:  https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"',
    '  exit 1',
    'fi',
    'echo',
    'echo "セットアップが完了しました。"',
    'echo "次回からはポータルの「接続スクリプトをダウンロード」ボタンを使って接続してください。"',
  ].join('\n')
}

// ─── 案B: クレデンシャル埋め込み接続スクリプト ──────────────────

function connectBat(
  instanceId: string,
  localPort: number,
  remotePort: number,
  region: string,
  label: string,
  creds: { access_key_id: string; secret_access_key: string; session_token: string; expiration: string },
): string {
  return [
    '@echo off',
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

function connectSh(
  instanceId: string,
  localPort: number,
  remotePort: number,
  region: string,
  label: string,
  creds: { access_key_id: string; secret_access_key: string; session_token: string; expiration: string },
): string {
  return [
    '#!/bin/bash',
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

// ─── セットアップパネル ──────────────────────────────────────────

function SetupPanel({ os }: { os: OS }) {
  const [open, setOpen] = useState(false)
  const isWin = os === 'windows'

  const handleSetupDownload = () => {
    if (isWin) {
      downloadFile(setupBat(), 'etra-setup.bat', 'application/bat')
    } else {
      downloadFile(setupSh(), 'etra-setup.sh', 'application/x-sh')
    }
  }

  return (
    <div className="mb-6 border border-gray-700 rounded">
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-4 py-3 text-sm text-gray-300 hover:text-white"
      >
        <span>初回セットアップ（AWS CLI + Session Manager Plugin）</span>
        <span className="text-gray-500">{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className="border-t border-gray-700 px-4 py-4">
          <p className="text-xs text-gray-400 mb-4">
            初回のみ必要です。セットアップスクリプトをダウンロードしてダブルクリックすると、
            AWS CLI と Session Manager Plugin が自動的にインストールされます。
          </p>
          <button
            onClick={handleSetupDownload}
            className="px-4 py-2 rounded text-sm bg-gray-700 hover:bg-gray-600 text-white"
          >
            セットアップ.{isWin ? 'bat' : 'sh'} をダウンロード
          </button>
          {!isWin && (
            <p className="text-xs text-gray-500 mt-2">
              ダウンロード後: <code>bash ~/Downloads/etra-setup.sh</code> で実行
            </p>
          )}
        </div>
      )}
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

  const handleDownload = async (localPort: number, remotePort: number, label: string) => {
    setLoading(true)
    setError(null)
    try {
      const creds = await getConnectCredentials()
      const content = isWin
        ? connectBat(inst.instance_id, localPort, remotePort, region, label, creds)
        : connectSh(inst.instance_id, localPort, remotePort, region, label, creds)
      const ts = new Date().toISOString().slice(0, 16).replace('T', '_').replace(':', '')
      downloadFile(content, `connect-${label.toLowerCase()}-${ts}.${ext}`, mime)
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
        <span className="ml-2 text-gray-500 text-xs">{inst.instance_type}</span>
      </p>

      {error && <p className="text-red-400 text-xs mb-3">{error}</p>}

      {/* JupyterLab */}
      <div className="mb-4 bg-gray-900 rounded p-3">
        <div className="flex items-center justify-between mb-2">
          <div>
            <p className="text-sm text-white font-semibold">JupyterLab</p>
            <p className="text-xs text-gray-400">接続後 → ブラウザで http://localhost:8888 を開く</p>
          </div>
          <button
            onClick={() => handleDownload(8888, 8888, 'JupyterLab')}
            disabled={loading}
            className="px-3 py-1.5 rounded text-xs bg-blue-800 hover:bg-blue-700 disabled:opacity-50 text-white whitespace-nowrap"
          >
            {loading ? '取得中...' : `.${ext} をダウンロード`}
          </button>
        </div>
      </div>

      {/* Amazon DCV */}
      <div className="bg-gray-900 rounded p-3">
        <div className="flex items-center justify-between mb-2">
          <div>
            <p className="text-sm text-white font-semibold">Amazon DCV（MATLAB GUI）</p>
            <p className="text-xs text-gray-400">接続後 → DCV クライアントで https://localhost:8443 に接続</p>
          </div>
          <button
            onClick={() => handleDownload(8443, 8443, 'DCV')}
            disabled={loading}
            className="px-3 py-1.5 rounded text-xs bg-blue-800 hover:bg-blue-700 disabled:opacity-50 text-white whitespace-nowrap"
          >
            {loading ? '取得中...' : `.${ext} をダウンロード`}
          </button>
        </div>
      </div>

      <p className="text-xs text-gray-600 mt-3">
        * 接続スクリプトには1時間有効の一時認証情報が含まれます。aws configure の設定は不要です。
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
        {/* OS 切り替え */}
        <div className="flex rounded border border-gray-700 overflow-hidden text-sm">
          <button
            onClick={() => setOs('windows')}
            className={`px-4 py-1.5 ${os === 'windows' ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white'}`}
          >
            Windows
          </button>
          <button
            onClick={() => setOs('mac')}
            className={`px-4 py-1.5 ${os === 'mac' ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white'}`}
          >
            Mac / Linux
          </button>
        </div>
      </div>

      {/* セットアップパネル（案A） */}
      <SetupPanel os={os} />

      {/* 接続カード（案B） */}
      {loading ? (
        <p className="text-gray-400 animate-pulse">読み込み中...</p>
      ) : error ? (
        <p className="text-red-400">{error}</p>
      ) : running.length === 0 ? (
        <div className="border border-gray-800 rounded p-6 text-center">
          <p className="text-gray-500 text-sm">実行中のインスタンスがありません。</p>
          <p className="text-gray-600 text-xs mt-1">Dashboard タブからインスタンスを起動してください。</p>
        </div>
      ) : (
        running.map((inst) => (
          <ConnectionCard key={inst.instance_id} inst={inst} os={os} region={region} />
        ))
      )}
    </div>
  )
}
