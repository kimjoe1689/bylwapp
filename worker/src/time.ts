const RFC3339 =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-])(\d{2}):(\d{2}))$/;

export function parseRFC3339(raw: string): Date | null {
  const match = RFC3339.exec(raw);
  if (!match) {
    return null;
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  const frac = match[7] ? Number(`0.${match[7]}`) : 0;
  const millis = Math.round(frac * 1000);
  let offsetMin = 0;
  if (match[8] !== "Z") {
    const sign = match[9] === "+" ? 1 : -1;
    offsetMin = sign * (Number(match[10]) * 60 + Number(match[11]));
  }
  if (Math.abs(offsetMin) > 14 * 60) {
    return null;
  }
  const utc = Date.UTC(year, month - 1, day, hour, minute, second, millis) - offsetMin * 60_000;
  const wall = new Date(utc + offsetMin * 60_000);
  if (
    wall.getUTCFullYear() !== year ||
    wall.getUTCMonth() !== month - 1 ||
    wall.getUTCDate() !== day ||
    wall.getUTCHours() !== hour ||
    wall.getUTCMinutes() !== minute ||
    wall.getUTCSeconds() !== second
  ) {
    return null;
  }
  return new Date(utc);
}

export function formatRFC3339(date: Date): string {
  return date.toISOString().slice(0, 19) + "Z";
}

export function formatRFC3339Nano(date: Date): string {
  const iso = date.toISOString();
  const frac = iso.slice(20, 23).replace(/0+$/, "");
  const head = iso.slice(0, 19);
  return frac ? `${head}.${frac}Z` : `${head}Z`;
}

export function nowNano(date = new Date()): string {
  return formatRFC3339Nano(date);
}

export function parseGoTime(raw: string): Date | null {
  return parseRFC3339(raw);
}

const DURATION =
  /[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:ns|us|µs|μs|ms|s|m|h)/g;

const UNIT_MS: Record<string, number> = {
  ns: 1e-6,
  us: 1e-3,
  µs: 1e-3,
  μs: 1e-3,
  ms: 1,
  s: 1000,
  m: 60_000,
  h: 3_600_000,
};

// time.ParseDuration subset used by BYLW_STALE_AFTER / STALE_AFTER.
export function parseDuration(raw: string): number | null {
  const text = raw.trim();
  if (!text) {
    return null;
  }
  const parts = text.match(DURATION);
  if (!parts || parts.join("") !== text) {
    return null;
  }
  let total = 0;
  for (const part of parts) {
    const split = /^(.*?)(ns|us|µs|μs|ms|s|m|h)$/.exec(part);
    if (!split) {
      return null;
    }
    const unit = UNIT_MS[split[2]];
    total += Number(split[1]) * unit;
  }
  if (!Number.isFinite(total) || total < 0) {
    return null;
  }
  return total;
}

export const DEFAULT_STALE_MS = 15 * 60 * 1000;
