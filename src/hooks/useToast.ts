import { useCallback, useRef, useState } from "react";

const TOAST_DURATION_MS = 2200;
const TOAST_ACTION_DURATION_MS = 4000;

export type ToastAction = { label: string; onPress: () => void };
export type ToastState = { message: string; action?: ToastAction } | null;

export function useToast() {
  const [toast, setToast] = useState<ToastState>(null);
  const toastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showToast = useCallback((message: string, action?: ToastAction) => {
    setToast({ message, action });
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    // Leave actionable toasts up longer — the user needs time to hit 撤销.
    const duration = action ? TOAST_ACTION_DURATION_MS : TOAST_DURATION_MS;
    toastTimerRef.current = setTimeout(() => setToast(null), duration);
  }, []);

  const hideToast = useCallback(() => {
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    setToast(null);
  }, []);

  return { toast, showToast, hideToast };
}
