import { apiUrl } from "./api-url";

const AUTH_KEY = "alice_access_code";

export function getAccessCode(): string | null {
  try {
    return localStorage.getItem(AUTH_KEY);
  } catch {
    return null;
  }
}

export function isAuthenticated(): boolean {
  return Boolean(getAccessCode());
}

export function saveAccessCode(code: string): void {
  try {
    localStorage.setItem(AUTH_KEY, code);
  } catch {
    // ignore quota / private mode
  }
}

export function clearAccessCode(): void {
  try {
    localStorage.removeItem(AUTH_KEY);
  } catch {
    // ignore
  }
}

/** 向服务端校验使用码，通过后写入 localStorage。 */
export async function authenticate(code: string): Promise<boolean> {
  let response: Response;
  try {
    response = await fetch(apiUrl("/api/auth/verify"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code }),
    });
  } catch {
    return false;
  }
  if (!response.ok) return false;
  saveAccessCode(code);
  return true;
}
