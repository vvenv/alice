import { useState, type FormEvent } from "react";

import { authenticate } from "../lib/auth";

interface AuthGateProps {
  onAuthenticated: () => void;
}

export function AuthGate({ onAuthenticated }: AuthGateProps) {
  const [code, setCode] = useState("");
  const [error, setError] = useState(false);
  const [busy, setBusy] = useState(false);

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (code.length !== 4 || busy) return;
    setBusy(true);
    setError(false);
    try {
      const ok = await authenticate(code);
      if (ok) {
        onAuthenticated();
        return;
      }
      setError(true);
      setCode("");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex-1 w-full max-w-md mx-auto bg-background md:rounded-shell px-4 pt-4 pb-[env(safe-area-inset-bottom)] flex flex-col items-center justify-center gap-6 min-h-dvh md:min-h-[50vh]">
      <div className="text-center">
        <h1 className="text-xl font-semibold text-foreground">听写练习</h1>
        <p className="mt-2 text-sm text-muted">请输入使用码</p>
      </div>

      <form
        onSubmit={handleSubmit}
        className="w-full max-w-[240px] flex flex-col gap-3"
      >
        <input
          type="text"
          inputMode="numeric"
          pattern="[0-9]*"
          autoComplete="one-time-code"
          maxLength={4}
          value={code}
          onChange={(event) => {
            const next = event.target.value.replace(/\D/g, "").slice(0, 4);
            setCode(next);
            setError(false);
          }}
          placeholder="••••"
          autoFocus
          disabled={busy}
          className={`w-full border rounded-card px-4 py-3 text-center text-2xl tracking-[0.4em] font-medium bg-surface-sunken text-foreground transition-all focus:outline-none focus:ring-2 focus:bg-background disabled:opacity-60 ${
            error
              ? "border-danger focus:border-danger focus:ring-danger-soft"
              : "border-border focus:border-primary-focus focus:ring-primary-ring"
          }`}
          aria-invalid={error}
          aria-describedby={error ? "auth-error" : undefined}
        />
        {error ? (
          <p id="auth-error" className="text-center text-sm text-danger">
            使用码不正确
          </p>
        ) : null}
        <button
          type="submit"
          disabled={code.length !== 4 || busy}
          className="btn-lg btn-lg--idle btn-primary w-full disabled:opacity-40 disabled:pointer-events-none"
        >
          {busy ? "验证中…" : "进入"}
        </button>
      </form>
    </div>
  );
}
