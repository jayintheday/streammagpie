/** Parse yt-dlp `--progress-template` lines. */

export type ProgressEvent = {
  percent: number | null;
  speed: string | null;
  eta: string | null;
  filename: string | null;
};

const PCT = /\[download\]\s+(\d+(?:\.\d+)?)%/;
const SPEED = /at\s+(\S+)\s/;
const ETA = /ETA\s+(\S+)/;
const DEST = /Destination:\s+(.+)$/;
const TEMPLATE = /^progress\t(\d+(?:\.\d+)?)\t(\S*)\t(\S*)\t(.*)$/;

export function parseProgressLine(line: string): ProgressEvent | null {
  const templated = TEMPLATE.exec(line.trim());
  if (templated) {
    const percent = Number(templated[1]);
    return {
      percent: Number.isFinite(percent) ? percent : null,
      speed: emptyToNull(templated[2]),
      eta: emptyToNull(templated[3]),
      filename: emptyToNull(templated[4]),
    };
  }

  const dest = DEST.exec(line);
  if (dest?.[1]) {
    return { percent: null, speed: null, eta: null, filename: dest[1].trim() };
  }

  const pct = PCT.exec(line);
  if (!pct?.[1]) return null;
  const percent = Number(pct[1]);
  const speedM = SPEED.exec(line);
  const etaM = ETA.exec(line);
  return {
    percent: Number.isFinite(percent) ? percent : null,
    speed: speedM?.[1] ?? null,
    eta: etaM?.[1] ?? null,
    filename: null,
  };
}

function emptyToNull(s: string | undefined): string | null {
  if (s === undefined || s === '' || s === 'NA' || s === 'Unknown') return null;
  return s;
}
