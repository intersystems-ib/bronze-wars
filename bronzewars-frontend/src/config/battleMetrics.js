export function armySurrenderMetrics(army) {
  const units = army?.units || [];
  // The catalogue maximum includes wounds suffered before this battle.
  const initialSoldiers = units.reduce((total, unit) => (
    total + Math.max(0, Number(unit.type?.initialStrength) || Number(unit.currentStrength) || 0)
  ), 0);
  const activeUnits = units.filter((unit) => unit.active !== false && unit.active !== 0 && Number(unit.currentStrength) > 0);
  const survivingSoldiers = activeUnits.reduce(
    (total, unit) => total + Math.max(0, Number(unit.currentStrength) || 0), 0,
  );
  const totalMorale = activeUnits.reduce(
    (total, unit) => total + (Math.max(0, Number(unit.morale ?? 100)) * Math.max(0, Number(unit.currentStrength) || 0)), 0,
  );
  return {
    troopPercentage: initialSoldiers > 0 ? Math.min(100, (survivingSoldiers / initialSoldiers) * 100) : 0,
    moralePercentage: initialSoldiers > 0 ? Math.min(100, totalMorale / initialSoldiers) : 0,
  };
}
