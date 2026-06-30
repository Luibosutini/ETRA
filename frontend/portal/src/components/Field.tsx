import type { ReactNode } from 'react'

interface FieldProps {
  label: string
  htmlFor: string
  children: ReactNode
  hint?: string
  error?: string
  required?: boolean
  labelHidden?: boolean
  className?: string
}

export default function Field({
  label,
  htmlFor,
  children,
  hint,
  error,
  required,
  labelHidden,
  className,
}: FieldProps) {
  return (
    <div className={className}>
      <label
        htmlFor={htmlFor}
        className={labelHidden ? 'sr-only' : 'block text-sm font-medium text-gray-300 mb-1'}
      >
        {label}
        {required && <span aria-hidden="true"> *</span>}
      </label>
      {children}
      {hint && (
        <p id={`${htmlFor}-hint`} className="mt-1 text-xs text-gray-400">
          {hint}
        </p>
      )}
      {error && (
        <p id={`${htmlFor}-error`} role="alert" className="mt-1 text-sm text-red-400">
          {error}
        </p>
      )}
    </div>
  )
}
