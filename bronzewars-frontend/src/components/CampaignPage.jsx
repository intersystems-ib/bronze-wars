import { useEffect, useMemo, useRef, useState } from 'react';
import egyptMap from '../assets/map/egypt.png';
import cityArtwork from '../assets/map/city.png';
import { movementContext, needsMovementDecision, storeMovementDecision, pendingMovementOrder, executeMovementOrder, skipMovement, engageArmy, encounterPayload } from '../config/campaignMovement';
import { resolveAIEncounter, pendingCombatReports, acknowledgeCombatReport } from '../config/campaignCombat';
import { hexDistance } from '../config/campaignVisibility';
import { campaignView } from '../config/campaignVisibility';
import { disbandArmy, terrainAttrition, mergeArmies } from '../config/campaignRules';
import { api } from '../api/client';
import { rivalNations, needsRecruitmentDecision, initializeCampaignAI, recruitmentCapacity, automaticRecruitmentDecision, applyRecruitmentDecision } from '../config/campaignAI';
import { CAMPAIGN_CITIES } from '../config/campaignCities';
import { cityAt, cityOwner, cityIncomeNation, cityProduction, cityRaid, assaultDuration, startCityAction, cancelCityAction, campaignCapital, isCampaignCapital } from '../config/campaignCityActions';
import { getArmyDesign, getBattlefieldUnitArtwork, getUnitTypesForDesign } from '../config/armyDesigns';
import { DEFAULT_ARMY_QUANTITIES, MIN_ARMY_DIVISIONS, minimumArmyCost } from '../config/armyRules';
import { CAMPAIGN_HEXES, campaignTerritory, campaignTerritoryInfo, availableGrain, HEX_BY_ID, MAP_HEIGHT, MAP_WIDTH, SEASONS, remainingMovement, armyMovement, armyTroops, activeUnitCount, unitTroops, migrateCampaignStrength, campaignEconomy, findSpawn, moveArmy, nextSeason, reachableHexes, recruitArmy } from '../config/campaignRules';
import { campaignSaveKey, createCampaignSave, writeCampaignSave, readCampaignSave, deleteCampaignSave, listCampaignSaves, importLegacyCampaigns } from '../config/campaignSaves';
import { TERRAIN_TYPES } from '../config/campaignTerrain';
import { CAMPAIGN_NATIONS, buildBorders } from '../config/campaignBorders';
import { useI18n } from '../i18n/I18nContext';
import ArmyBuilder from './ArmyBuilder';
import CampaignMergeDialog from './CampaignMergeDialog';
import UnitArtwork from './UnitArtwork';
import CampaignNationSelection from './CampaignNationSelection';
import CampaignStart, { CampaignSaveList } from './CampaignStart';
import '../campaign.css';

function cityName(city, t) {
  return t(`campaign.cityNames.${city.id}`);
}

function TerrainDetails({ hex, campaign, contact, onBack, children }) {
  const { t } = useI18n();
  const terrain = TERRAIN_TYPES[hex.terrain];
  const regionCity = CAMPAIGN_CITIES.find((city) => city.id === hex.regionId);
  const territory = campaignTerritoryInfo(campaign, hex);
  return <section className="campaign-terrain-detail" aria-label={t('campaign.terrainDetails')}>
    <p className="eyebrow">{t('campaign.terrainDetails')}</p>
    <h2>{hex.city ? cityName(hex.city, t) : t(`campaign.terrain.${hex.terrain}`)}</h2>
    {hex.city && <img className="campaign-city-preview" src={cityArtwork} alt="" />}
    <p>{t('campaign.hex', { col: hex.col + 1, row: hex.row + 1 })}</p>
    {children}
    {contact && !contact.own && <p className="campaign-enemy-contact">{t('campaign.enemyContact', { nation: t(`campaign.nations.${contact.designId}`), count: contact.unitCount ?? '?' })}</p>}
    <dl>
      {regionCity && <div><dt>{t('campaign.region')}</dt><dd>{cityName(regionCity, t)}</dd></div>}
      {hex.city && <div><dt>{t('campaign.settlement')}</dt><dd>{t(isCampaignCapital(campaign, hex.city) ? 'campaign.capital' : 'campaign.city')}</dd></div>}
      {hex.city && <div><dt>{t('campaign.terrainDetails')}</dt><dd>{t(`campaign.terrain.${hex.terrain}`)}</dd></div>}
      <div><dt>{t('campaign.territory')}</dt><dd>{campaignTerritory(campaign, hex) ? t(`campaign.nations.${campaignTerritory(campaign, hex)}`) : t('campaign.noTerritory')}</dd></div>
      {territory.occupied && <><div><dt>{t('campaign.occupation.status')}</dt><dd>{t('campaign.occupation.occupied')}</dd></div><div><dt>{t('campaign.occupation.originalOwner')}</dt><dd>{t(`campaign.nations.${territory.originalOwner}`)}</dd></div></>}
      {hex.city && <div><dt>{t('campaign.cityActions.incomeRecipient')}</dt><dd>{cityIncomeNation(campaign, hex.city) ? t(`campaign.nations.${cityIncomeNation(campaign, hex.city)}`) : t('campaign.cityActions.noHarvest')}</dd></div>}
      {hex.river && <div><dt>{t('campaign.river')}</dt><dd>{t(`campaign.rivers.${hex.river}`)}</dd></div>}
      <div><dt>{t('campaign.attrition')}</dt><dd>{terrainAttrition(campaign, hex) * 100} %</dd></div>
      <div><dt>{t('campaign.annualProduction')}</dt><dd><span className="grain-glyph" aria-hidden="true">&#x131E3;</span> {hex.city ? cityProduction(campaign, hex.city) : hex.production}</dd></div>
    </dl>
    {territory.occupied && <p>{t('campaign.occupation.effects')}</p>}
    <p>{t(terrain.difficult ? 'campaign.difficultMovement' : hex.land ? 'campaign.normalMovement' : 'campaign.impassable')}</p>
    <small>{t('campaign.productionActive')}</small>
    <button className="button button--secondary" type="button" onClick={onBack}>{t('campaign.backToArmies')}</button>
  </section>;
}

function CampaignDecisionModal({ phase, revealMap, onContinue }) {
  const { t } = useI18n();
  const dialog = useRef(null);
  const nationName = t(`campaign.nations.${phase.nation}`);
  const result = phase.result;

  useEffect(() => {
    const element = dialog.current;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    element.showModal();
    return () => { element.close(); document.body.style.overflow = previousOverflow; };
  }, []);

  return <dialog ref={dialog} className="campaign-ai-modal panel" aria-labelledby="campaign-ai-title" aria-describedby="campaign-ai-description" onCancel={(event) => event.preventDefault()}>
    <div role="status" aria-live="polite" aria-atomic="true">
      <img className="campaign-ai-emblem" src={getArmyDesign(phase.nation).logo} alt={t('campaign.ai.emblem', { nation: nationName })} />
      <h2 id="campaign-ai-title">{result ? t('campaign.combat.resultTitle') : t('campaign.ai.nationThinking', { nation: nationName })}</h2>
      <p id="campaign-ai-description">{result ? t(result.regional ? `campaign.combat.battleNames.${result.terrain}` : 'campaign.combat.battleNear', { city: t(`campaign.cityNames.${result.cityId}`), terrain: t(`campaign.terrain.${result.terrain}`) }) : t(`campaign.ai.${phase.kind || 'recruitment'}Phase`)}</p>
      <small>{t('campaign.ai.nationProgress', { current: phase.index + 1, total: phase.total })}</small>
    </div>
    {result ? <section className="campaign-ai-combat-result" aria-label={t('campaign.combat.resultTitle')}>
      <p className="campaign-ai-victor">{t('campaign.combat.victor', { nation: t(`campaign.nations.${result.winnerNation}`) })}</p>
      <p>{t('campaign.combat.nationLosses', { nation: t(`campaign.nations.${result.winnerNation}`), count: result.winnerLosses })}</p>
      <p>{t('campaign.combat.nationLosses', { nation: t(`campaign.nations.${result.loserNation}`), count: result.loserLosses })}</p>
      <p>{t(result.retreatHexId ? 'campaign.combat.defeatedRetreats' : 'campaign.combat.defeatedDestroyed', { nation: t(`campaign.nations.${result.loserNation}`) })}</p>
      <button autoFocus className="button button--primary" type="button" onClick={onContinue}>{t('campaign.combat.continue')}</button>
    </section> : <progress aria-label={t(`campaign.ai.${phase.kind || 'recruitment'}Phase`)} />}
    {revealMap && phase.kind === 'recruitment' && <p className="campaign-muted">{t('campaign.ai.deploymentSpace', { count: phase.freeHexes })}</p>}
  </dialog>;
}

function ArmyRecruitment({ grain, nation, capital, unitTypes, loading, onClose, onRecruit }) {
  const { t, language } = useI18n();
  const dialog = useRef(null);
  const designId = nation;
  const [name, setName] = useState('');
  const [customQuantities, setCustomQuantities] = useState(null);
  const available = getUnitTypesForDesign(unitTypes, designId).filter((unit) => unit.code !== 'MERCENARIES');
  const design = getArmyDesign(designId);
  const defaults = design.defaultQuantities || DEFAULT_ARMY_QUANTITIES;
  const defaultCost = available.reduce((sum, unit) => sum + (defaults[unit.code] || 0) * unit.grainCost, 0);
  const quantities = customQuantities || (defaultCost <= grain ? defaults : {});
  const cost = available.reduce((sum, unit) => sum + (quantities[unit.code] || 0) * unit.grainCost, 0);
  const units = available.filter((unit) => quantities[unit.code] > 0).map((unit) => ({ ...unit, quantity: quantities[unit.code] }));
  const movement = armyMovement(units);
  const troops = units.reduce((sum, unit) => sum + unit.quantity * unit.initialStrength, 0);
  const valid = !loading && units.reduce((sum, unit) => sum + unit.quantity, 0) >= MIN_ARMY_DIVISIONS && cost <= grain;

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
            <div className="field"><span>{t('campaign.nation')}</span><div className="campaign-recruit-nation"><img src={design.logo} alt="" /><strong>{t(`campaign.nations.${nation}`)}</strong></div></div>
          </div>
          <ArmyBuilder unitTypes={available} quantities={quantities} armyDesignId={designId} loading={loading} budget={grain} onChange={setCustomQuantities} />
          <div className="campaign-recruit-summary"><span>{t(troops === 1 ? 'campaign.troopCountOne' : 'campaign.troopCount', { count: troops })}</span><span>{t('campaign.averageMovement', { value: movement.toLocaleString(language, { maximumFractionDigits: 2 }) })}</span><small>{t('campaign.wholeHexes')}</small></div>
          <p className="campaign-muted">{t('campaign.deployInCapital', { city: cityName(capital, t) })}</p>
          <div className="campaign-modal-actions"><button className="button button--ghost" type="button" onClick={onClose}>{t('campaign.cancel')}</button><button className="button button--primary" type="submit" disabled={!valid}>{t('campaign.recruitCost', { cost })}</button></div>
        </form>
      </section>
    </div>
  );
}

export default function CampaignPage(props) {
  const [save, setSave] = useState(() => props.resumeCampaignId ? readCampaignSave(localStorage, props.resumeCampaignId) : null);
  const [screen, setScreen] = useState(() => props.resumeCampaignId && readCampaignSave(localStorage, props.resumeCampaignId) ? 'session' : 'home');
  const [saves, setSaves] = useState([]);
  const [error, setError] = useState('');

  function home() {
    setSave(null);
    setError('');
    setScreen('home');
  }

  function create(nation) {
    try {
      const created = createCampaignSave(localStorage, nation);
      setSave(created);
      setError('');
      setScreen('session');
    } catch {
      setError('campaign.saveFailed');
    }
  }

  function showSaves() {
    setError('');
    try {
      importLegacyCampaigns(localStorage);
      setSaves(listCampaignSaves(localStorage));
    } catch {
      setSaves([]);
      setError('campaign.saveFailed');
    }
    setScreen('load');
  }

  function resume(id) {
    const loaded = readCampaignSave(localStorage, id);
    if (!loaded) { setError('campaign.loadFailed'); return; }
    setSave(loaded);
    setError('');
    setScreen('session');
  }

  function removeSave(id) {
    try {
      if (!deleteCampaignSave(localStorage, id)) { setError('campaign.deleteFailed'); return; }
      setSaves(listCampaignSaves(localStorage));
      setError('');
    } catch { setError('campaign.deleteFailed'); }
  }

  if (screen === 'session') return <CampaignSession {...props} initialSave={save} key={save.id} onHome={home} />;
  if (screen === 'nation') return <CampaignNationSelection onStart={create} onBack={home} error={error} />;
  if (screen === 'load') return <CampaignSaveList saves={saves} error={error} onLoad={resume} onDelete={removeSave} onBack={home} />;
  return <CampaignStart onNew={() => { setError(''); setScreen('nation'); }} onLoad={showSaves} />;
}

function CampaignSession({ unitTypes, loadingUnitTypes, initialSave, onHome, onEncounter }) {
  const { t, language } = useI18n();
  const nation = initialSave.campaign.nation;
  const storageKey = campaignSaveKey(initialSave.id);
  const [campaign, setCampaign] = useState(initialSave.campaign);
  const [selectedId, setSelectedId] = useState(null);
  const [disbandingId, setDisbandingId] = useState(null);
  const [merging, setMerging] = useState(null);
  const [revealMap, setRevealMap] = useState(false);
  const [aiBusy, setAiBusy] = useState(false);
  const [aiPhase, setAiPhase] = useState(null);
  const combatContinuation = useRef(null);
  const [aiErrors, setAiErrors] = useState([]);
  const [aiRetry, setAiRetry] = useState(0);
  const [recruiting, setRecruiting] = useState(false);
  const [storageError, setStorageError] = useState(false);
  const [notice, setNotice] = useState('');
  const [zoom, setZoom] = useState(1);
  const [inspectedId, setInspectedId] = useState('7,11');
  const [sidebarMode, setSidebarMode] = useState('armies');
  const map = useRef(null);
  const openingBattle = useRef(false);
  const [battleOpening, setBattleOpening] = useState(false);
  const [battleError, setBattleError] = useState(false);
  const view = useMemo(() => campaignView(campaign, nation, { reveal: revealMap }), [campaign, nation, revealMap]);
  const ownArmies = useMemo(() => campaign.armies.filter((army) => army.designId === nation), [campaign.armies, nation]);
  const selected = ownArmies.find((army) => army.id === selectedId);
  const aiPending = pendingCombatReports(campaign).length > 0 || rivalNations(campaign).some((rival) => needsRecruitmentDecision(campaign, rival) || needsMovementDecision(campaign, rival));
  const campaignReady = campaign.version === 2 && !aiPending && !aiBusy && !campaign.pendingEncounter;
  const inspectedHex = HEX_BY_ID.get(inspectedId);
  const capital = campaignCapital(campaign, nation);
  const inspectingCapital = sidebarMode === 'terrain' && inspectedId === capital?.hexId && cityOwner(campaign, capital) === nation;
  const mergeSource = campaign.armies.find((army) => army.id === merging?.sourceId);
  const mergeTarget = campaign.armies.find((army) => army.id === merging?.targetId);
  const mergePreview = merging ? mergeArmies(campaign, merging.sourceId, merging.targetId) : campaign;
  const combinedArmy = mergePreview !== campaign ? mergePreview.armies.find((army) => army.id === merging.targetId) : null;
  const selectedCity = cityAt(selected?.hexId);
  const enemyCity = selectedCity && cityOwner(campaign, selectedCity) !== nation;
  const mapBorders = useMemo(() => buildBorders(CAMPAIGN_HEXES.map((hex) => ({ ...hex, territory: campaignTerritory(campaign, hex) }))), [campaign.cityOwners]);
  const terrain = TERRAIN_TYPES[inspectedHex.terrain];
  const economy = campaignEconomy(campaign);
  const formatGrain = (value) => value.toLocaleString(language, { maximumFractionDigits: 2 });
  const formatConsumption = (value) => value.toLocaleString('en-US', { useGrouping: false, maximumFractionDigits: 2 });
  const report = campaign.lastTurnReport;
  const reachable = useMemo(() => reachableHexes(campaign, selectedId), [campaign, selectedId]);
  const occupied = useMemo(() => new Map(view.armies.map((army) => [army.hexId, army])), [view]);
  const grain = availableGrain(campaign.grain);
  const cheapestUnit = minimumArmyCost(getUnitTypesForDesign(unitTypes, nation).filter((unit) => unit.code !== 'MERCENARIES'));
  const year = 1300 - Math.floor(campaign.turn / 3);
  const formattedYear = year > 0 ? t('campaign.yearBC', { year }) : t('campaign.yearAD', { year: 1 - year });

  useEffect(() => { setDisbandingId(null); }, [selectedId]);

  useEffect(() => {
    if (campaign.version !== 2 || loadingUnitTypes || !unitTypes.length) return;
    const controller = new AbortController();
    let active = true;
    async function decideRecruitment() {
      if (campaign.pendingEncounter && campaign.armies.some((army) => army.designId === nation && [campaign.pendingEncounter.attackerId, campaign.pendingEncounter.defenderId].includes(army.id))) return;
      setAiBusy(true);
      setAiErrors([]);
      let current = migrateCampaignStrength(initializeCampaignAI(campaign), unitTypes);
      const persist = (next) => {
        current = next;
        writeCampaignSave(localStorage, initialSave, current);
        setCampaign(current);
      };
      const errors = [];
      const rivals = rivalNations(current).filter((rival) => needsRecruitmentDecision(current, rival) || needsMovementDecision(current, rival));
      async function showCombatResults(meta) {
        for (const result of pendingCombatReports(current)) {
          setAiPhase({ ...meta, nation: meta.nation ?? result.attackerNation ?? result.winnerNation, kind: 'combat', result });
          const continued = await new Promise((resolve) => { combatContinuation.current = resolve; });
          if (!active || !continued) return false;
          combatContinuation.current = null;
          persist(acknowledgeCombatReport(current, result.id));
        }
        return true;
      }
      try {
        if (current.pendingEncounter) current = resolveAIEncounter(current);
        persist(current);
        if (!await showCombatResults({ index: 0, total: Math.max(1, rivals.length) }) || !active) return;
        for (const [index, rival] of rivals.entries()) {
          let phase = 'recruitment';
          try {
            if (needsRecruitmentDecision(current, rival)) {
              const catalogue = getUnitTypesForDesign(unitTypes, rival).filter((unit) => unit.code !== 'MERCENARIES');
              const capacity = recruitmentCapacity(current, rival, catalogue);
              let decision = automaticRecruitmentDecision(capacity);
              if (!decision) {
                setAiPhase({ nation: rival, index, total: rivals.length, kind: phase, freeHexes: capacity.freeDeploymentHexes });
                decision = await api.campaignRecruitment(capacity, controller.signal);
              }
              if (!active) return;
              persist(applyRecruitmentDecision(current, rival, decision, catalogue));
            }
            phase = 'movement';
            while (needsMovementDecision(current, rival)) {
              setAiPhase({ nation: rival, index, total: rivals.length, kind: phase });
              if (!pendingMovementOrder(current, rival)) {
                const decision = await api.campaignStrategy(movementContext(current, rival), controller.signal);
                if (!active) return;
                persist(storeMovementDecision(current, rival, decision));
              }
              persist(executeMovementOrder(current, rival));
              if (current.pendingEncounter) {
                const participants = [current.pendingEncounter.attackerId, current.pendingEncounter.defenderId];
                if (current.armies.some((army) => participants.includes(army.id) && army.designId === nation)) break;
                setAiPhase({ nation: rival, index, total: rivals.length, kind: 'combat' });
                persist(resolveAIEncounter(current));
                if (!await showCombatResults({ nation: rival, index, total: rivals.length }) || !active) return;
              }
            }
            if (current.pendingEncounter) break;
          } catch (error) {
            if (!active) return;
            console.warn('Campaign AI failed', rival, phase, error);
            errors.push({ nation: rival, phase });
          }
        }
      } catch { setStorageError(true); }
      if (active) { setAiErrors(errors); setAiBusy(false); setAiPhase(null); }
    }
    decideRecruitment();
    return () => { active = false; controller.abort(); combatContinuation.current?.(false); combatContinuation.current = null; };
  }, [campaign.turn, campaign.version, loadingUnitTypes, unitTypes, aiRetry]);

  useEffect(() => {
    const upgraded = migrateCampaignStrength(campaign, unitTypes);
    if (upgraded === campaign) return;
    try {
      const backupKey = `${storageKey}.before-strength-v2`;
      if (!localStorage.getItem(backupKey)) localStorage.setItem(backupKey, JSON.stringify(campaign));
    } catch { /* Conversion remains playable when the optional backup cannot be stored. */ }
    setCampaign(upgraded);
  }, [campaign, unitTypes, storageKey]);

  useEffect(() => {
    try { writeCampaignSave(localStorage, initialSave, campaign); setStorageError(false); }
    catch { setStorageError(true); }
  }, [campaign, initialSave]);

  async function openEncounter() {
    if (openingBattle.current || !campaign.pendingEncounter) return;
    openingBattle.current = true;
    setBattleOpening(true);
    setBattleError(false);
    try {
      writeCampaignSave(localStorage, initialSave, campaign);
      await onEncounter(encounterPayload(campaign, initialSave.id));
    } catch { setBattleError(true); }
    finally { openingBattle.current = false; setBattleOpening(false); }
  }

  useEffect(() => {
    if (campaign.pendingEncounter && !campaign.pendingEncounter.battleId && !aiBusy && !battleError && campaign.armies.some((army) => army.designId === nation && [campaign.pendingEncounter.attackerId, campaign.pendingEncounter.defenderId].includes(army.id))) openEncounter();
  }, [campaign.pendingEncounter, aiBusy]);

  function centerHex(hex) {
    const svg = map.current?.querySelector('svg');
    if (svg && hex) {
      const scale = svg.getBoundingClientRect().width / MAP_WIDTH;
      map.current.scrollTo({ top: Math.max(0, hex.y * scale - map.current.clientHeight / 2), left: Math.max(0, hex.x * scale - map.current.clientWidth / 2), behavior: 'smooth' });
    }
  }

  function focusArmy(army) {
    setSidebarMode('armies');
    setSelectedId(army.id);
    setInspectedId(army.hexId);
    centerHex(HEX_BY_ID.get(army.hexId));
  }

  function showArmies() {
    setSelectedId(null);
    setSidebarMode('armies');
  }

  function inspectCapital() {
    if (!capital) return;
    setSelectedId(null);
    setSidebarMode('terrain');
    setInspectedId(capital.hexId);
    centerHex(HEX_BY_ID.get(capital.hexId));
  }

  function activateHex(hex) {
    setInspectedId(hex.id);
    const army = occupied.get(hex.id);
    if (army?.own) {
      if (campaignReady && selected && selected.id !== army.id && reachable.has(hex.id)) { setMerging({ sourceId: selected.id, targetId: army.id }); return; }
      setSelectedId(army.id); setSidebarMode('armies'); return;
    }
    if (army) { setSidebarMode('terrain'); return; }
    if (selected && reachable.has(hex.id)) {
      setCampaign((current) => moveArmy(current, selectedId, hex.id));
      setNotice(t('campaign.moved', { name: selected.name || t('campaign.defaultArmyName', { number: selected.id }), col: hex.col + 1, row: hex.row + 1 }));
      return;
    }
    setSelectedId(null);
    setSidebarMode('terrain');
  }

  function confirmMerge() {
    const next = mergeArmies(campaign, merging.sourceId, merging.targetId);
    setMerging(null);
    if (next === campaign) return;
    setCampaign(next);
    focusArmy(next.armies.find((army) => army.id === merging.targetId));
    setNotice(t('campaign.merge.completed'));
  }

  function recruit(input, available) {
    if (!inspectingCapital) return;
    const next = recruitArmy(campaign, input, available);
    if (next === campaign) return;
    setCampaign(next);
    setRecruiting(false);
    focusArmy(next.armies.at(-1));
    setNotice(t('campaign.recruited'));
  }

  function actOnCity(type) {
    if (!selected || !enemyCity) return;
    setCampaign((current) => startCityAction(current, selected.id, type));
    setNotice(t(`campaign.cityActions.${type}Started`, { city: cityName(selectedCity, t), grain: cityProduction(campaign, selectedCity) }));
  }

  function disband() {
    if (!selected || disbandingId !== selected.id) return;
    setCampaign((current) => disbandArmy(current, selected.id));
    setNotice(t('campaign.disbanded', { name: selected.name || t('campaign.defaultArmyName', { number: selected.id }) }));
    setDisbandingId(null);
    showArmies();
  }

  return (
    <main className="campaign-page">
      <header className="campaign-heading">
        <div><button className="campaign-nation-back" type="button" onClick={onHome}>← {t('campaign.home')}</button><h1>{t('campaign.titleForNation', { nation: t(`campaign.nations.${nation}`) })}</h1><p className="campaign-game-id">{t('campaign.gameId', { id: initialSave.id })}</p></div>
        <div className="campaign-calendar"><strong>{formattedYear}</strong><ol aria-label={t('campaign.calendar')}>{SEASONS.map((season, index) => <li key={season} className={campaign.turn % 3 === index ? 'is-current' : ''} aria-current={campaign.turn % 3 === index ? 'step' : undefined}><span>{index + 1}</span>{t(`campaign.seasons.${season}`)}</li>)}</ol></div>
        <button className="button button--primary" type="button" disabled={!campaignReady} onClick={() => { setCampaign((current) => nextSeason(current)); setNotice(t('campaign.movementRestored')); }}>{t('campaign.endTurn')} <span aria-hidden="true">→</span></button>
      </header>
      {storageError && <p className="error-banner" role="alert">{t('campaign.storageError')}</p>}
      {aiBusy && aiPhase && <CampaignDecisionModal phase={aiPhase} revealMap={revealMap} onContinue={() => combatContinuation.current?.(true)} />}
      {!aiBusy && aiErrors.length > 0 && <div className="error-banner" role="alert">
        <p>{t('campaign.ai.failed')}</p>
        <button type="button" className="button button--secondary" onClick={() => setAiRetry((value) => value + 1)}>{t('campaign.ai.retry')}</button>
        {aiErrors.map(({ nation: rival, phase }) => <button key={rival} type="button" className="button button--ghost" onClick={() => {
          setCampaign((current) => phase === 'movement' ? skipMovement(current, rival) : skipMovement(applyRecruitmentDecision(current, rival, { action: 'wait', reason: t('campaign.ai.skipped'), source: 'SKIPPED' }, []), rival));
          setAiErrors((current) => current.filter((entry) => entry.nation !== rival));
          setAiRetry((value) => value + 1);
        }}>{t('campaign.ai.skip', { nation: t(`campaign.nations.${rival}`) })}</button>)}
      </div>}
      {campaign.pendingEncounter && <section className="panel campaign-combat-pending" role="status">
        <p>{t('campaign.combat.pending')}</p>
        {battleError && <p role="alert">{t('campaign.combat.failed')}</p>}
        <button className="button button--primary" type="button" disabled={battleOpening} onClick={openEncounter}>{t(battleOpening ? 'campaign.combat.opening' : 'campaign.combat.open')}</button>
      </section>}
      <label className="campaign-reveal"><input type="checkbox" checked={revealMap} onChange={(event) => setRevealMap(event.target.checked)} />{t('campaign.ai.reveal')}</label>
      <div className="campaign-layout" inert={aiPending || aiBusy || Boolean(campaign.pendingEncounter)}>
        <aside className="campaign-sidebar panel" aria-label={t(sidebarMode === 'terrain' ? 'campaign.terrainDetails' : selected ? 'campaign.selectedArmy' : 'campaign.armies')}>
          <div className="campaign-grain"><span className="grain-glyph" aria-hidden="true">&#x131E3;</span><div><strong>{grain}</strong><small>{t('armyBuilder.grainRemaining')}</small></div></div>
          <p className="campaign-upkeep">{t('campaign.upkeep', { grain: formatConsumption(economy.consumption) })}</p>
          <p className="campaign-upkeep">{t('campaign.annualYield', { grain: economy.production })} <span className="grain-glyph" aria-hidden="true">&#x131E3;</span></p>
          <p className={`campaign-situation is-${economy.situation}`}>{t(`campaign.situations.${economy.situation}`)}</p>
          {sidebarMode === 'terrain' ? <TerrainDetails hex={inspectedHex} campaign={campaign} contact={occupied.get(inspectedId)} onBack={showArmies}>
            {selected && occupied.get(inspectedId) && !occupied.get(inspectedId).own && hexDistance(selected.hexId, inspectedId) === 1 && <button className="button button--primary" type="button" disabled={!campaignReady || !remainingMovement(selected)} onClick={() => setCampaign((current) => engageArmy(current, selected.id, occupied.get(inspectedId).id))}>{t('campaign.combat.attack')}</button>}
            {inspectingCapital && <>
              <button className="button button--secondary" type="button" disabled={!campaignReady || loadingUnitTypes || grain < cheapestUnit || !findSpawn(campaign)} onClick={() => setRecruiting(true)}>+ {t('campaign.createArmy')}</button>
              {!findSpawn(campaign) && <p className="campaign-muted">{t('campaign.capitalOccupied')}</p>}
              {!loadingUnitTypes && grain < cheapestUnit && <p className="campaign-muted">{t('campaign.insufficientGrain')}</p>}
            </>}
          </TerrainDetails> : <>
          <div className="campaign-armies-heading"><h2>{selected ? selected.name || t('campaign.defaultArmyName', { number: selected.id }) : t('campaign.armies')}</h2>{!selected && <span>{ownArmies.length}</span>}</div>
          {!selected && (capital ? <button className="button button--secondary" type="button" onClick={inspectCapital}>{t('campaign.goToCapital', { city: cityName(capital, t) })}</button> : <p className="campaign-muted">{t('campaign.noCapital')}</p>)}
          {!ownArmies.length && <div className="campaign-empty"><span aria-hidden="true">⚑</span><p>{t('campaign.empty')}</p></div>}
          <div className="campaign-armies">{(selected ? [selected] : ownArmies).map((army) => {
            const name = army.name || t('campaign.defaultArmyName', { number: army.id });
            const count = armyTroops(army);
            const troops = t(count === 1 ? 'campaign.troopCountOne' : 'campaign.troopCount', { count });
            const morale = t('campaign.armyMorale', { value: army.morale ?? 100 });
            return <button className={`campaign-army ${army.id === selectedId ? 'is-selected' : ''}`} type="button" aria-pressed={army.id === selectedId} aria-label={`${name} · ${troops} · ${morale}`} title={name} key={army.id} onClick={() => focusArmy(army)}>
              <UnitArtwork unitCode="LIGHT_INFANTRY" armyDesignId={army.designId} variant="battlefield" />
              <span><strong>{troops}</strong><small>{morale}</small></span>
            </button>;
          })}</div>
          {selected && <div className="campaign-disband">
            {disbandingId === selected.id ? <>
              <p>{t('campaign.disbandHelp')}</p>
              <div className="campaign-city-action-buttons">
                <button className="button button--ghost" type="button" onClick={() => setDisbandingId(null)}>{t('campaign.cancel')}</button>
                <button className="button button--secondary" type="button" onClick={disband}>{t('campaign.confirmDisband')}</button>
              </div>
            </> : <button className="button button--ghost" type="button" onClick={() => setDisbandingId(selected.id)}>{t('campaign.disbandArmy')}</button>}
          </div>}
          {selected && <section className="campaign-army-composition" aria-label={t('campaign.armyComposition')}>
            {selected.units.filter((unit) => activeUnitCount(unit) > 0).map((unit) => {
              const name = unitTypes.find((type) => type.code === unit.code)?.name || t(`campaign.unitNames.${unit.code}`);
              return <figure className="campaign-unit-group" key={unit.code} title={t('campaign.unitStrength', { unit: name, current: unitTroops(unit), maximum: unit.quantity * unit.initialStrength })}>
                <UnitArtwork unitCode={unit.code} armyDesignId={selected.designId} variant="battlefield" alt={name} />
                <figcaption>×{activeUnitCount(unit)}</figcaption>
              </figure>;
            })}
          </section>}
          {selected && enemyCity && campaignReady && <section className="campaign-city-actions" aria-label={t('campaign.cityActions.title')}>
            <h3>{cityName(selectedCity, t)}</h3>
            <p>{t('campaign.cityActions.enemyCity', { nation: t(`campaign.nations.${cityOwner(campaign, selectedCity)}`) })}</p>
            {!cityRaid(campaign, selectedCity) && <p>{t('campaign.cityActions.raidHelp', { grain: cityProduction(campaign, selectedCity) })}</p>}
            <div className="campaign-city-action-buttons">
              <button className="button button--secondary" type="button" disabled={!campaignReady || Boolean(cityRaid(campaign, selectedCity))} onClick={() => actOnCity('raid')}>{t('campaign.cityActions.raid')}</button>
              <button className="button button--secondary" type="button" disabled={!campaignReady || selected.cityAction?.type === 'assault'} onClick={() => actOnCity('assault')}>{t('campaign.cityActions.assault')}</button>
            </div>
            {cityRaid(campaign, selectedCity) && <p>{t('campaign.cityActions.raided')}</p>}
            {selected.cityAction?.type === 'assault' ? <>
                <p>{t('campaign.cityActions.progress', { elapsed: selected.cityAction.turnsElapsed, required: selected.cityAction.turnsRequired })}</p>
                <progress value={selected.cityAction.turnsElapsed} max={selected.cityAction.turnsRequired} aria-label={t('campaign.cityActions.title')} />
                <p>{t('campaign.cityActions.lossesHelp')}</p>
              </> : <p>{t('campaign.cityActions.estimate', { turns: assaultDuration(selected) })}</p>}
            {selected.cityAction && <button className="button button--ghost" type="button" onClick={() => { setCampaign((current) => cancelCityAction(current, selected.id)); setNotice(t('campaign.cityActions.cancelled')); }}>{t('campaign.cityActions.cancel')}</button>}
          </section>}
          {selected && <button className="button button--secondary" type="button" onClick={showArmies}>{t('campaign.backToArmies')}</button>}
          </>}
          <p className="campaign-save-note">{t('campaign.savedLocally')}</p>
        </aside>
        <section className="campaign-map-panel panel" aria-label={t('campaign.map')}>
          <div className="campaign-map-toolbar"><p>{selected ? t('campaign.moveHint') : t('campaign.selectHint')}</p><div className="campaign-zoom"><button type="button" disabled={zoom <= 1} onClick={() => setZoom((value) => Math.max(1, value - 0.25))} aria-label={t('battle.zoomOut')}>−</button><button type="button" onClick={() => setZoom(1)} aria-label={t('battle.resetZoom')}>{Math.round(zoom * 100)}%</button><button type="button" disabled={zoom >= 2} onClick={() => setZoom((value) => Math.min(2, value + 0.25))} aria-label={t('battle.zoomIn')}>+</button></div></div>
          <div className={`campaign-terrain-info terrain--${inspectedHex.terrain}`} role="status">
            <strong>{t(`campaign.terrain.${inspectedHex.terrain}`)} · {inspectedHex.col + 1}, {inspectedHex.row + 1}</strong>
            <span>{t('campaign.terrainAttrition', { rate: terrainAttrition(campaign, inspectedHex) * 100 })}</span>
            <span>{t(terrain.difficult ? 'campaign.difficultMovement' : inspectedHex.land ? 'campaign.normalMovement' : 'campaign.impassable')}</span>
          </div>
          <div className="campaign-map-scroll" ref={map}>
            <svg className="campaign-map" style={{ width: `${zoom * 100}%` }} viewBox={`0 0 ${MAP_WIDTH} ${MAP_HEIGHT}`} aria-label={t('campaign.map')}>
              <defs><pattern id="campaign-occupation-pattern" patternUnits="userSpaceOnUse" width="8" height="8" patternTransform="rotate(35)"><path d="M0 0V8" stroke="#e8c178" strokeWidth="2" opacity="0.55" /></pattern></defs>
              <image href={egyptMap} x="0" y="0" width={MAP_WIDTH} height={MAP_HEIGHT} />
              {CAMPAIGN_HEXES.map((hex) => {
                const army = occupied.get(hex.id);
                const active = army?.id === selectedId;
                const canMove = reachable.has(hex.id);
                const positionLabel = army ? t('campaign.armyAt', { name: army.own ? `${army.name || t('campaign.defaultArmyName', { number: army.id })} · ${t('campaign.unitCount', { count: army.unitCount })}` : t('campaign.enemyContact', { nation: t(`campaign.nations.${army.designId}`), count: army.unitCount ?? '?' }), col: hex.col + 1, row: hex.row + 1 }) : t('campaign.hex', { col: hex.col + 1, row: hex.row + 1 });
                const territory = campaignTerritoryInfo(campaign, hex);
                const occupationLabel = territory.occupied ? t('campaign.occupation.description', { original: t(`campaign.nations.${territory.originalOwner}`), controller: t(`campaign.nations.${territory.controller}`) }) : '';
                const label = `${occupationLabel ? `${occupationLabel} · ` : ''}${hex.city ? `${cityName(hex.city, t)} · ` : ''}${positionLabel} · ${t(`campaign.terrain.${hex.terrain}`)} · ${t('campaign.terrainAttrition', { rate: terrainAttrition(campaign, hex) * 100 })} · ${t('campaign.productionValue', { amount: hex.city ? cityProduction(campaign, hex.city) : hex.production })} · ${t(TERRAIN_TYPES[hex.terrain].difficult ? 'campaign.difficultMovement' : hex.land ? 'campaign.normalMovement' : 'campaign.impassable')}`;
                return <g key={hex.id} className={`campaign-hex ${!hex.land ? 'is-water' : ''} ${canMove ? 'is-reachable' : ''} ${active ? 'is-selected' : ''} ${army ? 'is-occupied' : ''} ${sidebarMode === 'terrain' && inspectedId === hex.id ? 'is-inspected' : ''}`} role="button" tabIndex={army || hex.city || canMove || inspectedId === hex.id ? 0 : -1} aria-label={label} onClick={() => activateHex(hex)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); activateHex(hex); } }}>
                  <title>{label}</title><polygon points={hex.points} />
                  {territory.occupied && <polygon points={hex.points} aria-hidden="true" pointerEvents="none" style={{ fill: 'url(#campaign-occupation-pattern)', stroke: 'none' }} />}
                  {hex.city && <g className="campaign-city" aria-hidden="true">
                    {isCampaignCapital(campaign, hex.city) && <circle className="campaign-capital-ring" cx={hex.x} cy={hex.y} r="21" style={{ stroke: CAMPAIGN_NATIONS[cityOwner(campaign, hex.city)].color }} />}
                    <image href={cityArtwork} x={hex.x - 20} y={hex.y - 23} width="40" height="40" />
                    <circle className="campaign-city-owner" cx={hex.x - 14} cy={hex.y - 12} r="4" style={{ fill: CAMPAIGN_NATIONS[cityOwner(campaign, hex.city)].color }} />
                  </g>}
                  {canMove && !army && <circle className="campaign-move-dot" cx={hex.x} cy={hex.y} r="3" />}
                </g>;
              })}
              <g className="campaign-borders" aria-hidden="true">{mapBorders.map((border) => <path key={border.id} d={border.path} stroke={CAMPAIGN_NATIONS[border.territory].color} />)}</g>
              <defs><mask id="campaign-vision-mask" maskUnits="userSpaceOnUse" x="0" y="0" width={MAP_WIDTH} height={MAP_HEIGHT}>
                <rect x="0" y="0" width={MAP_WIDTH} height={MAP_HEIGHT} fill="white" />
                <g fill="black">{CAMPAIGN_HEXES.filter((hex) => view.visibleHexIds.has(hex.id)).map((hex) => <polygon key={hex.id} points={hex.points} />)}</g>
              </mask></defs>
              <g className="campaign-fog" aria-hidden="true"><rect x="0" y="0" width={MAP_WIDTH} height={MAP_HEIGHT} mask="url(#campaign-vision-mask)" /></g>
              <g className="campaign-city-labels" aria-hidden="true">{CAMPAIGN_HEXES.filter((hex) => hex.city).map((hex) => <text key={hex.id} className="campaign-city-name" x={hex.x} y={hex.y + 20} textAnchor="middle" opacity={view.visibleHexIds.has(hex.id) ? 1 : 0.3}>{isCampaignCapital(campaign, hex.city) ? '★ ' : ''}{cityName(hex.city, t)}</text>)}</g>
              <g className="campaign-army-markers" aria-hidden="true">{view.armies.map((army) => {
                const hex = HEX_BY_ID.get(army.hexId);
                return <g key={army.id} className={`campaign-army-marker ${army.own ? 'is-own' : 'is-enemy'}`} style={{ '--army-nation-color': CAMPAIGN_NATIONS[army.designId]?.color ?? '#43c7bf' }}>
                  <circle cx={hex.x} cy={hex.y} r="19" />
                  <image href={getBattlefieldUnitArtwork('LIGHT_INFANTRY', army.designId)} x={hex.x - 18} y={hex.y - 23} width="36" height="42" />
                  <circle className="campaign-army-outline" cx={hex.x} cy={hex.y} r="21" />
                  <text x={hex.x + 14} y={hex.y + 19}>{army.unitCount ?? '?'}</text>
                </g>;
              })}</g>
            </svg>
          </div>
          <div className="campaign-map-footer"><span><i />{t('campaign.reachable')}</span><div className="campaign-border-legend">{Object.entries(CAMPAIGN_NATIONS).map(([id, nation]) => <span key={id}><i style={{ background: nation.color }} />{t(`campaign.nations.${id}`)}</span>)}<span><i className="campaign-occupation-key" />{t('campaign.occupation.occupied')}</span></div><small>{t('campaign.mapHelp')}</small></div>
          <p className="campaign-fog-help">{t('campaign.fogHelp')}</p>
        </section>
      </div>
      {report && <section className="campaign-turn-report panel" aria-label={t('campaign.turnReport')}>
        <h2>{t('campaign.turnReport')}</h2>
        <p>{t('campaign.productionReport', { grain: formatGrain(report.producedGrain || 0) })}</p>
        <p>{t('campaign.consumptionReport', { consumed: formatGrain(report.consumedGrain), required: formatGrain(report.requiredGrain) })}</p>
        {report.situation && <p>{t(`campaign.situations.${report.situation}`)}</p>}
        {(report.capturedCities || []).filter((entry) => entry.previousOwner === nation && entry.newOwner !== nation).map((entry) => <p className="campaign-city-lost" key={entry.cityId}>{t('campaign.cityActions.lost', { city: t(`campaign.cityNames.${entry.cityId}`), nation: t(`campaign.nations.${entry.newOwner}`) })}</p>)}
        <ul>{report.armies.filter((entry) => !campaign.armies.some((army) => army.id === entry.armyId && army.designId !== nation)).map((entry) => <li key={entry.armyId}><strong>{entry.name || t('campaign.defaultArmyName', { number: entry.armyId })}</strong><span>{t('campaign.lossReport', { terrain: entry.terrainLosses, supply: entry.supplyLosses })}</span>{entry.assaultLosses > 0 && <span>{t('campaign.cityActions.lossReport', { count: entry.assaultLosses })}</span>}{entry.capturedCityId && <span className="campaign-recovery">{t('campaign.cityActions.captured', { city: t(`campaign.cityNames.${entry.capturedCityId}`) })}</span>}{entry.moraleLosses > 0 && <span>{t('campaign.moraleLossReport', { count: entry.moraleLosses })}</span>}{entry.recoveredMorale > 0 && <span className="campaign-recovery">{t('campaign.moraleRecoveryReport', { count: entry.recoveredMorale })}</span>}{entry.recoveredUnits > 0 && <span className="campaign-recovery">{t('campaign.recoveryReport', { count: entry.recoveredUnits })}</span>}{entry.destroyed && <em>{t('campaign.armyDestroyed')}</em>}</li>)}</ul>
      </section>}
      <p className="campaign-notice" role="status" aria-live="polite">{notice}</p>
      {merging && mergeSource && mergeTarget && <CampaignMergeDialog source={mergeSource} target={mergeTarget} combined={combinedArmy} onCancel={() => setMerging(null)} onConfirm={confirmMerge} />}
      {recruiting && capital && <ArmyRecruitment grain={grain} nation={nation} capital={capital} unitTypes={unitTypes} loading={loadingUnitTypes} onClose={() => setRecruiting(false)} onRecruit={recruit} />}
    </main>
  );
}
