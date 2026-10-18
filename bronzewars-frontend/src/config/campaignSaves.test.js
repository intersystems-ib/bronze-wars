import assert from 'node:assert/strict';
import { test } from 'node:test';
import { campaignStorageKey, nextSeason, recruitArmy, moveArmy, reachableHexes } from './campaignRules.js';
import { LEGACY_HATTI_ID } from './nationIdentity.js';
import { CAMPAIGN_SAVE_PREFIX, campaignSaveKey, createCampaignSave, readCampaignSave, writeCampaignSave, deleteCampaignSave, listCampaignSaves, importLegacyCampaigns } from './campaignSaves.js';

function memoryStorage() {
  const values = new Map();
  return { get length() { return values.size; }, key: (index) => [...values.keys()][index] ?? null,
    getItem: (key) => values.get(key) ?? null, setItem: (key, value) => values.set(key, value), removeItem: (key) => values.delete(key) };
}
const firstDate = '2026-10-18T10:00:00.000Z';
const laterDate = '2026-10-18T11:00:00.000Z';
const catalogue = [{ code: 'LIGHT_INFANTRY', initialStrength: 60, speed: 2, grainCost: 6, attack: 4, defense: 2, damage: 5 }];
const create = (storage, id, nation = 'egypt') => createCampaignSave(storage, nation, { makeId: () => id, now: firstDate });

test('deleting one campaign removes its save and backup, preserving all other games and preventing stale autosaves', () => {
  const storage = memoryStorage();
  const removed = create(storage, 'remove');
  const retained = create(storage, 'retain');
  storage.setItem(`${campaignSaveKey('remove')}.before-strength-v2`, JSON.stringify(removed.campaign));
  assert.equal(deleteCampaignSave(storage, 'remove'), true);
  assert.equal(readCampaignSave(storage, 'remove'), null);
  assert.equal(storage.getItem(`${campaignSaveKey('remove')}.before-strength-v2`), null);
  assert.deepEqual(readCampaignSave(storage, 'retain'), retained);
  assert.deepEqual(listCampaignSaves(storage).map((save) => save.id), ['retain']);
  assert.throws(() => writeCampaignSave(storage, removed, removed.campaign), /deleted/);
  assert.equal(deleteCampaignSave(storage, 'remove'), false);
  assert.throws(() => deleteCampaignSave(storage, '../invalid'));
});

test('deleted legacy campaigns cannot reappear when reopening the registry, including old Hatti identities', () => {
  for (const nation of ['egypt', 'hatti', 'nubia']) {
    const storage = memoryStorage();
    const record = create(storage, 'original', nation);
    const source = nation === 'hatti' ? LEGACY_HATTI_ID : nation;
    storage.setItem(campaignStorageKey(source), JSON.stringify({ ...record.campaign, nation: source }));
    importLegacyCampaigns(storage, firstDate);
    assert.equal(deleteCampaignSave(storage, `legacy-${nation}`), true);
    assert.equal(storage.getItem(campaignStorageKey(source)), null);
    // Even an old source later restored by another browser tab must not be reimported.
    storage.setItem(campaignStorageKey(source), JSON.stringify({ ...record.campaign, nation: source }));
    importLegacyCampaigns(storage, laterDate);
    assert.equal(readCampaignSave(storage, `legacy-${nation}`), null);
    assert.deepEqual(listCampaignSaves(storage).map((save) => save.id), ['original']);
  }
});

test('new campaigns start from zero with separate IDs and do not reset existing games of the same nation', () => {
  const storage = memoryStorage();
  const first = create(storage, 'first');
  const advanced = nextSeason(nextSeason(first.campaign));
  writeCampaignSave(storage, first, advanced, laterDate);
  const second = create(storage, 'second');
  assert.equal(second.campaign.turn, 0);
  assert.equal(second.campaign.grain, 100);
  assert.deepEqual(second.campaign.armies, []);
  assert.equal(second.campaign.nextArmyId, 1);
  assert.equal(readCampaignSave(storage, 'first').campaign.turn, 2);
  assert.equal(readCampaignSave(storage, 'second').campaign.turn, 0);
  assert.equal(listCampaignSaves(storage).length, 2);
});

test('loading restores troops, position, movement, morale, grain and last-turn report exactly', () => {
  const storage = memoryStorage();
  const record = create(storage, 'full-state');
  let state = recruitArmy(record.campaign, { name: 'Guard', designId: 'egypt', quantities: { LIGHT_INFANTRY: 4 } }, catalogue);
  state = nextSeason(state);
  state = moveArmy(state, 1, reachableHexes(state, 1).keys().next().value);
  state.armies[0].morale = 77;
  state.armies[0].units[0].strengths = [44, 12, 0, 0];
  const saved = writeCampaignSave(storage, record, state, laterDate);
  assert.deepEqual(readCampaignSave(storage, record.id), saved);
  assert.equal(saved.createdAt, firstDate);
  assert.equal(saved.updatedAt, laterDate);
  assert.equal(saved.id, record.id);
});

test('the registry orders saved games by their last update and exposes turn, nation and ID', () => {
  const storage = memoryStorage();
  const records = ['egypt', 'hatti', 'nubia'].map((nation) => create(storage, `game-${nation}`, nation));
  writeCampaignSave(storage, records[1], { ...records[1].campaign, turn: 4 }, laterDate);
  const saves = listCampaignSaves(storage);
  assert.equal(saves[0].id, 'game-hatti');
  assert.equal(saves[0].campaign.nation, 'hatti');
  assert.equal(saves[0].campaign.turn, 4);
  assert.equal(1300 - Math.floor(saves[0].campaign.turn / 3), 1299);
  assert.equal(saves[0].campaign.turn % 3, 1);
});

test('old per-nation campaigns are imported once and source entries are kept as backups', () => {
  const storage = memoryStorage();
  const base = create(storage, 'existing');
  const old = { ...base.campaign, turn: 7, grain: 28, nation: LEGACY_HATTI_ID };
  storage.setItem(campaignStorageKey(LEGACY_HATTI_ID), JSON.stringify(old));
  storage.setItem(campaignStorageKey('egypt'), JSON.stringify({ ...base.campaign, turn: 2 }));
  importLegacyCampaigns(storage, firstDate);
  const imported = readCampaignSave(storage, 'legacy-hatti');
  assert.equal(imported.campaign.nation, 'hatti');
  assert.equal(imported.campaign.turn, 7);
  assert.equal(imported.campaign.grain, 28);
  writeCampaignSave(storage, imported, nextSeason(imported.campaign), laterDate);
  importLegacyCampaigns(storage, laterDate);
  assert.equal(readCampaignSave(storage, 'legacy-hatti').campaign.turn, 8);
  assert.equal(listCampaignSaves(storage).length, 3);
  assert.equal(storage.getItem(campaignStorageKey(LEGACY_HATTI_ID)), JSON.stringify(old));
});

test('invalid or unrelated entries and migration backups never appear as new empty games', () => {
  const storage = memoryStorage();
  const record = create(storage, 'valid');
  storage.setItem(`${CAMPAIGN_SAVE_PREFIX}broken`, '{broken');
  storage.setItem(`${CAMPAIGN_SAVE_PREFIX}invalid`, JSON.stringify({ ...record, id: 'invalid', campaign: { ...record.campaign, turn: -1 } }));
  storage.setItem(`${CAMPAIGN_SAVE_PREFIX}mismatched`, JSON.stringify(record));
  storage.setItem(`${CAMPAIGN_SAVE_PREFIX}valid.before-strength-v2`, JSON.stringify(record.campaign));
  storage.setItem(campaignStorageKey('nubia'), '{broken');
  storage.setItem('bronzewars.battle-design.4', 'hatti');
  importLegacyCampaigns(storage, firstDate);
  assert.deepEqual(listCampaignSaves(storage).map((save) => save.id), ['valid']);
  assert.equal(readCampaignSave(storage, 'missing'), null);
  assert.equal(readCampaignSave(storage, 'broken'), null);
  assert.equal(readCampaignSave(storage, 'invalid'), null);
});

test('duplicate IDs and invalid state are rejected without replacing a valid save', () => {
  const storage = memoryStorage();
  const record = create(storage, 'same-id');
  const before = storage.getItem(campaignSaveKey(record.id));
  assert.throws(() => create(storage, 'same-id', 'nubia'));
  assert.throws(() => writeCampaignSave(storage, record, { ...record.campaign, armies: [{}] }));
  assert.throws(() => campaignSaveKey(undefined));
  assert.throws(() => create(storage, 'bad.id'));
  assert.throws(() => create(storage, 'sea', 'seapeople'));
  assert.equal(storage.getItem(campaignSaveKey(record.id)), before);
});

test('storage failure does not overwrite other saves and a load failure does not create a game', () => {
  const storage = memoryStorage();
  const record = create(storage, 'protected');
  const failing = { ...storage, setItem() { throw new Error('Quota exceeded'); } };
  assert.throws(() => writeCampaignSave(failing, record, nextSeason(record.campaign)));
  assert.deepEqual(readCampaignSave(storage, record.id), record);
  assert.equal(readCampaignSave({ getItem() { throw new Error('Blocked'); } }, record.id), null);
});
