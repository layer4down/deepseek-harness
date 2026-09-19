import { useEffect, useRef } from 'react'

/** Props for the shell-owned browser title projection. */
export interface DocumentTitleProps {
  /** Durable title of the selected session, or undefined for the product title. */
  title?: string
  /** Custom (activity-visibility): live sessions (running or awaiting the user) across the registry. */
  activeCount?: number
}

/**
 * Project the selected durable session title into the browser title and
 * restore the shell's original product title when unmounted.
 * @param props - selected session title projection.
 * @returns no rendered content.
 */
export function DocumentTitle({ title, activeCount }: DocumentTitleProps): null {
  const original = useRef(document.title)
  useEffect(() => {
    // Custom (activity-visibility): a browser-tab badge for live work; the tab
    // is the only peripheral cue when this app is not the focused tab.
    const prefix = activeCount === undefined || activeCount <= 0 ? '' : `(${activeCount} active) `
    document.title = title === undefined ? original.current : `${prefix}${title} — ${original.current}`
    return () => { document.title = original.current }
  }, [title, activeCount])
  return null
}
