import { ReactNode, RefObject, KeyboardEvent, useEffect, useRef } from 'react'

type DialogRole = 'dialog' | 'alertdialog'

interface DialogProps {
  open: boolean
  onClose: () => void
  label: string
  children: ReactNode
  role?: DialogRole
  initialFocusRef?: RefObject<HTMLElement>
  className?: string
}

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'textarea:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  '[contenteditable="true"]',
  '[tabindex]:not([tabindex="-1"])',
].join(',')

function getFocusableElements(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
    (element) =>
      !element.hasAttribute('disabled') &&
      element.getAttribute('aria-hidden') !== 'true' &&
      element.getClientRects().length > 0,
  )
}

export default function Dialog({
  open,
  onClose,
  label,
  children,
  role = 'dialog',
  initialFocusRef,
  className,
}: DialogProps) {
  const dialogRef = useRef<HTMLDivElement>(null)
  const previousActiveElementRef = useRef<HTMLElement | null>(null)

  useEffect(() => {
    if (!open) return

    previousActiveElementRef.current =
      document.activeElement instanceof HTMLElement ? document.activeElement : null

    const focusTimer = window.setTimeout(() => {
      const dialog = dialogRef.current
      if (!dialog) return

      const initialElement = initialFocusRef?.current ?? getFocusableElements(dialog)[0] ?? dialog
      initialElement.focus()
    }, 0)

    return () => {
      window.clearTimeout(focusTimer)
      previousActiveElementRef.current?.focus()
      previousActiveElementRef.current = null
    }
  }, [initialFocusRef, open])

  const handleKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      event.stopPropagation()
      onClose()
      return
    }

    if (event.key !== 'Tab') return

    const dialog = dialogRef.current
    if (!dialog) return

    const focusableElements = getFocusableElements(dialog)
    if (focusableElements.length === 0) {
      event.preventDefault()
      dialog.focus()
      return
    }

    const firstElement = focusableElements[0]
    const lastElement = focusableElements[focusableElements.length - 1]
    const activeElement = document.activeElement

    if (event.shiftKey) {
      if (activeElement === firstElement || activeElement === dialog) {
        event.preventDefault()
        lastElement.focus()
      }
      return
    }

    if (activeElement === lastElement) {
      event.preventDefault()
      firstElement.focus()
    }
  }

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-gray-950/80"
      onClick={onClose}
    >
      <div
        ref={dialogRef}
        role={role}
        aria-modal="true"
        aria-label={label}
        tabIndex={-1}
        onClick={(event) => event.stopPropagation()}
        onKeyDown={handleKeyDown}
        className={
          className ??
          'w-full max-w-lg rounded border border-gray-800 bg-gray-900 p-4 shadow-xl'
        }
      >
        {children}
      </div>
    </div>
  )
}
