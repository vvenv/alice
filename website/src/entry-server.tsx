import { StrictMode } from "react";
import { renderToString } from "react-dom/server";
import App from "./App";

/** Must render the same tree as main.tsx so hydrateRoot matches. */
export function render() {
  return renderToString(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
