import { useEffect, useMemo, useRef, useState } from 'react';
import egyptMap from '../assets/map/egypt.png';
import { ARMY_DESIGNS, getArmyDesign, getBattlefieldUnitArtwork, getUnitTypesForDesign } from '../config/armyDesigns';
import { DEFAULT_ARMY_QUANTITIES } from '../config/armyRules';
import { CAMPAIGN_HEXES, CAMPAIGN_BORDERS, CAMPAIGN_STORAGE_KEY, HEX_BY_ID, MAP_HEIGHT, MAP_WIDTH, SEASONS, armyMovement, armyUpkeep, campaignEconomy, remainingMovement, findSpawn, loadCampaign, moveArmy, nextSeason, reachableHexes, recruitArmy } from '../config/campaignRules';
import { TERRAIN_TYPES } from '../config/campaignTerrain';
import { CAMPAIGN_NATIONS } from '../config/campaignBorders';
import { useI18n } from '../i18n/I18nContext';
import ArmyBuilder from './ArmyBuilder';
import UnitArtwork from './UnitArtwork';
import '../campaign.css';

function TerrainDetails({ hex, onBack }) {
  const { t } = useI18n();
  const terrain = TERRAIN_TYPES[hex.terrain];
  return <section className="campaign-terrain-detail" aria-label={t('campaign.terrainDetails')}>
    <p className="eyebrow">{t('campaign.terrainDetails')}</p>
    <h2>{t(`campaign.terrain.${hex.terrain}`)}</h2>
    <p>{t('campaign.hex', { col: hex.col + 1, row: hex.row + 1 })}</p>
    <dl>
      <div><dt>{t('campaign.territory')}</dt><dd>{hex.territory ? t(`campaign.nations.${hex.territory}`) : t('campaign.noTerritory')}</dd></div>
      {hex.river && <div><dt>{t('campaign.river')}</dt><dd>{t(`campaign.rivers.${hex.river}`)}</dd></div>}
      <div><dt>{t('campaign.attrition')}</dt><dd>{terrain.attritionRate * 100} %</dd></div>
      <div><dt>{t('campaign.production')}</dt><dd><span className="grain-glyph" aria-hidden="true">&#x131E3;</span> {hex.production}</dd></div>
    </dl>
    <p>{t(terrain.difficult ? 'campaign.difficultMovement' : hex.land ? 'campaign.normalMovement' : 'campaign.impassable')}</p>
    <small>{t('campaign.productionActive')}</small>
    <button className="button button--secondary" type="button" onClick={onBack}>{t('campaign.backToArmies')}</button>
  </section>;
}

function ArmyRecruitment({ grain, unitTypes, loading, onClose, onRecruit }) {
  const { t, language } = useI18n();
  const dialog = useRef(null);
  const [designId, setDesignId] = useState('egypt');
  const [name, setName] = useState('');
  const [byDesign, setByDesign] = useState({});
  const available = getUnitTypesForDesign(unitTypes, designId).filter((unit) => unit.code !== 'MERCENARIES');
  const design = getArmyDesign(designId);
  const defaults = design.defaultQuantities || DEFAULT_ARMY_QUANTITIES;
  const defaultCost = available.reduce((sum, unit) => sum + (defaults[unit.code] || 0) * unit.grainCost, 0);
  const quantities = byDesign[designId] || (defaultCost <= grain ? defaults : {});
  const cost = available.reduce((sum, unit) => sum + (quantities[unit.code] || 0) * unit.grainCost, 0);
  const units = available.filter((unit) => quantities[unit.code] > 0).map((unit) => ({ ...unit, quantity: quantities[unit.code] }));
  const movement = armyMovement(units);
  const valid = !loading && units.length > 0 && cost <= grain;

  useEffect(() => {
    const previousFocus = document.activeElement;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    dialog.current?.querySelector('button')?.focus();
    function onKey(event) {
      if (event.key === 'Escape') onClose();
      if (event.key !== 'Tab') return;
      const elements = [...dialog.current.querySelectorAll('button:not(:disabled),input:not(:disabled),select:not(:disabled)')];
      const first = elements[0];
      const last = elements.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    }
    document.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener('keydown', onKey);
      previousFocus?.focus();
    };
  }, [onClose]);

  return (
    <div className="campaign-modal-overlay" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <section ref={dialog} className="campaign-recruit panel" role="dialog" aria-modal="true" aria-labelledby="recruit-title">
        <div className="campaign-modal-heading">
          <div><p className="eyebrow">{t('campaign.muster')}</p><h2 id="recruit-title">{t('campaign.createArmy')}</h2></div>
          <button type="button" className="encounter-modal__close" onClick={onClose} aria-label={t('app.close')}>×</button>
        </div>
        <form onSubmit={(event) => { event.preventDefault(); if (valid) onRecruit({ name, designId, quantities }, available); }}>
          <div className="campaign-recruit-fields">
            <label className="field"><span>{t('campaign.armyName')}</span><input value={name} maxLength={80} onChange={(event) => setName(event.target.value)} placeholder={t('campaign.defaultArmyName', { number: 1 })} /></label>
            <label className="field"><span>{t('campaign.nation')}</span><select value={designId} onChange={(event) => setDesignId(event.target.value)}>{ARMY_DESIGNS.map((item) => <option value={item.id} key={item.id}>{t(item.nameKey)}</option>)}</select></label>
          </div>
          <ArmyBuilder unitTypes={available} quantities={quantities} armyDesignId={designId} loading={loading} budget={grain} onChange={(next) => setByDesign((current) => ({ ...current, [designId]: next }))} />
          <div className="campaign-recruit-summary"><span>{t('campaign.averageMovement', { value: movement.toLocaleString(language, { maximumFractionDigits: 2 }) })}</span><small>{t('campaign.wholeHexes')}</small></div>
          <div className="campaign-modal-actions"><button className="button button--ghost" type="button" onClick={onClose}>{t('campaign.cancel')}</button><button className="button button--primary" type="submit" disabled={!valid}>{t('campaign.recruitCost', { cost })}</button></div>
        </form>
      </section>
    </div>
  );
}

export default function CampaignPage({ unitTypes, loadingUnitTypes }) {
  const { t, language } = useI18n();
  const [campaign, setCampaign] = useState(() => loadCampaign({ getItem: (key) => window.localStorage.getItem(key) }));
  const [selectedId, setSelectedId] = useState(null);
  const [recruiting, setRecruiting] = useState(false);
  const [storageError, setStorageError] = useState(false);
  const [notice, setNotice] = useState('');
  const [zoom, setZoom] = useState(1);
  const [inspectedId, setInspectedId] = useState('7,11');
  const [sidebarMode, setSidebarMode] = useState('armies');
  const map = useRef(null);
  const selected = campaign.armies.find((army) => army.id === selectedId);
  const inspectedHex = HEX_BY_ID.get(inspectedId);
  const terrain = TERRAIN_TYPES[inspectedHex.terrain];
  const economy = campaignEconomy(campaign);
  const formatGrain = (value) => value.toLocaleString(language, { maximumFractionDigits: 2 });
  const formatConsumption = (value) => value.toLocaleString('en-US', { useGrouping: false, maximumFractionDigits: 2 });
  const report = campaign.lastTurnReport;
  const reachable = useMemo(() => reachableHexes(campaign, selectedId), [campaign, selectedId]);
  const occupied = useMemo(() => new Map(campaign.armies.map((army) => [army.hexId, army])), [campaign.armies]);
  const cheapestUnit = Math.min(...ARMY_DESIGNS.flatMap((design) => getUnitTypesForDesign(unitTypes, design.id).filter((unit) => unit.code !== 'MERCENARIES').map((unit) => unit.grainCost)));
  const year = 1300 - Math.floor(campaign.turn / 3);
  const formattedYear = year > 0 ? t('campaign.yearBC', { year }) : t('campaign.yearAD', { year: 1 - year });

  useEffect(() => {
    try { localStorage.setItem(CAMPAIGN_STORAGE_KEY, JSON.stringify(campaign)); setStorageError(false); }
    catch { setStorageError(true); }
  }, [campaign]);

  function focusArmy(army) {
    setSidebarMode('armies');
    setSelectedId(army.id);
    setInspectedId(army.hexId);
    const hex = HEX_BY_ID.get(army.hexId);
    const svg = map.current?.querySelector('svg');
    if (svg && hex) {
      const scale = svg.getBoundingClientRect().width / MAP_WIDTH;
      map.current.scrollTo({ top: Math.max(0, hex.y * scale - map.current.clientHeight / 2), left: Math.max(0, hex.x * scale - map.current.clientWidth / 2), behavior: 'smooth' });
    }
  }

  function activateHex(hex) {
    setInspectedId(hex.id);
    const army = occupied.get(hex.id);
    if (army) { setSelectedId(army.id); setSidebarMode('armies'); return; }
    if (selected && reachable.has(hex.id)) {
      setCampaign((current) => moveArmy(current, selectedId, hex.id));
      setNotice(t('campaign.moved', { name: selected.name || t('campaign.defaultArmyName', { number: selected.id }), col: hex.col + 1, row: hex.row + 1 }));
      return;
    }
    setSelectedId(null);
    setSidebarMode('terrain');
  }

  function recruit(input, available) {
    const next = recruitArmy(campaign, input, available);
    if (next === campaign) return;
    setCampaign(next);
    setRecruiting(false);
    focusArmy(next.armies.at(-1));
    setNotice(t('campaign.recruited'));
  }

  return (
    <main className="campaign-page">
      <header className="campaign-heading">
        <div><p className="eyebrow">{t('navigation.campaigns')}</p><h1>{t('campaign.title')}</h1></div>
        <div className="campaign-calendar"><strong>{formattedYear}</strong><ol aria-label={t('campaign.calendar')}>{SEASONS.map((season, index) => <li key={season} className={campaign.turn % 3 === index ? 'is-current' : ''} aria-current={campaign.turn % 3 === index ? 'step' : undefined}><span>{index + 1}</span>{t(`campaign.seasons.${season}`)}</li>)}</ol></div>
        <button className="button button--primary" type="button" onClick={() => { setCampaign((current) => nextSeason(current)); setNotice(t('campaign.movementRestored')); }}>{t('campaign.endTurn')} <span aria-hidden="true">→</span></button>
      </header>
      {storageError && <p className="error-banner" role="alert">{t('campaign.storageError')}</p>}
      <div className="campaign-layout">
        <aside className="campaign-sidebar panel" aria-label={t(sidebarMode === 'terrain' ? 'campaign.terrainDetails' : 'campaign.armies')}>
          <div className="campaign-grain"><span className="grain-glyph" aria-hidden="true">&#x131E3;</span><div><strong>{formatGrain(campaign.grain)}</strong><small>{t('armyBuilder.grainRemaining')}</small></div></div>
          <p className="campaign-upkeep">{t('campaign.upkeep', { grain: formatConsumption(economy.consumption) })}</p>
          <p className={`campaign-situation is-${economy.situation}`}>{t(`campaign.situations.${economy.situation}`)}</p>
          {sidebarMode === 'terrain' ? <TerrainDetails hex={inspectedHex} onBack={() => setSidebarMode('armies')} /> : <>
          <div className="campaign-armies-heading"><h2>{t('campaign.armies')}</h2><span>{campaign.armies.length}</span></div>
          <button className="button button--secondary" type="button" disabled={loadingUnitTypes || campaign.grain < cheapestUnit || !findSpawn(campaign)} onClick={() => setRecruiting(true)}>+ {t('campaign.createArmy')}</button>
          {!loadingUnitTypes && campaign.grain < cheapestUnit && <p className="campaign-muted">{t('campaign.insufficientGrain')}</p>}
          {!campaign.armies.length && <div className="campaign-empty"><span aria-hidden="true">⚑</span><p>{t('campaign.empty')}</p></div>}
          <div className="campaign-armies">{campaign.armies.map((army) => <button className={`campaign-army ${army.id === selectedId ? 'is-selected' : ''}`} type="button" aria-pressed={army.id === selectedId} key={army.id} onClick={() => focusArmy(army)}><UnitArtwork unitCode="LIGHT_INFANTRY" armyDesignId={army.designId} variant="battlefield" /><span><strong>{army.name || t('campaign.defaultArmyName', { number: army.id })}</strong><small>{t(getArmyDesign(army.designId).nameKey)}</small><small>{t('campaign.armySummary', { units: army.units.reduce((sum, unit) => sum + unit.quantity, 0), remaining: remainingMovement(army) })}</small><small>{t('campaign.upkeep', { grain: formatConsumption(armyUpkeep(army)) })}</small></span></button>)}</div>
          {selected && <section className="campaign-army-detail"><h3>{selected.name || t('campaign.defaultArmyName', { number: selected.id })}</h3><p>{t('campaign.averageMovement', { value: armyMovement(selected.units).toLocaleString(language, { maximumFractionDigits: 2 }) })}</p><p>{t('campaign.position', { col: HEX_BY_ID.get(selected.hexId).col + 1, row: HEX_BY_ID.get(selected.hexId).row + 1 })}</p><ul>{selected.units.map((unit) => <li key={unit.code}><span>{unitTypes.find((type) => type.code === unit.code)?.name || t(`campaign.unitNames.${unit.code}`)}</span><strong>×{unit.quantity}</strong></li>)}</ul><small>{t('campaign.wholeHexes')}</small></section>}
          </>}
          <p className="campaign-save-note">{t('campaign.savedLocally')}</p>
        </aside>
        <section className="campaign-map-panel panel" aria-label={t('campaign.map')}>
          <div className="campaign-map-toolbar"><p>{selected ? t('campaign.moveHint') : t('campaign.selectHint')}</p><div className="campaign-zoom"><button type="button" disabled={zoom <= 1} onClick={() => setZoom((value) => Math.max(1, value - 0.25))} aria-label={t('battle.zoomOut')}>−</button><button type="button" onClick={() => setZoom(1)} aria-label={t('battle.resetZoom')}>{Math.round(zoom * 100)}%</button><button type="button" disabled={zoom >= 2} onClick={() => setZoom((value) => Math.min(2, value + 0.25))} aria-label={t('battle.zoomIn')}>+</button></div></div>
          <div className={`campaign-terrain-info terrain--${inspectedHex.terrain}`} role="status">
            <strong>{t(`campaign.terrain.${inspectedHex.terrain}`)} · {inspectedHex.col + 1}, {inspectedHex.row + 1}</strong>
            <span>{t('campaign.terrainAttrition', { rate: terrain.attritionRate * 100 })}</span>
            <span>{t(terrain.difficult ? 'campaign.difficultMovement' : inspectedHex.land ? 'campaign.normalMovement' : 'campaign.impassable')}</span>
          </div>
          <div className="campaign-map-scroll" ref={map}>
            <svg className="campaign-map" style={{ width: `${zoom * 100}%` }} viewBox={`0 0 ${MAP_WIDTH} ${MAP_HEIGHT}`} aria-label={t('campaign.map')}>
              <image href={egyptMap} x="0" y="0" width={MAP_WIDTH} height={MAP_HEIGHT} />
              {CAMPAIGN_HEXES.map((hex) => {
                const army = occupied.get(hex.id);
                const active = army?.id === selectedId;
                const canMove = reachable.has(hex.id);
                const positionLabel = army ? t('campaign.armyAt', { name: army.name || t('campaign.defaultArmyName', { number: army.id }), col: hex.col + 1, row: hex.row + 1 }) : t('campaign.hex', { col: hex.col + 1, row: hex.row + 1 });
                const label = `${positionLabel} · ${t(`campaign.terrain.${hex.terrain}`)} · ${t('campaign.terrainAttrition', { rate: TERRAIN_TYPES[hex.terrain].attritionRate * 100 })} · ${t('campaign.productionValue', { amount: hex.production })} · ${t(TERRAIN_TYPES[hex.terrain].difficult ? 'campaign.difficultMovement' : hex.land ? 'campaign.normalMovement' : 'campaign.impassable')}`;
                return <g key={hex.id} className={`campaign-hex ${!hex.land ? 'is-water' : ''} ${canMove ? 'is-reachable' : ''} ${active ? 'is-selected' : ''} ${army ? 'is-occupied' : ''} ${sidebarMode === 'terrain' && inspectedId === hex.id ? 'is-inspected' : ''}`} role="button" tabIndex={army || canMove || inspectedId === hex.id ? 0 : -1} aria-label={label} onClick={() => activateHex(hex)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); activateHex(hex); } }}>
                  <title>{label}</title><polygon points={hex.points} />
                  {army && <><circle cx={hex.x} cy={hex.y} r="19" /><image href={getBattlefieldUnitArtwork('LIGHT_INFANTRY', army.designId)} x={hex.x - 18} y={hex.y - 23} width="36" height="42" /><text x={hex.x + 14} y={hex.y + 19}>{army.id}</text></>}
                  {canMove && !army && <circle className="campaign-move-dot" cx={hex.x} cy={hex.y} r="3" />}
                </g>;
              })}
              <g className="campaign-borders" aria-hidden="true">{CAMPAIGN_BORDERS.map((border) => <path key={border.id} d={border.path} stroke={CAMPAIGN_NATIONS[border.territory].color} />)}</g>
            </svg>
          </div>
          <div className="campaign-map-footer"><span><i />{t('campaign.reachable')}</span><div className="campaign-border-legend">{Object.entries(CAMPAIGN_NATIONS).map(([id, nation]) => <span key={id}><i style={{ background: nation.color }} />{t(`campaign.nations.${id}`)}</span>)}</div><small>{t('campaign.mapHelp')}</small></div>
        </section>
      </div>
      {report && <section className="campaign-turn-report panel" aria-label={t('campaign.turnReport')}>
        <h2>{t('campaign.turnReport')}</h2>
        <p>{t('campaign.productionReport', { grain: formatGrain(report.producedGrain || 0) })}</p>
        <p>{t('campaign.consumptionReport', { consumed: formatGrain(report.consumedGrain), required: formatGrain(report.requiredGrain) })}</p>
        {report.situation && <p>{t(`campaign.situations.${report.situation}`)}</p>}
        <ul>{report.armies.map((entry) => <li key={entry.armyId}><strong>{entry.name || t('campaign.defaultArmyName', { number: entry.armyId })}</strong><span>{t('campaign.lossReport', { terrain: entry.terrainLosses, supply: entry.supplyLosses })}</span>{entry.recoveredUnits > 0 && <span className="campaign-recovery">{t('campaign.recoveryReport', { count: entry.recoveredUnits })}</span>}{entry.destroyed && <em>{t('campaign.armyDestroyed')}</em>}</li>)}</ul>
      </section>}
      <p className="campaign-notice" role="status" aria-live="polite">{notice}</p>
      {recruiting && <ArmyRecruitment grain={campaign.grain} unitTypes={unitTypes} loading={loadingUnitTypes} onClose={() => setRecruiting(false)} onRecruit={recruit} />}
    </main>
  );
}
