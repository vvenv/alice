import { clearAccessCode, getAccessCode } from "./auth";
import { apiUrl } from "./api-url";

export { apiUrl };

/** Auth-wrapped API fetch; on 401 clears credentials and signals caller. */
export async function apiFetch(
  path: string,
  init?: RequestInit,
): Promise<Response> {
  const headers = new Headers(init?.headers);
  const code = getAccessCode();
  if (code) headers.set("X-Access-Code", code);

  const response = await fetch(apiUrl(path), { ...init, headers });

  if (response.status === 401) {
    await clearAccessCode();
    // The app detects the cleared code and navigates to auth screen.
  }

  return response;
}
