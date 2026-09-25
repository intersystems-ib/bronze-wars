import { useCallback, useEffect, useState } from 'react';
import { api } from './api/client';
import AppNavigation from './components/AppNavigation';
import BattleSetup from './components/BattleSetup';
import BattleView from './components/BattleView';
import LanguageSwitcher from './components/LanguageSwitcher';
import LoadBattlePage from './components/LoadBattlePage';
import { DEFAULT_ARMY_DESIGN_ID, getArmyDesign, getArmyDesignForFaction } from './config/armyDesigns';
import { useI18n } from './i18n/I18nContext';

const BATTLE_DESIGN_STORAGE_PREFIX = 'bronzewars.battle-design.';

function storedArmyDesign(battleId) {
  try {
    return getArmyDesign(localStorage.getItem(`${BATTLE_DESIGN_STORAGE_PREFIX}${battleId}`)).id;
  } catch {
    return DEFAULT_ARMY_DESIGN_ID;
  }
}

function storeArmyDesign(battleId, designId) {
  try {
    localStorage.setItem(`${BATTLE_DESIGN_STORAGE_PREFIX}${battleId}`, getArmyDesign(designId).id);
  } catch {
    // The battle remains playable when browser storage is unavailable.
  }
}

function wait(milliseconds) {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function moveBattleUnit(battleState, unitId, position) {
  return {
    ...battleState,
    armies: battleState.armies.map((army) => ({
      ...army,
      units: army.units.map((unit) => (
        String(unit.id) === String(unitId) ? { ...unit, position: { ...position } } : unit
      )),
    })),
  };
}

export default function App() {
  const { t } = useI18n();
  const [unitTypes, setUnitTypes] = useState([]);
  const [battle, setBattle] = useState(null);
  const [deployment, setDeployment] = useState(null);
  const [armyDesignId, setArmyDesignId] = useState(DEFAULT_ARMY_DESIGN_ID);
  const [selectedUnitId, setSelectedUnitId] = useState(null);
  const [startView, setStartView] = useState('create');
  const [navigationOpen, setNavigationOpen] = useState(false);
  const [loadingUnitTypes, setLoadingUnitTypes] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [turnConfirmation, setTurnConfirmation] = useState(null);
  const [deployingEnemy, setDeployingEnemy] = useState(false);
  const [animatingUnitId, setAnimatingUnitId] = useState(null);

  const showError = useCallback((caughtError) => {
    setError({
      code: caughtError.code || 'UNKNOWN_ERROR',
      message: caughtError.message,
    });
  }, []);

  const loadBattle = useCallback(async (battleId) => {
    const battlePayload = await api.getBattle(battleId);
    setBattle(battlePayload.battle);
    const humanArmy = battlePayload.battle.armies.find((army) => army.side === 'HUMAN');
    setArmyDesignId(humanArmy?.faction ? getArmyDesignForFaction(humanArmy.faction).id : storedArmyDesign(battleId));
    if (battlePayload.battle.phase === 'DEPLOYMENT') {
      const deploymentPayload = await api.getDeployment(battleId);
      setDeployment(deploymentPayload);
    } else {
      setDeployment(null);
    }
  }, []);

  useEffect(() => {
    api.listUnitTypes()
      .then((payload) => setUnitTypes(payload.items))
      .catch(showError)
      .finally(() => setLoadingUnitTypes(false));
  }, [showError]);

  async function run(action) {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (caughtError) {
      showError(caughtError);
    } finally {
      setBusy(false);
    }
  }

  function createBattle(input) {
    run(async () => {
      const { armyDesignId: selectedDesignId, ...battleInput } = input;
      const payload = await api.createBattle(battleInput);
      const resolvedDesignId = getArmyDesign(selectedDesignId).id;
      storeArmyDesign(payload.battle.id, resolvedDesignId);
      setArmyDesignId(resolvedDesignId);
      setBattle(payload.battle);
      const deploymentPayload = await api.getDeployment(payload.battle.id);
      setDeployment(deploymentPayload);
      setSelectedUnitId(null);
    });
  }

  function resumeBattle(battleId) {
    run(async () => {
      await loadBattle(battleId);
      setSelectedUnitId(null);
    });
  }

  function placeUnit(unitId, position) {
    if (!battle || !unitId) return;
    run(async () => {
      await api.placeUnit(battle.id, unitId, position);
      await loadBattle(battle.id);
      setSelectedUnitId(null);
    });
  }

  function moveUnit(unitId, position) {
    if (!battle || !unitId) return;
    run(async () => {
      await api.moveUnit(battle.id, unitId, position);
      await loadBattle(battle.id);
    });
  }

  async function advanceTurn(confirmIncomplete = false) {
    if (!battle) return;
    setBusy(true);
    setError(null);
    try {
      const payload = await api.nextTurn(battle.id, confirmIncomplete);
      setTurnConfirmation(null);
      for (const movement of payload.aiMovementTrace || []) {
        setAnimatingUnitId(movement.unitId);
        for (const position of movement.path || []) {
          setBattle((currentBattle) => moveBattleUnit(currentBattle, movement.unitId, position));
          await wait(320);
        }
      }
      setBattle(payload.battle);
    } catch (caughtError) {
      if (caughtError.code === 'UNITS_PENDING_MOVEMENT') {
        setTurnConfirmation({ pendingUnits: caughtError.details?.pendingUnits || 0 });
      } else {
        showError(caughtError);
      }
    } finally {
      setAnimatingUnitId(null);
      setBusy(false);
    }
  }

  async function startBattle() {
    if (!battle) return;
    setBusy(true);
    setDeployingEnemy(true);
    setError(null);
    try {
      const payload = await api.startBattle(battle.id);
      setBattle(payload.battle);
      setDeployment(null);
      setSelectedUnitId(null);
    } catch (caughtError) {
      showError(caughtError);
    } finally {
      setDeployingEnemy(false);
      setBusy(false);
    }
  }

  function leaveBattle() {
    setBattle(null);
    setDeployment(null);
    setSelectedUnitId(null);
    setArmyDesignId(DEFAULT_ARMY_DESIGN_ID);
    setTurnConfirmation(null);
    setDeployingEnemy(false);
    setAnimatingUnitId(null);
    setStartView('create');
  }

  const errorBanner = error && (
    <div className="error-banner" role="alert">
      <span>{t(`errors.${error.code}`) === `errors.${error.code}` ? error.message : t(`errors.${error.code}`)}</span>
      <button onClick={() => setError(null)} type="button" aria-label={t('app.close')}>×</button>
    </div>
  );

  return (
    <div className="app-shell">
      <div className="ambient ambient--one" />
      <div className="ambient ambient--two" />
      {battle ? (
        <>
          <nav className="topbar">
            <a className="brand" href="/" onClick={(event) => { event.preventDefault(); leaveBattle(); }}>
              <span className="brand-mark"><i>BW</i></span>
              <span><strong>{t('app.title')}</strong><small>{t('app.subtitle')}</small></span>
            </a>
            <LanguageSwitcher />
          </nav>
          {errorBanner}
          {deployingEnemy && (
            <div className="enemy-deployment-overlay" role="dialog" aria-modal="true" aria-labelledby="enemy-deployment-title">
              <div className="enemy-deployment-modal panel">
                <span className="enemy-deployment-spinner" aria-hidden="true" />
                <strong id="enemy-deployment-title">{t('battle.enemyFormationDeploying')}</strong>
                <span>{t('battle.enemyFormationDeployingDetail')}</span>
              </div>
            </div>
          )}
          <BattleView
            battle={battle}
            armyDesignId={armyDesignId}
            deployment={deployment}
            selectedUnitId={selectedUnitId}
            animatingUnitId={animatingUnitId}
            busy={busy}
            onSelectUnit={(unit) => setSelectedUnitId(unit?.id || null)}
            onPlaceUnit={placeUnit}
            onMoveUnit={moveUnit}
            onStart={startBattle}
            onNextTurn={() => advanceTurn(false)}
            turnConfirmation={turnConfirmation}
            onConfirmNextTurn={() => advanceTurn(true)}
            onCancelNextTurn={() => setTurnConfirmation(null)}
            onExit={leaveBattle}
          />
          <footer>BronzeWars · InterSystems IRIS</footer>
        </>
      ) : (
        <div className="start-shell">
          <header className="start-toolbar">
            <button className="menu-button" type="button" onClick={() => setNavigationOpen(true)} aria-label={t('navigation.open')}>
              <span /><span /><span />
            </button>
            <div className="toolbar-brand">
              <strong>{t('app.title')}</strong>
              <small>{t('app.subtitle')}</small>
            </div>
            <LanguageSwitcher />
          </header>
          <AppNavigation
            activeView={startView}
            open={navigationOpen}
            onChange={(view) => { setStartView(view); setError(null); }}
            onClose={() => setNavigationOpen(false)}
          />
          <div className="start-content">
            {errorBanner}
            {startView === 'load' ? (
              <LoadBattlePage busy={busy} onResume={resumeBattle} />
            ) : (
              <BattleSetup
                unitTypes={unitTypes}
                loadingUnitTypes={loadingUnitTypes}
                armyDesignId={armyDesignId}
                busy={busy}
                onArmyDesignChange={setArmyDesignId}
                onCreate={createBattle}
              />
            )}
          </div>
        </div>
      )}
    </div>
  );
}
