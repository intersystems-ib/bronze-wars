import { useEffect, useRef } from 'react';
import { armyTroops, activeUnitCount } from '../config/campaignRules';
import { useI18n } from '../i18n/I18nContext';

export default function CampaignMergeDialog({ source, target, combined, onCancel, onConfirm }) {
  const { t } = useI18n();
  const dialog = useRef(null);
  useEffect(() => {
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);
  const name = (army) => army.name || t('campaign.defaultArmyName', { number: army.id });
  return <dialog ref={dialog} className="campaign-merge-dialog panel" aria-labelledby="merge-army-title" aria-describedby="merge-army-description" onCancel={(event) => { event.preventDefault(); onCancel(); }}>
    <h2 id="merge-army-title">{t('campaign.merge.title')}</h2>
    <p id="merge-army-description">{t('campaign.merge.question', { source: name(source), target: name(target) })}</p>
    {combined && <p>{t('campaign.merge.summary', { troops: armyTroops(combined), divisions: combined.units.reduce((sum, unit) => sum + activeUnitCount(unit), 0), morale: combined.morale })}</p>}
    <p>{t('campaign.merge.movement')}</p>
    <div className="campaign-modal-actions">
      <button className="button button--secondary" type="button" onClick={onCancel}>{t('campaign.cancel')}</button>
      <button className="button button--primary" type="button" onClick={onConfirm} disabled={!combined}>{t('campaign.merge.confirm')}</button>
    </div>
  </dialog>;
}
