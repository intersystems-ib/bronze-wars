import { useI18n } from '../i18n/I18nContext';
import BattleBoard from './BattleBoard';
import UnitRoster from './UnitRoster';

export default function BattleView({
  battle,
  armyDesignId,
  deployment,
  selectedUnitId,
  busy,
  onSelectUnit,
  onPlaceUnit,
  onStart,
  onRefresh,
  onExit,
}) {
  const { t } = useI18n();
  const humanArmy = battle.armies.find((army) => army.side === 'HUMAN');
  const inDeployment = battle.phase === 'DEPLOYMENT';
  const humanReady = Boolean(deployment?.ready?.human);
  const selectedUnit = humanArmy?.units.find((unit) => String(unit.id) === String(selectedUnitId));

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
        </dl>
        <div className="header-actions">
          <button className="button button--ghost" disabled={busy} onClick={onRefresh} type="button">{t('battle.refresh')}</button>
          <button className="button button--ghost" disabled={busy} onClick={onExit} type="button">{t('battle.newBattle')}</button>
        </div>
      </header>

      <div className="battle-workspace">
        <UnitRoster
          army={humanArmy}
          selectedUnitId={selectedUnitId}
          disabled={!inDeployment || busy}
          onSelect={onSelectUnit}
        />

        <div className="board-column">
          <div className={`command-strip ${humanReady ? 'is-ready' : ''}`}>
            <div>
              <strong>{selectedUnit ? `${t('battle.selected')}: ${selectedUnit.name}` : t('battle.selectInstruction')}</strong>
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
            canDeploy={inDeployment && Boolean(selectedUnitId)}
            busy={busy}
            onCellClick={onPlaceUnit}
          />
        </div>
      </div>
    </main>
  );
}
