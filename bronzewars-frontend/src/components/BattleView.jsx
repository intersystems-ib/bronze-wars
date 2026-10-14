import { useState } from 'react';
import { useI18n } from '../i18n/I18nContext';
import BattleBoard from './BattleBoard';
import BattleEncounterModal from './BattleEncounterModal';
import UnitInspector from './UnitInspector';
import UnitRoster from './UnitRoster';

function armySurrenderMetrics(army) {
  const units = army?.units || [];
  const initialSoldiers = units.reduce((total, unit) => (
    total + Math.max(0, Number(unit.type?.initialStrength) || Number(unit.currentStrength) || 0)
  ), 0);
  const activeUnits = units.filter((unit) => unit.active !== false && Number(unit.currentStrength) > 0);
  const survivingSoldiers = activeUnits.reduce(
    (total, unit) => total + Math.max(0, Number(unit.currentStrength) || 0),
    0,
  );
  const totalMorale = activeUnits.reduce(
    (total, unit) => total + (Math.max(0, Number(unit.morale ?? 100)) * Math.max(0, Number(unit.currentStrength) || 0)),
    0,
  );

  return {
    troopPercentage: initialSoldiers > 0 ? Math.min(100, (survivingSoldiers / initialSoldiers) * 100) : 0,
    moralePercentage: initialSoldiers > 0 ? Math.min(100, totalMorale / initialSoldiers) : 0,
  };
}

function ArmyScore({ army, side, color }) {
  const metrics = armySurrenderMetrics(army);
  const name = army?.name || side;
  const scores = [
    { label: 'Tropas', value: metrics.troopPercentage },
    { label: 'Moral', value: metrics.moralePercentage },
  ];

  return (
    <div className={`battle-status__team battle-status__team--${side}`} style={{ display: 'grid', gap: '6px' }}>
      <strong style={{ color }}>{name}</strong>
      {scores.map(({ label, value }) => {
        const percentage = Math.round(value);
        const accessibleLabel = `${name}, ${label}: ${percentage}%`;
        return (
          <div className="battle-status__metric" key={label}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '3px' }}>
              <span>{label}</span>
              <span>{percentage}%</span>
            </div>
            <div
              aria-label={accessibleLabel}
              aria-valuemax="100"
              aria-valuemin="0"
              aria-valuenow={percentage}
              className="battle-status__bar"
              role="progressbar"
              style={{ height: '10px', overflow: 'hidden', borderRadius: '999px', backgroundColor: '#403a31' }}
            >
              <span style={{ display: 'block', width: `${value}%`, height: '100%', backgroundColor: color, transition: 'width 250ms ease' }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

function BattleStatusBar({ humanArmy, aiArmy }) {
  const label = `${humanArmy?.name || 'Human'} y ${aiArmy?.name || 'AI'}: porcentajes de tropas y moral supervivientes.`;

  return (
    <section
      aria-label={label}
      className="battle-status"
      style={{ display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: '16px', padding: '10px 0' }}
    >
      <ArmyScore army={humanArmy} side="human" color="#d7a842" />
      <ArmyScore army={aiArmy} side="ai" color="#b34d3e" />
    </section>
  );
}

export default function BattleView({
  battle,
  armyDesignId,
  deployment,
  selectedUnitId,
  animatingUnitId,
  automaticEncounter,
  busy,
  onSelectUnit,
  onPlaceUnit,
  onMoveUnit,
  onAttackUnit,
  onStart,
  onNextTurn,
  turnConfirmation,
  onTurnConfirmationChange,
  onConfirmNextTurn,
  onCancelNextTurn,
  onAutomaticEncounterClose,
  onSurrender,
  onExit,
}) {
  const { t } = useI18n();
  const humanArmy = battle.armies.find((army) => army.side === 'HUMAN');
  const aiArmy = battle.armies.find((army) => army.side === 'AI');
  const commanderType = aiArmy?.commanderType;
  const inDeployment = battle.phase === 'DEPLOYMENT';
  const inMovement = battle.phase === 'MOVEMENT';
  const canAttack = inMovement || battle.phase === 'COMBAT';
  const humanReady = Boolean(deployment?.ready?.human);
  const selectedArmy = battle.armies.find((army) => army.units.some((unit) => String(unit.id) === String(selectedUnitId)));
  const selectedUnit = selectedArmy?.units.find((unit) => String(unit.id) === String(selectedUnitId));
  const [draggedUnitId, setDraggedUnitId] = useState(null);
  const [encounterTargetId, setEncounterTargetId] = useState(null);
  const [encounterResult, setEncounterResult] = useState(null);
  const encounterArmy = battle.armies.find((army) => army.units.some((unit) => String(unit.id) === String(encounterTargetId)));
  const encounterTarget = encounterArmy?.units.find((unit) => String(unit.id) === String(encounterTargetId));
  const automaticAttackerArmy = battle.armies.find((army) => army.units.some((unit) => String(unit.id) === String(automaticEncounter?.attackerUnitId)));
  const automaticAttacker = automaticAttackerArmy?.units.find((unit) => String(unit.id) === String(automaticEncounter?.attackerUnitId));
  const automaticDefenderArmy = battle.armies.find((army) => army.units.some((unit) => String(unit.id) === String(automaticEncounter?.defenderUnitId)));
  const automaticDefender = automaticDefenderArmy?.units.find((unit) => String(unit.id) === String(automaticEncounter?.defenderUnitId));

  function selectUnit(unit) {
    setEncounterTargetId(null);
    setEncounterResult(null);
    onSelectUnit(unit);
  }

  function openEncounter(unit) {
    setEncounterResult(null);
    setEncounterTargetId(unit.id);
  }

  async function resolveEncounter() {
    const result = await onAttackUnit(selectedUnit?.id, encounterTarget?.id);
    if (result) setEncounterResult(result);
  }

  function placeUnit(unitId, position) {
    setDraggedUnitId(null);
    onPlaceUnit(unitId, position);
  }

  function finishDragging() {
    setDraggedUnitId(null);
    if (inDeployment) selectUnit(null);
  }

  function beginBoardDrag(unitId) {
    setDraggedUnitId(unitId);
    const army = battle.armies.find((candidate) => candidate.units.some((unit) => String(unit.id) === String(unitId)));
    const unit = army?.units.find((candidate) => String(candidate.id) === String(unitId));
    if (unit) selectUnit(unit);
  }

  return (
    <main className="battle-layout">
      {turnConfirmation && (
        <div className="turn-confirmation-overlay" role="presentation">
          <section className="turn-confirmation panel" role="alertdialog" aria-modal="true" aria-labelledby="turn-confirmation-title" aria-describedby="turn-confirmation-message">
            <div>
              <strong id="turn-confirmation-title">{t('battle.pendingMovementTitle')}</strong>
              <span id="turn-confirmation-message">{t('battle.pendingMovementMessage', { count: turnConfirmation.pendingUnits })}</span>
            </div>
            <label className="turn-confirmation__preference">
              <input
                checked={Boolean(turnConfirmation.dontShowAgain)}
                disabled={busy}
                onChange={(event) => onTurnConfirmationChange(event.target.checked)}
                type="checkbox"
              />
              <span>{t('battle.dontShowTurnWarningAgain')}</span>
            </label>
            <div className="turn-confirmation__actions">
              <button className="button button--ghost" disabled={busy} onClick={onCancelNextTurn} type="button">{t('battle.stayInTurn')}</button>
              <button className="button button--primary" disabled={busy} onClick={onConfirmNextTurn} type="button">{t('battle.advanceAnyway')}</button>
            </div>
          </section>
        </div>
      )}

      <div className="battle-workspace">
        <div className="battle-sidebar">
          <section className="battle-controls panel">
            <div>
              <p className="eyebrow">{t('battle.battle')} #{battle.id}</p>
              <h1>{battle.name}</h1>
            </div>
            <dl className="battle-controls__meta">
              <div><dt>{t('battle.round')}</dt><dd>{battle.currentRound}</dd></div>
              {commanderType && (
                <div><dt>{t('battle.aiCommander')}</dt><dd>{t(`commanderTypes.${commanderType}`)}</dd></div>
              )}
            </dl>
            <div className="battle-controls__actions">
              {inDeployment ? (
                <button className="button button--primary" disabled={!humanReady || busy} onClick={onStart} type="button">
                  {busy ? t('battle.starting') : t('battle.start')}
                </button>
              ) : (
                <button className="button button--secondary" disabled={busy || !inMovement} onClick={onNextTurn} type="button">
                  {t('battle.nextTurn')}
                </button>
              )}
              {!inDeployment && (
                <button className="button button--ghost" disabled={busy} onClick={onSurrender} type="button">{t('battle.surrender')}</button>
              )}
            </div>
          </section>

          {inDeployment ? (
            <UnitRoster
              army={humanArmy}
              selectedUnitId={selectedUnitId}
              disabled={busy}
              onSelect={onSelectUnit}
              onDragStart={setDraggedUnitId}
              onDragEnd={finishDragging}
            />
          ) : (
            <UnitInspector unit={selectedUnit} army={selectedArmy} />
          )}
        </div>

        <div className="board-column">
          {!inDeployment && <BattleStatusBar humanArmy={humanArmy} aiArmy={aiArmy} />}
          <BattleBoard
            battle={battle}
            armyDesignId={armyDesignId}
            selectedUnitId={selectedUnitId}
            animatingUnitId={animatingUnitId}
            draggedUnitId={draggedUnitId}
            canDeploy={inDeployment}
            canMove={inMovement}
            canAttack={canAttack}
            busy={busy}
            onUnitDragStart={beginBoardDrag}
            onUnitDragEnd={finishDragging}
            onUnitDrop={placeUnit}
            onUnitMove={onMoveUnit}
            onUnitSelect={selectUnit}
            onAttackTarget={openEncounter}
          />
        </div>
      </div>

      {!automaticEncounter && encounterTarget && selectedUnit && selectedArmy && encounterArmy && (
        <BattleEncounterModal
          attacker={selectedUnit}
          attackerArmy={selectedArmy}
          defender={encounterTarget}
          defenderArmy={encounterArmy}
          busy={busy}
          attackType={encounterResult?.type || (
            selectedUnit.position && encounterTarget.position
              && Math.abs(selectedUnit.position.x - encounterTarget.position.x) + Math.abs(selectedUnit.position.y - encounterTarget.position.y) === 1
              ? 'MELEE'
              : 'RANGED'
          )}
          result={encounterResult}
          onResolve={resolveEncounter}
          onClose={() => { setEncounterTargetId(null); setEncounterResult(null); }}
        />
      )}
      {automaticEncounter && automaticAttacker && automaticAttackerArmy && automaticDefender && automaticDefenderArmy && (
        <BattleEncounterModal
          attacker={automaticAttacker}
          attackerArmy={automaticAttackerArmy}
          defender={automaticDefender}
          defenderArmy={automaticDefenderArmy}
          busy={false}
          attackType={automaticEncounter.type}
          result={automaticEncounter}
          automatic
          onResolve={() => {}}
          onClose={onAutomaticEncounterClose}
        />
      )}
    </main>
  );
}
