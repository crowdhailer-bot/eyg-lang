// Resolve with `timedOut` unless the work settles first.
//
// The timer is cleared as soon as the work answers, so a run that finishes is
// never held open by the deadlines of requests that arrived in time.
export function deadline(work, delay, timedOut) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(timedOut), delay);
    work.then((value) => {
      clearTimeout(timer);
      resolve(value);
    });
  });
}
