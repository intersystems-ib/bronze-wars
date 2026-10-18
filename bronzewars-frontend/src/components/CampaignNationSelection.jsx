import { useState } from 'react';
import { ARMY_DESIGNS } from '../config/armyDesigns';
import { PLAYABLE_NATIONS } from '../config/campaignRules';
import { useI18n } from '../i18n/I18nContext';
import UnitArtwork from './UnitArtwork';

export default function CampaignNationSelection({ onStart, onBack, error }) {
  const { t } = useI18n();
  const [selected, setSelected] = useState('egypt');
  return <main className="start-page campaign-nation-page">
    <section className="start-card panel">
      <p className="eyebrow">{t('navigation.campaigns')}</p>
      <h1>{t('campaign.chooseNation')}</h1>
      <p className="lede">{t('campaign.chooseNationHelp')}</p>
      {error && <p className="error-banner" role="alert">{t(error)}</p>}
      <div className="campaign-nation-grid" role="group" aria-label={t('campaign.nation')}>
        {ARMY_DESIGNS.filter((design) => PLAYABLE_NATIONS.includes(design.id)).map((design) => <button key={design.id} className={`campaign-nation-card ${selected === design.id ? 'is-selected' : ''}`} type="button" aria-pressed={selected === design.id} onClick={() => setSelected(design.id)}>
          <img className="campaign-nation-logo" src={design.logo} alt="" />
          <span><strong>{t(`campaign.nations.${design.id}`)}</strong><small>{t(design.descriptionKey)}</small></span>
          <UnitArtwork unitCode="LIGHT_INFANTRY" armyDesignId={design.id} variant="battlefield" />
        </button>)}
      </div>
      <p className="campaign-muted">{t('campaign.nationProgress')}</p>
      <button type="button" className="button button--primary campaign-nation-start" onClick={() => onStart(selected)}>{t('campaign.enterCampaign')}</button>
      <button type="button" className="button button--ghost" onClick={onBack}>← {t('campaign.home')}</button>
    </section>
  </main>;
}
