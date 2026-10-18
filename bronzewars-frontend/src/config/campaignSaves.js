import { PLAYABLE_NATIONS, campaignStorageKey, loadCampaign, newCampaign } from './campaignRules.js';
import { LEGACY_HATTI_ID } from './nationIdentity.js';

export const CAMPAIGN_SAVE_PREFIX = 'bronzewars.campaign.save.';
const VALID_ID = /^[a-zA-Z0-9-]{1,80}$/;
const DELETED_PREFIX = 'bronzewars.campaign.deleted.';

export function campaignSaveKey(id) {
  if (typeof id !== 'string' || !VALID_ID.test(id)) throw new Error('Invalid campaign ID');
  return `${CAMPAIGN_SAVE_PREFIX}${id}`;
}

function validCampaign(campaign) {
  return loadCampaign({ getItem: () => JSON.stringify(campaign) }, campaign?.nation, { fallbackToNew: false });
}

export function readCampaignSave(storage, id) {
  try {
    const record = JSON.parse(storage.getItem(campaignSaveKey(id)));
    if (record?.saveVersion !== 1 || record.id !== id || !Number.isFinite(Date.parse(record.createdAt)) || !Number.isFinite(Date.parse(record.updatedAt))) return null;
    const campaign = validCampaign(record.campaign);
    return campaign ? { ...record, campaign } : null;
  } catch {
    return null;
  }
}

export function writeCampaignSave(storage, record, campaign, now = new Date().toISOString()) {
  if (storage.getItem(`${DELETED_PREFIX}${record.id}`) !== null) throw new Error('Campaign has been deleted');
  const validated = validCampaign(campaign);
  if (!validated || !Number.isFinite(Date.parse(now)) || !Number.isFinite(Date.parse(record.createdAt))) throw new Error('Invalid campaign save');
  const updated = { saveVersion: 1, id: record.id, createdAt: record.createdAt, updatedAt: now, campaign: validated };
  storage.setItem(campaignSaveKey(record.id), JSON.stringify(updated));
  return updated;
}

export function createCampaignSave(storage, nation, { makeId = () => crypto.randomUUID(), now = new Date().toISOString() } = {}) {
  if (!PLAYABLE_NATIONS.includes(nation)) throw new Error('Invalid campaign nation');
  const id = makeId();
  if (storage.getItem(campaignSaveKey(id)) !== null) throw new Error('Campaign ID already exists');
  return writeCampaignSave(storage, { id, createdAt: now }, newCampaign(nation), now);
}

export function deleteCampaignSave(storage, id) {
  const key = campaignSaveKey(id);
  const record = readCampaignSave(storage, id);
  if (!record) return false;
  // Keep a marker so opening the registry cannot import a deleted legacy game again.
  storage.setItem(`${DELETED_PREFIX}${id}`, '1');
  storage.removeItem(`${key}.before-strength-v2`);
  if (id === `legacy-${record.campaign.nation}`) {
    storage.removeItem(campaignStorageKey(record.campaign.nation));
    if (record.campaign.nation === 'hatti') storage.removeItem(campaignStorageKey(LEGACY_HATTI_ID));
  }
  storage.removeItem(key);
  return true;
}

// Old per-nation saves are imported once, retaining their original entries.
// Stable IDs make repeated visits and React remounts safe and idempotent.
export function importLegacyCampaigns(storage, now = new Date().toISOString()) {
  for (const nation of PLAYABLE_NATIONS) {
    const id = `legacy-${nation}`;
    if (storage.getItem(campaignSaveKey(id)) !== null || storage.getItem(`${DELETED_PREFIX}${id}`) !== null) continue;
    const campaign = loadCampaign(storage, nation, { fallbackToNew: false });
    if (campaign) writeCampaignSave(storage, { id, createdAt: now }, campaign, now);
  }
}

export function listCampaignSaves(storage) {
  const records = [];
  for (let index = 0; index < storage.length; index += 1) {
    const key = storage.key(index);
    if (!key?.startsWith(CAMPAIGN_SAVE_PREFIX)) continue;
    const id = key.slice(CAMPAIGN_SAVE_PREFIX.length);
    if (!VALID_ID.test(id)) continue;
    const record = readCampaignSave(storage, id);
    if (record) records.push(record);
  }
  return records.sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt) || a.id.localeCompare(b.id));
}
