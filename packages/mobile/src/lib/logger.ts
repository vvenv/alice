type LogLevel = "debug" | "info" | "warn" | "error";

interface Logger {
  debug: (...args: unknown[]) => void;
  info: (...args: unknown[]) => void;
  warn: (...args: unknown[]) => void;
  error: (...args: unknown[]) => void;
}

/**
 * Create a namespaced logger.
 *
 * In production (`__DEV__ === false`), `debug` and `info` are no-ops.
 * `warn` and `error` always log.
 */
export function createLogger(namespace: string): Logger {
  const prefix = `[${namespace}]`;

  return {
    debug: __DEV__
      ? (...args: unknown[]) => console.debug(prefix, ...args)
      : () => {},

    info: __DEV__
      ? (...args: unknown[]) => console.log(prefix, ...args)
      : () => {},

    warn: (...args: unknown[]) => console.warn(prefix, ...args),

    error: (...args: unknown[]) => console.error(prefix, ...args),
  };
}
