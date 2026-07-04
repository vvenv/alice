interface ToastProps {
  message: string;
}

export function Toast({ message }: ToastProps) {
  if (!message) return null;

  return (
    <div className="fixed left-1/2 -translate-x-1/2 bottom-[max(24px,env(safe-area-inset-bottom))] z-50 animate-toast">
      <div className="toast">{message}</div>
    </div>
  );
}
