import { initialGrain, PLAYABLE_NATIONS, SEASONS, availableGrain, armyTroops, campaignUpkeep, campaignProduction, deploymentHexes, recruitArmy } from './campaignRules.js';
import { campaignView } from './campaignVisibility.js';
import { HEX_BY_ID, campaignTerritory, occupiedRegions } from './campaignRules.js';
import { MIN_ARMY_DIVISIONS, minimumArmyCost } from './armyRules.js';
import { campaignCapital } from './campaignCityActions.js';

export function automaticRecruitmentDecision(capacity) {
  const reason = capacity.nation === 'seapeople' && !capacity.capitalCityId ? 'NO_CAPITAL'
    : capacity.annualProduction + 1e-9 < capacity.annualConsumption ? 'PRODUCTION_DEFICIT'
    : capacity.reserve < capacity.minimumArmyCost ? 'INSUFFICIENT_GRAIN' : null;
  return reason ? { action: 'wait', reason, source: 'RULES', blockReason: reason } : null;
}

export function rivalNations(campaign) {
  const activeSeaPeoples = campaign.seaPeoples?.invasionCount > 0 || campaign.armies.some((army) => army.designId === 'seapeople')
    || Object.values(campaign.cityOwners || {}).includes('seapeople');
  return [...PLAYABLE_NATIONS, ...(activeSeaPeoples ? ['seapeople'] : [])].filter((nation) => nation !== (campaign.nation || 'egypt'));
}

export function needsRecruitmentDecision(campaign, nation) {
  const entry = campaign.aiRecruitment?.[nation];
  return entry?.turn !== campaign.turn || (entry.action === 'wait' && entry.source !== 'SKIPPED' && entry.deploymentRuleVersion !== 3);
}

export function initializeCampaignAI(campaign) {
  const foreignGrain = { ...campaign.foreignGrain };
  for (const nation of rivalNations(campaign)) foreignGrain[nation] ??= initialGrain(nation);
  const aiRecruitment = { ...campaign.aiRecruitment };
  for (const nation of rivalNations(campaign)) if (needsRecruitmentDecision(campaign, nation)) delete aiRecruitment[nation];
  return { ...campaign, foreignGrain, aiRecruitment };
}

// Bounded knapsack: maximize actual troop strength, not the formation count.
// Binary groups keep the calculation small even after years of saving grain.
export function maxRecruitableTroops(catalogue, budget) {
  const cap = Math.min(Math.max(0, Math.floor(budget + 1e-9)), catalogue.reduce((sum, unit) => sum + unit.grainCost * 99, 0));
  const best = new Float64Array(cap + 1);
  for (const unit of catalogue) {
    let remaining = 99;
    for (let group = 1; remaining > 0; group *= 2) {
      const count = Math.min(group, remaining);
      const cost = count * unit.grainCost;
      for (let grain = cap; grain >= cost; grain -= 1) best[grain] = Math.max(best[grain], best[grain - cost] + count * unit.initialStrength);
      remaining -= count;
    }
  }
  return best[cap];
}

export function recruitmentCapacity(campaign, nation, catalogue) {
  const reserve = availableGrain(campaign.foreignGrain?.[nation] ?? initialGrain(nation));
  const armies = campaign.armies.filter((army) => army.designId === nation);
  const consumption = campaignUpkeep({ ...campaign, nation });
  const production = campaignProduction(campaign, nation);
  const sustainableBudget = Math.max(0, (production / SEASONS.length - consumption) / 0.1);
  const freeHexes = deploymentHexes({ ...campaign, nation });
  const capital = campaignCapital(campaign, nation);
  const capitalHexId = freeHexes[0]?.id;
  const visibleInvaders = campaignView(campaign, nation).armies.filter((army) => !army.own && campaignTerritory(campaign, HEX_BY_ID.get(army.hexId)) === nation).length;
  return {
    nation, turn: campaign.turn, season: SEASONS[campaign.turn % 3], turnsToHarvest: 3 - campaign.turn % 3,
    reserve, annualProduction: production, consumptionPerTurn: consumption, annualConsumption: consumption * 3,
    minimumDivisions: MIN_ARMY_DIVISIONS, minimumArmyCost: minimumArmyCost(catalogue),
    armyCount: armies.length, troops: armies.reduce((sum, army) => sum + armyTroops(army), 0),
    situation: reserve <= 0 ? 'famine' : production > consumption * 3 ? 'abundance' : 'scarcity',
    capitalAvailable: Boolean(capitalHexId),
    capitalCityId: capital?.id ?? null, capitalHexId: capital?.hexId ?? null,
    deploymentArea: 'capital_region', freeDeploymentHexes: freeHexes.length,
    visibleInvaders, occupiedRegions: occupiedRegions(campaign, nation), depletedArmyCount: armies.filter((army) => armyTroops(army) < army.units.reduce((sum, unit) => sum + unit.quantity * unit.initialStrength, 0)).length,
    maxAffordableTroops: capitalHexId ? maxRecruitableTroops(catalogue, reserve) : 0,
    maxSustainableTroops: capitalHexId ? maxRecruitableTroops(catalogue, Math.min(reserve, sustainableBudget)) : 0,
    options: capitalHexId ? ['small', 'balanced', 'large', 'raid', 'invasion'].map((id, index) => {
      const codes = id === 'raid' ? ['LIGHT_CAVALRY', 'CHARIOTS', 'LIGHT_INFANTRY', 'ARCHERS']
        : id === 'invasion' ? ['SPEARMEN', 'HEAVY_INFANTRY', 'ARCHERS', 'LIGHT_INFANTRY'] : ['SPEARMEN', 'LIGHT_INFANTRY', 'ARCHERS'];
      const core = codes.map((code) => catalogue.find((unit) => unit.code === code && (id !== 'raid' || unit.speed >= 2))).filter(Boolean);
      const cheapest = [...core].sort((a, b) => a.grainCost - b.grainCost)[0];
      if (!cheapest || cheapest.grainCost * MIN_ARMY_DIVISIONS > reserve) return null;
      let cost = cheapest.grainCost * MIN_ARMY_DIVISIONS, troops = cheapest.initialStrength * MIN_ARMY_DIVISIONS, added = true;
      const budget = Math.min(reserve, Math.max(cost, Math.floor(reserve * [0.25, 0.5, 0.75, 0.5, 0.75][index])));
      const quantities = { [cheapest.code]: MIN_ARMY_DIVISIONS };
      while (added) {
        added = false;
        for (const unit of core) if (cost + unit.grainCost <= budget && (quantities[unit.code] || 0) < 99) {
          quantities[unit.code] = (quantities[unit.code] || 0) + 1;
          cost += unit.grainCost;
          troops += unit.initialStrength;
          added = true;
        }
      }
      return { id, purpose: id === 'raid' ? 'RAID' : id === 'invasion' ? 'CONQUER' : 'GENERAL', quantities, cost, troops, consumptionPerTurn: Math.round(cost * 10) / 100,
        reserveAfterRecruitment: reserve - cost, annualConsumptionAfterRecruitment: Math.round((consumption + cost * 0.1) * 300) / 100 };
    }).filter(Boolean) : [],
    units: catalogue.map((unit) => ({ code: unit.code, troops: unit.initialStrength, cost: unit.grainCost,
      consumptionPerTurn: unit.grainCost / 10, maxAffordable: capitalHexId ? Math.min(99, Math.floor(reserve / unit.grainCost)) : 0 })),
  };
}

export function applyRecruitmentDecision(campaign, nation, decision, catalogue, { language = 'es' } = {}) {
  if (!rivalNations(campaign).includes(nation) || !needsRecruitmentDecision(campaign, nation)) return campaign;
  if (!decision || !['recruit', 'wait'].includes(decision.action) || typeof decision.reason !== 'string') throw new Error('INVALID_AI_DECISION');
  let next = campaign;
  if (decision.action === 'recruit') {
    if (automaticRecruitmentDecision(recruitmentCapacity(campaign, nation, catalogue))) throw new Error('AI_RECRUITMENT_BLOCKED');
    const quantities = decision.quantities;
    if (!quantities || Array.isArray(quantities) || typeof quantities !== 'object' || !Object.keys(quantities).length
      || Object.entries(quantities).some(([code, count]) => !catalogue.some((unit) => unit.code === code) || !Number.isInteger(count) || count < 1 || count > 99)) throw new Error('INVALID_AI_COMPOSITION');
    if (Object.values(quantities).reduce((sum, count) => sum + count, 0) < MIN_ARMY_DIVISIONS) throw new Error('AI_ARMY_TOO_SMALL');
    const recruited = recruitArmy({ ...campaign, nation, grain: campaign.foreignGrain[nation] }, {
      language, designId: nation, quantities,
    }, catalogue);
    if (recruited.armies.length === campaign.armies.length) throw new Error('UNAFFORDABLE_AI_ARMY');
    const purpose = decision.optionId === 'raid' ? 'RAID' : decision.optionId === 'invasion' ? 'CONQUER' : null;
    next = { ...campaign, armies: recruited.armies.map((army) => army.id === recruited.nextArmyId - 1 && purpose ? { ...army, campaignMission: { intent: purpose } } : army), nextArmyId: recruited.nextArmyId,
      foreignGrain: { ...campaign.foreignGrain, [nation]: recruited.grain } };
  }
  return { ...next, aiRecruitment: { ...next.aiRecruitment, [nation]: {
    turn: campaign.turn, action: decision.action, reason: decision.reason.slice(0, 500), source: decision.action === 'wait' && ['SKIPPED', 'RULES'].includes(decision.source) ? decision.source : 'LLM', deploymentRuleVersion: 3,
    ...(decision.blockReason ? { blockReason: decision.blockReason } : {}),
    ...(decision.action === 'recruit' ? { armyId: next.nextArmyId - 1 } : {}),
  } } };
}
