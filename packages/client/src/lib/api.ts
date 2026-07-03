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
