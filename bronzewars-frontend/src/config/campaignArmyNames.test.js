import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CAMPAIGN_ARMY_NAMES, randomArmyName } from './campaignArmyNames.js';
import { newCampaign, recruitArmy, loadCampaign } from './campaignRules.js';
import { initializeCampaignAI, applyRecruitmentDecision } from './campaignAI.js';

const catalogue = [{ code: 'LIGHT_INFANTRY', initialStrength: 60, speed: 2, grainCost: 6, attack: 4, defense: 2, damage: 5 }];
const input = (nation, name, language = 'es') => ({ name, language, designId: nation, quantities: { LIGHT_INFANTRY: 4 } });

test('random selection uses the national repertoire and supports Spanish and English', () => {
  for (const [nation, entries] of Object.entries(CAMPAIGN_ARMY_NAMES)) {
    assert.equal(randomArmyName(nation, [], { random: () => 0 }), `Ejército de ${entries[0].es}`);
    assert.equal(randomArmyName(nation, [], { language: 'en', random: () => 0.999 }), `Army of ${entries.at(-1).en}`);
  }
});

test('names avoid deployed duplicates across languages and use suffixes after exhausting the repertoire', () => {
  const armies = CAMPAIGN_ARMY_NAMES.egypt.map((entry) => ({ designId: 'egypt', name: `Ejército de ${entry.es}` }));
  assert.equal(randomArmyName('egypt', armies, { language: 'en', random: () => 0 }), 'Army of Ra (2)');
  armies.push({ designId: 'egypt', name: 'Army of Ra (2)' });
  assert.equal(randomArmyName('egypt', armies, { random: () => 0 }), 'Ejército de Ramsés (2)');
  assert.equal(randomArmyName('nubia', armies, { random: () => 0 }), 'Ejército de Apedemak');
});

test('recruitment persists automatic names and preserves custom names and existing saves', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    const state = recruitArmy(newCampaign(nation), input(nation, '  '), catalogue);
    const name = state.armies[0].name;
    assert.ok(CAMPAIGN_ARMY_NAMES[nation].some((entry) => name === `Ejército de ${entry.es}`));
    assert.equal(loadCampaign({ getItem: () => JSON.stringify(state) }, nation).armies[0].name, name);
    const custom = recruitArmy(newCampaign(nation), input(nation, '  Guardia real  '), catalogue);
    assert.equal(custom.armies[0].name, 'Guardia real');
    const english = recruitArmy(newCampaign(nation), input(nation, '', 'en'), catalogue);
    assert.ok(english.armies[0].name.startsWith('Army of '));
  }
});

test('AI recruits automatically receive a saved national name in the selected language', () => {
  for (const nation of ['hatti', 'nubia']) {
    const state = initializeCampaignAI(newCampaign());
    const next = applyRecruitmentDecision(state, nation, { action: 'recruit', quantities: { LIGHT_INFANTRY: 4 }, reason: 'Defence' }, catalogue, { language: 'en' });
    assert.ok(CAMPAIGN_ARMY_NAMES[nation].some((entry) => next.armies[0].name === `Army of ${entry.en}`));
    assert.equal(loadCampaign({ getItem: () => JSON.stringify(next) }).armies[0].name, next.armies[0].name);
  }
});
