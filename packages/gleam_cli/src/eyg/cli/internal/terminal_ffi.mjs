export function isTty() {
  return Boolean(process.stdout.isTTY) && !process.env.NO_COLOR;
}

let interrupted = false;
const onInterrupt = () => {
  interrupted = true;
};

// While a turn runs Ctrl-C stops the turn rather than the process.
export function startTurn() {
  interrupted = false;
  process.on("SIGINT", onInterrupt);
}

export function endTurn() {
  process.off("SIGINT", onInterrupt);
}

export function isInterrupted() {
  return interrupted;
}
