import { ReactNode } from 'react'

interface MessageProps {
  children: ReactNode
  className?: string
  id?: string
}

export function ErrorMessage({ children, className, id }: MessageProps) {
  return (
    <p id={id} role="alert" className={`text-red-400 text-sm ${className ?? ''}`}>
      {children}
    </p>
  )
}

export function StatusMessage({ children, className, id }: MessageProps) {
  return (
    <p id={id} role="status" className={className}>
      {children}
    </p>
  )
}
