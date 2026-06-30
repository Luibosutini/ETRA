import {
  ReactNode,
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react'
import Dialog from './Dialog'

interface ConfirmOptions {
  title: string
  message?: string
  confirmLabel?: string
  cancelLabel?: string
  danger?: boolean
}

interface ConfirmContextValue {
  confirm: (options: ConfirmOptions) => Promise<boolean>
}

interface PendingConfirm {
  options: ConfirmOptions
  resolve: (value: boolean) => void
}

const ConfirmContext = createContext<ConfirmContextValue | null>(null)

export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [options, setOptions] = useState<ConfirmOptions | null>(null)
  const pendingRef = useRef<PendingConfirm | null>(null)
  const cancelButtonRef = useRef<HTMLButtonElement>(null)

  const settle = useCallback((value: boolean) => {
    pendingRef.current?.resolve(value)
    pendingRef.current = null
    setOptions(null)
  }, [])

  const confirm = useCallback((nextOptions: ConfirmOptions) => {
    return new Promise<boolean>((resolve) => {
      if (pendingRef.current) {
        pendingRef.current.resolve(false)
      }
      pendingRef.current = { options: nextOptions, resolve }
      setOptions(nextOptions)
    })
  }, [])

  useEffect(() => {
    return () => {
      pendingRef.current?.resolve(false)
    }
  }, [])

  return (
    <ConfirmContext.Provider value={{ confirm }}>
      {children}
      <Dialog
        open={options !== null}
        onClose={() => settle(false)}
        label={options?.title ?? '確認'}
        role="alertdialog"
        initialFocusRef={cancelButtonRef}
        className="mx-4 w-full max-w-md rounded border border-gray-800 bg-gray-900 p-5 shadow-xl"
      >
        {options && (
          <div>
            <h2 className="text-base font-semibold text-white">{options.title}</h2>
            {options.message && (
              <p className="mt-2 whitespace-pre-line text-sm text-gray-300">{options.message}</p>
            )}
            <div className="mt-5 flex justify-end gap-2">
              <button
                ref={cancelButtonRef}
                type="button"
                onClick={() => settle(false)}
                className="rounded border border-gray-700 px-3 py-1.5 text-sm text-gray-300 hover:text-white"
              >
                {options.cancelLabel ?? 'キャンセル'}
              </button>
              <button
                type="button"
                onClick={() => settle(true)}
                className={`rounded px-3 py-1.5 text-sm text-white ${
                  options.danger
                    ? 'bg-red-800 hover:bg-red-700'
                    : 'bg-blue-700 hover:bg-blue-600'
                }`}
              >
                {options.confirmLabel ?? 'OK'}
              </button>
            </div>
          </div>
        )}
      </Dialog>
    </ConfirmContext.Provider>
  )
}

export function useConfirm() {
  const context = useContext(ConfirmContext)
  if (!context) {
    throw new Error('useConfirm must be used within ConfirmProvider')
  }
  return context
}
