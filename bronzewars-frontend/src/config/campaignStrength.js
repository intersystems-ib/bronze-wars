export function unitTroops(unit) {
  return (unit.strengths || []).reduce((sum, strength) => sum + strength, 0);
}

export function activeUnitCount(unit) {
  return unit.strengths ? unit.strengths.filter((strength) => strength > 0).length : unit.quantity;
}

export function armyTroops(army) {
  return army.units.reduce((sum, unit) => sum + unitTroops(unit), 0);
}

function changeStrength(units, rate, recovering) {
  const entries = units.flatMap((unit, group) => unit.strengths.map((strength, index) => ({
    group, index, weight: recovering ? unit.initialStrength - strength : strength,
  })));
  const total = entries.reduce((sum, entry) => sum + entry.weight, 0);
  const amount = Math.min(total, Math.max(0, Math.ceil(total * rate - 1e-9)));
  for (const entry of entries) {
    const share = total ? amount * entry.weight / total : 0;
    entry.change = Math.floor(share);
    entry.remainder = share - entry.change;
  }
  let extra = amount - entries.reduce((sum, entry) => sum + entry.change, 0);
  for (const entry of [...entries].sort((a, b) => b.remainder - a.remainder || a.group - b.group || a.index - b.index)) {
    if (extra <= 0) break;
    if (entry.change < entry.weight) { entry.change += 1; extra -= 1; }
  }
  const result = units.map((unit) => ({ ...unit, strengths: [...unit.strengths] }));
  for (const entry of entries) result[entry.group].strengths[entry.index] += (recovering ? 1 : -1) * entry.change;
  return { units: result, amount };
}

export function applyCasualties(units, rate) {
  const result = changeStrength(units, rate, false);
  return { units: result.units, losses: result.amount };
}

export function recoverCasualties(units, rate = 0.05) {
  const result = changeStrength(units, rate, true);
  return { units: result.units, recovered: result.amount };
}

export function migrateCampaignStrength(campaign, catalogue) {
  if (!catalogue.length || ![1, 2].includes(campaign.version)) return campaign;
  const profileKeys = { egypt: 'egyptian', hatti: 'hittite', nubia: 'nubian', seapeople: 'sea_peoples' };
  if (campaign.version === 2) {
    let changed = false;
    const armies = campaign.armies.map((army) => {
      const units = army.units.map((unit) => {
        const type = catalogue.find((candidate) => candidate.code === unit.code);
        const profile = { ...type, ...type?.profiles?.[profileKeys[army.designId]] };
        const missing = ['attack', 'defense', 'damage'].filter((field) => !Number.isFinite(unit[field]) && Number.isFinite(profile[field]));
        if (!missing.length) return unit;
        changed = true;
        return { ...unit, ...Object.fromEntries(missing.map((field) => [field, profile[field]])) };
      });
      if (army.morale === undefined) changed = true;
      return { ...army, morale: army.morale ?? 100, units };
    });
    return changed ? { ...campaign, armies } : campaign;
  }
  const armies = [];
  for (const army of campaign.armies) {
    const roster = army.initialUnits || army.units;
    const current = new Map(army.units.map((unit) => [unit.code, unit]));
    const units = [];
    for (const original of roster) {
      const type = catalogue.find((candidate) => candidate.code === original.code);
      const profile = { ...type, ...type?.profiles?.[profileKeys[army.designId]] };
      if (!Number.isInteger(profile.initialStrength) || profile.initialStrength <= 0) return campaign;
      const survivors = current.get(original.code);
      units.push({
        ...original, ...survivors, attack: profile.attack, defense: profile.defense, damage: profile.damage, quantity: original.quantity, initialStrength: profile.initialStrength,
        strengths: Array.from({ length: original.quantity }, (_, index) => index < (survivors?.quantity || 0) ? profile.initialStrength : 0),
      });
    }
    const { initialUnits, ...rest } = army;
    armies.push({ ...rest, morale: army.morale ?? 100, units });
  }
  // Old turn reports counted whole formations as casualties; do not relabel them as troops.
  const { lastTurnReport, ...rest } = campaign;
  return { ...rest, version: 2, armies };
}
