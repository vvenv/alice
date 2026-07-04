/** Dev 直连 API 端口，避免 Vite 代理对大 POST 断流；生产走同域 /api */
export function apiUrl(path: string): string {
  const configured = import.meta.env.VITE_API_BASE;
  if (typeof configured === "string" && configured.length > 0) {
    return `${configured.replace(/\/$/, "")}${path}`;
  }
  if (import.meta.env.DEV && typeof window !== "undefined") {
    const { protocol, hostname } = window.location;
    return `${protocol}//${hostname}:3600${path}`;
  }
  return path;
}

/** 带使用码的 API 请求；401 时清除本地凭证并刷新。 */
export async function apiFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const { clearAccessCode, getAccessCode } = await import("./auth");
  const headers = new Headers(init?.headers);
  const code = getAccessCode();
  if (code) headers.set("X-Access-Code", code);

  const response = await fetch(apiUrl(path), { ...init, headers });

  if (response.status === 401) {
    clearAccessCode();
    window.location.reload();
  }

  return response;
}
