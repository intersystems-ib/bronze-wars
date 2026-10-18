import { campaignEconomy, terrainAttrition, occupationGarrison, HEX_BY_ID, SUPPLY_ATTRITION_RATE, RECOVERY_RATE } from './campaignRules.js';
import { ASSAULT_LOSS_RATE } from './campaignCityActions.js';

export function campaignModifiers(campaign, army) {
  const { situation } = campaignEconomy(campaign);
  const modifiers = [];
  const add = (kind, rate) => { if (rate) modifiers.push({ kind, value: Math.round(rate * 100) }); };
  if (army) add('terrain', -terrainAttrition(campaign, HEX_BY_ID.get(army.hexId), army.designId));
  if (situation === 'famine') add('supply', -SUPPLY_ATTRITION_RATE);
  if (army?.cityAction?.type === 'assault') add('assault', -ASSAULT_LOSS_RATE);
  else if (situation === 'abundance' && (!army || !occupationGarrison(campaign, army))) add('recovery', RECOVERY_RATE);
  return modifiers.length ? modifiers : [{ kind: 'none', value: 0 }];
}
