import { useState } from 'react';
import { useI18n } from '../i18n/I18nContext';
import BattleBoard from './BattleBoard';
import BattleEncounterModal from './BattleEncounterModal';
import UnitInspector from './UnitInspector';
import UnitRoster from './UnitRoster';

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
  onConfirmNextTurn,
  onCancelNextTurn,
  onAutomaticEncounterClose,
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
      <header className="battle-header panel">
        <div>
          <p className="eyebrow">{t('battle.battle')} #{battle.id}</p>
          <h1>{battle.name}</h1>
        </div>
        <dl className="battle-meta">
          <div><dt>{t('battle.status')}</dt><dd>{t(`statuses.${battle.status}`)}</dd></div>
          <div><dt>{t('battle.phase')}</dt><dd>{t(`phases.${battle.phase}`)}</dd></div>
          <div><dt>{t('battle.round')}</dt><dd>{battle.currentRound}</dd></div>
          {commanderType && (
            <div><dt>{t('battle.aiCommander')}</dt><dd>{t(`commanderTypes.${commanderType}`)}</dd></div>
          )}
        </dl>
        <div className="header-actions">
          {!inDeployment && (
            <button className="button button--secondary" disabled={busy || !inMovement} onClick={onNextTurn} type="button">
              {t('battle.nextTurn')}
            </button>
          )}
          <button className="button button--ghost" disabled={busy} onClick={onExit} type="button">{t('battle.newBattle')}</button>
        </div>
      </header>

      {turnConfirmation && (
        <section className="turn-confirmation panel" role="alertdialog" aria-labelledby="turn-confirmation-title">
          <div>
            <strong id="turn-confirmation-title">{t('battle.pendingMovementTitle')}</strong>
            <span>{t('battle.pendingMovementMessage', { count: turnConfirmation.pendingUnits })}</span>
          </div>
          <div className="turn-confirmation__actions">
            <button className="button button--ghost" disabled={busy} onClick={onCancelNextTurn} type="button">{t('battle.stayInTurn')}</button>
            <button className="button button--primary" disabled={busy} onClick={onConfirmNextTurn} type="button">{t('battle.advanceAnyway')}</button>
          </div>
        </section>
      )}

      <div className="battle-workspace">
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

        <div className="board-column">
          <div className={`command-strip ${humanReady ? 'is-ready' : ''}`}>
            <div>
              <strong>{selectedUnit ? `${t('battle.selected')}: ${selectedUnit.type.name}` : t('battle.dragInstruction')}</strong>
              <span>
                {!inDeployment
                  ? t('battle.startedInstruction')
                  : humanReady
                    ? t('battle.deploymentComplete')
                    : t('battle.deploymentPending')}
              </span>
            </div>
            {inDeployment && (
              <button className="button button--primary" disabled={!humanReady || busy} onClick={onStart} type="button">
                {busy ? t('battle.starting') : t('battle.start')}
              </button>
            )}
          </div>

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
