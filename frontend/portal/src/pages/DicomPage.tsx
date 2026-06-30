import { useEffect, useState } from 'react'
import { listDicomStudies, DicomStudy } from '../api'
import Field from '../components/Field'
import { ErrorMessage, StatusMessage } from '../components/Message'

/** DICOM StudyDate (YYYYMMDD) を YYYY-MM-DD 表示に変換する。 */
function formatStudyDate(date: string | null): string {
  if (!date || date.length !== 8) return date ?? '-'
  return `${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6, 8)}`
}

function viewerUrl(study: DicomStudy): string {
  // ポータルと OHIF は同一 CloudFront ドメイン配信のため origin から導出する
  const uid = study.study_instance_uid ?? ''
  return `${window.location.origin}/ohif/viewer?StudyInstanceUIDs=${encodeURIComponent(uid)}`
}

export default function DicomPage() {
  const [studies, setStudies] = useState<DicomStudy[]>([])
  const [nextToken, setNextToken] = useState<string | null>(null)
  const [patientId, setPatientId] = useState('')
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<DicomStudy | null>(null)

  const fetchStudies = async (filterPatientId = patientId) => {
    setLoading(true)
    setError(null)
    try {
      const data = await listDicomStudies({ patientId: filterPatientId || undefined })
      setStudies(data.studies)
      setNextToken(data.next_token)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'スタディ一覧の取得に失敗しました')
    } finally {
      setLoading(false)
    }
  }

  const fetchMore = async () => {
    if (!nextToken) return
    setLoadingMore(true)
    setError(null)
    try {
      const data = await listDicomStudies({
        nextToken,
        patientId: patientId || undefined,
      })
      setStudies((prev) => [...prev, ...data.studies])
      setNextToken(data.next_token)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'スタディ一覧の取得に失敗しました')
    } finally {
      setLoadingMore(false)
    }
  }

  useEffect(() => {
    fetchStudies()
  }, [])

  // ─── ビューア表示 ───
  if (selected) {
    return (
      <div className="flex flex-col h-full">
        <div className="flex items-center gap-4 mb-3 flex-wrap">
          <button
            onClick={() => setSelected(null)}
            className="px-3 py-1 rounded text-sm bg-gray-700 hover:bg-gray-600"
          >
            ← 一覧に戻る
          </button>
          <span className="text-sm text-gray-300">
            {selected.patient_id ?? '-'} / {formatStudyDate(selected.study_date)} /{' '}
            {selected.study_description ?? '-'}
          </span>
          <a
            href={viewerUrl(selected)}
            target="_blank"
            rel="noreferrer"
            className="text-sm text-blue-400 hover:text-blue-300"
          >
            新しいタブで開く ↗
            <span className="sr-only">（新しいタブで開きます）</span>
          </a>
        </div>
        {/* iframe 内で Cognito セッションが切れている場合、ログイン画面は iframe 表示を
            拒否するため空白になる。その場合は「新しいタブで開く」を案内する。 */}
        <iframe
          src={viewerUrl(selected)}
          title="OHIF Viewer"
          allow="fullscreen"
          className="w-full min-h-[calc(100vh-12rem)] rounded border border-gray-700 bg-black"
        />
      </div>
    )
  }

  // ─── 一覧表示 ───
  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold">DICOM スタディ一覧</h1>
        <button
          onClick={() => fetchStudies()}
          disabled={loading}
          className="px-3 py-1 rounded text-sm bg-gray-700 hover:bg-gray-600 disabled:opacity-50"
        >
          更新
        </button>
      </div>

      <div className="flex gap-2 mb-4 items-center">
        <Field label="患者 ID" htmlFor="dicom-patient-id" labelHidden>
          <input
            id="dicom-patient-id"
            type="text"
            value={patientId}
            onChange={(e) => setPatientId(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && !loading && fetchStudies()}
            placeholder="患者 ID で絞り込み（完全一致）"
            className="bg-gray-800 border border-gray-700 rounded px-3 py-1 text-sm text-white w-64"
          />
        </Field>
        <button
          onClick={() => fetchStudies()}
          disabled={loading}
          className="px-3 py-1 rounded text-sm bg-gray-700 hover:bg-gray-600 disabled:opacity-50"
        >
          検索
        </button>
      </div>

      {error && <ErrorMessage className="mb-3">{error}</ErrorMessage>}

      {loading ? (
        <StatusMessage className="text-gray-400 animate-pulse">読み込み中...</StatusMessage>
      ) : studies.length === 0 ? (
        <p className="text-gray-400">
          スタディがありません。DICOM データは HealthImaging へのインポート後に表示されます。
        </p>
      ) : (
        <>
          <table className="w-full text-sm border-collapse">
            <caption className="sr-only">DICOM スタディ一覧</caption>
            <thead>
              <tr className="text-left text-gray-400 border-b border-gray-700">
                <th scope="col" className="py-2 pr-4">患者 ID</th>
                <th scope="col" className="py-2 pr-4">患者名</th>
                <th scope="col" className="py-2 pr-4">検査日</th>
                <th scope="col" className="py-2 pr-4">説明</th>
                <th scope="col" className="py-2 pr-4 text-right">Series</th>
                <th scope="col" className="py-2 pr-4 text-right">Images</th>
                <th scope="col" className="py-2"><span className="sr-only">操作</span></th>
              </tr>
            </thead>
            <tbody>
              {studies.map((s) => (
                <tr
                  key={`${s.image_set_id}-${s.version}`}
                  className="border-b border-gray-800 hover:bg-gray-800"
                >
                  <td className="py-2 pr-4">{s.patient_id ?? '-'}</td>
                  <td className="py-2 pr-4">{s.patient_name ?? '-'}</td>
                  <td className="py-2 pr-4">{formatStudyDate(s.study_date)}</td>
                  <td className="py-2 pr-4">{s.study_description ?? '-'}</td>
                  <td className="py-2 pr-4 text-right">{s.series_count ?? '-'}</td>
                  <td className="py-2 pr-4 text-right">{s.instance_count ?? '-'}</td>
                  <td className="py-2 text-right">
                    <button
                      onClick={() => setSelected(s)}
                      disabled={!s.study_instance_uid}
                      aria-label={`${s.patient_id ?? '患者 ID 不明'} のスタディを開く`}
                      className="px-3 py-1 rounded text-sm bg-blue-700 hover:bg-blue-600 disabled:opacity-50"
                    >
                      開く
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {nextToken && (
            <div className="mt-4">
              <button
                onClick={fetchMore}
                disabled={loadingMore}
                className="px-3 py-1 rounded text-sm bg-gray-700 hover:bg-gray-600 disabled:opacity-50"
              >
                {loadingMore ? '読み込み中...' : 'さらに読み込む'}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  )
}
