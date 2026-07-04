import { clearAccessCode, getAccessCode } from "./auth";
import { apiUrl } from "./api-url";

export { apiUrl };

/** 带使用码的 API 请求；401 时清除本地凭证并刷新。 */
export async function apiFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
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
