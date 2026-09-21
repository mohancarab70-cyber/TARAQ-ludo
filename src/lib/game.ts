export const POWER_BY_ROLL: Record<number, number> = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 5, 6: 10 };

export function dicePower(roll: number) {
  return POWER_BY_ROLL[roll] ?? 0;
}

export function cappedPoints(points: number) {
  return Math.min(20, Math.max(0, points));
}

export function canLock(power: number, targetPoints: number) {
  return power > targetPoints;
}
