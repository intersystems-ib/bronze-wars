import { useEffect, useRef, useState } from 'react';
import { getArmyDesign } from '../config/armyDesigns';
import { SEASONS } from '../config/campaignRules';
import { useI18n } from '../i18n/I18nContext';

export default function CampaignStart({ onNew, onLoad }) {
  const { t } = useI18n();
  return <main className="start-page campaign-start-page">
    <section className="start-card panel">
      <p className="eyebrow">{t('app.subtitle')}</p>
      <h1>{t('app.title')}</h1>
      <p className="lede">{t('campaign.startHelp')}</p>
      <div className="campaign-start-options">
        <button className="campaign-start-option" type="button" onClick={onNew}>
          <span aria-hidden="true">⚑</span><strong>{t('campaign.newCampaign')}</strong><small>{t('campaign.newCampaignHelp')}</small>
        </button>
        <button className="campaign-start-option" type="button" onClick={onLoad}>
          <span aria-hidden="true">☷</span><strong>{t('campaign.loadCampaign')}</strong><small>{t('campaign.loadCampaignHelp')}</small>
        </button>
      </div>
    </section>
  </main>;
}

function DeleteCampaignDialog({ save, onCancel, onConfirm }) {
  const { t } = useI18n();
  const dialog = useRef(null);
  useEffect(() => {
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);
  return <dialog ref={dialog} className="campaign-delete-dialog panel" aria-labelledby="delete-campaign-title" aria-describedby="delete-campaign-description" onCancel={(event) => { event.preventDefault(); onCancel(); }}>
    <h2 id="delete-campaign-title">{t('campaign.deleteTitle')}</h2>
    <p id="delete-campaign-description">{t('campaign.deleteHelp', { id: save.id, nation: t(`campaign.nations.${save.campaign.nation}`) })}</p>
    <div className="campaign-modal-actions">
      <button className="button button--secondary" type="button" onClick={onCancel}>{t('campaign.cancel')}</button>
      <button className="button button--primary" type="button" onClick={onConfirm}>{t('campaign.confirmDelete')}</button>
    </div>
  </dialog>;
}

export function CampaignSaveList({ saves, error, onLoad, onDelete, onBack }) {
  const { t } = useI18n();
  const [deleting, setDeleting] = useState(null);
  return <main className="start-page campaign-load-page">
    <section className="start-card panel">
      <p className="eyebrow">{t('navigation.campaigns')}</p>
      <h1>{t('campaign.loadCampaign')}</h1>
      <p className="lede">{t('campaign.saveListHelp')}</p>
      {error && <p className="error-banner" role="alert">{t(error)}</p>}
      {!saves.length ? <p className="campaign-muted">{t('campaign.noSaves')}</p> : <div className="campaign-save-table-wrap">
        <table className="campaign-save-table">
          <thead><tr><th scope="col">{t('campaign.saveId')}</th><th scope="col">{t('campaign.nation')}</th><th scope="col">{t('campaign.saveTurn')}</th><th scope="col"><span className="campaign-visually-hidden">{t('campaign.loadAction')}</span></th></tr></thead>
          <tbody>{saves.map((save) => {
            const year = 1300 - Math.floor(save.campaign.turn / SEASONS.length);
            const date = year > 0 ? t('campaign.yearBC', { year }) : t('campaign.yearAD', { year: 1 - year });
            const nation = t(`campaign.nations.${save.campaign.nation}`);
            return <tr key={save.id}>
              <td><code>{save.id}</code></td>
              <td><span className="campaign-save-nation"><img src={getArmyDesign(save.campaign.nation).logo} alt="" />{nation}</span></td>
              <td><strong>{date}</strong><small>{t(`campaign.seasons.${SEASONS[save.campaign.turn % SEASONS.length]}`)}</small></td>
              <td><div className="campaign-save-actions"><button className="button button--secondary" type="button" aria-label={t('campaign.loadSave', { id: save.id })} onClick={() => onLoad(save.id)}>{t('campaign.loadAction')}</button><button className="button button--ghost" type="button" aria-label={t('campaign.deleteSave', { id: save.id })} onClick={() => setDeleting(save)}>{t('campaign.deleteAction')}</button></div></td>
            </tr>;
          })}</tbody>
        </table>
      </div>}
      <button className="button button--ghost" type="button" onClick={onBack}>← {t('campaign.home')}</button>
      {deleting && <DeleteCampaignDialog save={deleting} onCancel={() => setDeleting(null)} onConfirm={() => { onDelete(deleting.id); setDeleting(null); }} />}
    </section>
  </main>;
}
