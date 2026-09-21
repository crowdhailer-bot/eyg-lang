/** Run real EYG in an isolated worker. Unknown effects and imports fail closed. */
export function runEyg(
  code,
  { effects = {}, context = {}, onEffect = () => {}, signal, timeout = 5000 } = {},
) {
  if (typeof code !== 'string' || code.length > 32_000)
    return Promise.reject(new Error('EYG source must be a string of at most 32,000 characters.'));
  if (signal?.aborted) return Promise.reject(new Error('Run cancelled.'));
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(new Blob([__WORKER_SOURCE__], { type: 'text/javascript' }));
    let worker;
    try {
      worker = new Worker(url);
    } catch (error) {
      URL.revokeObjectURL(url);
      reject(error);
      return;
    }
    let settled = false,
      pendingTrace;
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      if (error && pendingTrace) {
        try {
          onEffect({ ...pendingTrace, status: 'error', error: error.message });
        } catch {
          /* Observer failure must not prevent cleanup. */
        }
      }
      clearTimeout(timer);
      signal?.removeEventListener('abort', cancel);
      worker.terminate();
      URL.revokeObjectURL(url);
      error ? reject(error) : resolve(result);
    };
    const cancel = () => finish(new Error('Run cancelled.'));
    const timer = setTimeout(() => finish(new Error('EYG time limit exceeded.')), timeout);
    signal?.addEventListener('abort', cancel, { once: true });
    worker.onerror = (event) => {
      event.preventDefault();
      finish(
        new Error(
          event.message || 'Worker could not start. Check this page’s Content Security Policy.',
        ),
      );
    };
    worker.onmessage = async ({ data }) => {
      if (settled) return;
      try {
        if (JSON.stringify(data).length > 128_000)
          throw new Error('EYG result exceeds the output limit.');
        if (data.type === 'error') return finish(new Error(data.message));
        if (data.type === 'done') return finish(null, data.value);
        if (data.type !== 'effect') throw new Error('Invalid interpreter message.');
        const trace = { id: data.id, name: data.name, argument: data.argument };
        pendingTrace = trace;
        onEffect({ ...trace, status: 'running' });
        try {
          if (!Object.hasOwn(effects, data.name) || typeof effects[data.name] !== 'function')
            throw new Error(`Effect ${data.name} is not allowed.`);
          const result = await effects[data.name](data.argument);
          if (settled) return;
          if (JSON.stringify(result ?? {}).length > 128_000)
            throw new Error('Effect result exceeds the output limit.');
          pendingTrace = undefined;
          onEffect({ ...trace, status: 'done', result: result ?? {} });
          worker.postMessage({ type: 'resume', value: result ?? {} });
        } catch (error) {
          pendingTrace = undefined;
          if (!settled) onEffect({ ...trace, status: 'error', error: error.message });
          throw error;
        }
      } catch (error) {
        finish(error);
      }
    };
    try {
      worker.postMessage({ type: 'start', code, context });
    } catch (error) {
      finish(error);
    }
  });
}
