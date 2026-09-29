Class BronzeWars.Tests.ServiceTest Extends %UnitTest.TestCase
{

Method Test00ProductionArchitecture()
{
    set running = ##class(Ens.Director).IsProductionRunning(.production)
    do $$$AssertTrue(running, "The interoperability production is running")
    do $$$AssertEquals(production, "BronzeWars.Interop.Production", "The expected production is active")

    for item = "Unit Type Service","Battle Service","Deployment Service","Unit Type Process","Battle Process","Deployment Process","Data Operation","LLM Operation" {
        set enabled = ##class(Ens.Director).IsItemEnabled(item, .sc)
        do $$$AssertStatusOK(sc, item _ " can be inspected")
        do $$$AssertTrue(enabled, item _ " is enabled")
    }
}

Method Test01CreateBattle()
{
    set result = ##class(BronzeWars.Interop.Client).CreateBattle({"name":"Service creation test"})
    do $$$AssertTrue(result.ok, "A battle is created")
    do $$$AssertEquals(result.status, 201, "Creation returns status 201")
    set battle = result.data.battle
    do $$$AssertEquals(battle.status, "CREATED", "Initial status is CREATED")
    do $$$AssertEquals(battle.phase, "DEPLOYMENT", "Initial phase is DEPLOYMENT")
    do $$$AssertEquals(battle.currentRound, 0, "Initial round is zero")
    do $$$AssertEquals(battle.board.width, 16, "Default board width is 16")
    do $$$AssertEquals(battle.board.height, 12, "Default board height is 12")
    do $$$AssertEquals(battle.armies.%Size(), 2, "Two armies are created")
    do $$$AssertEquals(battle.armies.%Get(0).units.%Size(), 10, "Human army uses the default ten-unit composition")
    do $$$AssertEquals(battle.armies.%Get(1).units.%Size(), 0, "AI composition remains hidden and undecided during human deployment")
    do $$$AssertEquals(battle.armies.%Get(1).commanderType, "", "AI commander remains undecided until battle start")
    set firstUnit = battle.armies.%Get(0).units.%Get(0)
    do $$$AssertTrue(firstUnit.currentStrength > 0, "Unit strength is copied from its type")
    do $$$AssertEquals(firstUnit.morale, 100, "Units begin with full morale")
    do $$$AssertTrue(firstUnit.type.attack > 0, "Battle units expose their combat characteristics")
    do $$$AssertEquals(firstUnit.isDeployed, 0, "Units begin undeployed")
    do $$$AssertEquals(firstUnit.hasMoved, 0, "Units begin without movement")
    do $$$AssertEquals(firstUnit.active, 1, "Units begin active")
}

Method Test02PlacementRules()
{
    set battle1 = ..CreateBattle("Placement rules one")
    set battle2 = ..CreateBattle("Placement rules two")
    set human1 = battle1.armies.%Get(0)
    set unit1 = human1.units.%Get(0).id
    set unit2 = human1.units.%Get(1).id

    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, unit1, 5, 10)
    do $$$AssertTrue(result.ok, "A human unit can be placed in its zone")
    do $$$AssertEquals(result.data.unit.position.x, 5, "Placed X coordinate is persisted")
    do $$$AssertEquals(result.data.unit.position.y, 10, "Placed Y coordinate is persisted")

    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, unit1, 6, 10)
    do $$$AssertTrue(result.ok, "A human unit can be relocated")
    do $$$AssertEquals(result.data.unit.position.x, 6, "Relocation replaces the previous position")

    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, unit2, 16, 10)
    do $$$AssertEquals(result.code, "POSITION_OUT_OF_BOUNDS", "Out-of-bounds placement is rejected")
    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, unit2, 3, 8)
    do $$$AssertEquals(result.code, "POSITION_OUTSIDE_DEPLOYMENT_ZONE", "Placement outside the human zone is rejected")
    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, unit2, 6, 10)
    do $$$AssertEquals(result.code, "CELL_OCCUPIED", "An occupied cell is rejected")
    set humanUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unit1), aiArmy = ..FindArmy(battle1.id, "AI")
    set aiUnit = ##class(BronzeWars.Model.BattleUnit).%New(humanUnit.UnitType, humanUnit.UnitProfile)
    set aiUnit.Battle = humanUnit.Battle, aiUnit.Army = aiArmy, aiUnit.Name = "Placement rule AI unit"
    set sc = aiUnit.%Save()
    do $$$AssertStatusOK(sc, "An AI fixture unit can be created")
    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, aiUnit.%Id(), 0, 9)
    do $$$AssertEquals(result.code, "NOT_HUMAN_UNIT", "An AI unit cannot be placed through the public use case")
    set foreignUnit = battle2.armies.%Get(0).units.%Get(0).id
    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, foreignUnit, 0, 9)
    do $$$AssertEquals(result.code, "UNIT_NOT_IN_BATTLE", "A unit from another battle is rejected")
}

Method Test03StartAndRollback()
{
    set battleJSON = ..CreateBattle("Start and rollback test")
    set battleId = battleJSON.id
    set result = ##class(BronzeWars.Interop.Client).StartBattle(battleId)
    do $$$AssertEquals(result.code, "HUMAN_DEPLOYMENT_INCOMPLETE", "A battle cannot start with an incomplete human deployment")

    set human = battleJSON.armies.%Get(0)
    for i = 0:1:(human.units.%Size() - 1) {
        set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battleId, human.units.%Get(i).id, i, 9)
        do $$$AssertTrue(result.ok, "Human deployment position " _ i _ " is accepted")
    }

    set failed = ##class(BronzeWars.Interop.Client).StartBattle(battleId, 1)
    do $$$AssertEquals(failed.status, 500, "A forced start failure is reported")
    set storedBattle = ##class(BronzeWars.Model.Battle).%OpenId(battleId)
    do $$$AssertEquals(storedBattle.Status, "CREATED", "A failed start rolls the battle status back")
    set aiArmy = ..FindArmy(battleId, "AI")
    set aiArmyId = aiArmy.%Id()
    &sql(SELECT COUNT(*) INTO :deployedAfterFailure FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND IsDeployed = 1)
    do $$$AssertEquals(deployedAfterFailure, 0, "A failed start rolls the AI deployment back")

    set started = ##class(BronzeWars.Interop.Client).StartBattle(battleId)
    do $$$AssertTrue(started.ok, "A fully deployed battle starts")
    do $$$AssertEquals(started.data.battle.status, "IN_PROGRESS", "Started status is IN_PROGRESS")
    do $$$AssertEquals(started.data.battle.phase, "MOVEMENT", "Started phase is MOVEMENT")
    do $$$AssertEquals(started.data.battle.currentRound, 1, "Started round is one")

    set humanArmyId = human.id
    &sql(SELECT COUNT(*) INTO :initialMoraleErrors FROM BronzeWars_Model.BattleUnit WHERE Battle = :battleId AND Active = 1 AND IsDeployed = 1 AND Morale <> 100)
    do $$$AssertEquals(initialMoraleErrors, 0, "Every deployed unit starts the battle with 100 morale")

    set aiArmy = ..FindArmy(battleId, "AI"), aiArmyId = aiArmy.%Id()
    do $$$AssertTrue(##class(BronzeWars.AI.Commanders.Strategy).IsValid(aiArmy.CommanderType), "Battle start selects and persists a valid random AI commander")
    do $$$AssertEquals(started.data.battle.armies.%Get(1).commanderType, aiArmy.CommanderType, "The API exposes the selected AI commander")
    do $$$AssertTrue(##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(aiArmy), "The AI is completely and legally deployed")
    &sql(SELECT COUNT(*), MIN(u.PositionX), MAX(u.PositionX) INTO :aiLineCount, :aiLineMin, :aiLineMax FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.PositionY = 1 AND t.Code IN ('SPEARMEN','HEAVY_INFANTRY','MERCENARIES'))
    &sql(SELECT MIN(PositionX), MAX(PositionX) INTO :aiFormationMin, :aiFormationMax FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1 AND IsDeployed = 1)
    &sql(SELECT COUNT(*) INTO :mobileFlankUnits FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.PositionX IN (:aiFormationMin, :aiFormationMax) AND t.Code IN ('LIGHT_INFANTRY','LIGHT_CAVALRY','HEAVY_CAVALRY','CHARIOTS'))
    &sql(SELECT COUNT(*) INTO :aiLineMoraleErrors FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.PositionY = 1 AND t.Code IN ('SPEARMEN','HEAVY_INFANTRY','MERCENARIES') AND u.Morale <> 100)
    set expectedLine = ##class(BronzeWars.AI.Commanders.Strategy).MainLineTarget(aiArmy.CommanderType, 10, 16)
    do $$$AssertTrue(aiLineCount >= expectedLine, "The AI infantry line follows its commander doctrine")
    if aiArmy.CommanderType = "FLANKER" {
        do $$$AssertTrue((aiFormationMax - aiFormationMin + 1) > 10, "A flanking commander exceeds the human frontage")
        do $$$AssertEquals(mobileFlankUnits, 2, "A flanking commander places a mobile unit on both extremes")
    }
    do $$$AssertEquals(aiLineCount, aiLineMax - aiLineMin + 1, "The AI infantry line has no gaps")
    do $$$AssertEquals(aiLineMoraleErrors, 0, "Every unit in the AI main line starts with full morale")

    set mobileUnitId = "", mobileUnitX = "", mobileUnitSpeed = 0
    for i = 0:1:(human.units.%Size() - 1) {
        if (mobileUnitId = ""), (human.units.%Get(i).type.speed >= 2) set mobileUnitId = human.units.%Get(i).id, mobileUnitX = i, mobileUnitSpeed = human.units.%Get(i).type.speed
    }
    do $$$AssertNotEquals(mobileUnitId, "", "The army contains a unit able to move several cells")
    set invalidMove = ##class(BronzeWars.Interop.Client).MoveUnit(battleId, mobileUnitId, mobileUnitX + 1, 8)
    do $$$AssertEquals(invalidMove.code, "INVALID_MOVEMENT_STEP", "Diagonal movement is rejected")
    set moved = ##class(BronzeWars.Interop.Client).MoveUnit(battleId, mobileUnitId, mobileUnitX, 7)
    do $$$AssertTrue(moved.ok, "A human unit can move several cells in one cardinal direction")
    do $$$AssertEquals(moved.data.unit.hasMoved, 1, "A moved unit is marked as moved")
    do $$$AssertEquals(moved.data.unit.movementSpent, 2, "The travelled distance consumes movement points")
    do $$$AssertEquals(moved.data.unit.remainingMovement, mobileUnitSpeed - 2, "The response reports the remaining movement")

    set pendingTurn = ##class(BronzeWars.Interop.Client).NextTurn(battleId)
    do $$$AssertEquals(pendingTurn.code, "UNITS_PENDING_MOVEMENT", "Advancing warns when units have not moved")
    do $$$AssertEquals(pendingTurn.details.pendingUnits, human.units.%Size() - 1, "The warning reports pending human units")
    &sql(SELECT COUNT(*) INTO :situationToolCallsBefore FROM BronzeWars_AI_Audit.ToolExecution WHERE ToolName = 'GetBattleSituation')
    set advancedTurn = ##class(BronzeWars.Interop.Client).NextTurn(battleId, 1)
    do $$$AssertTrue(advancedTurn.ok, "The turn can be advanced after confirmation")
    do $$$AssertEquals(advancedTurn.data.battle.currentRound, 2, "Advancing starts the next round")
    &sql(SELECT COUNT(*) INTO :situationToolCallsAfter FROM BronzeWars_AI_Audit.ToolExecution WHERE ToolName = 'GetBattleSituation')
    do $$$AssertTrue(situationToolCallsAfter > situationToolCallsBefore, "The movement agent invokes and audits GetBattleSituation during the turn decision")
    &sql(SELECT COUNT(*) INTO :aiMovementPlans FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_MOVEMENT_PLANNED')
    &sql(SELECT COUNT(*) INTO :aiMovementEvents FROM BronzeWars_Model.BattleEvent e JOIN BronzeWars_Model.BattleUnit u ON e.ActorUnit = u.%ID JOIN BronzeWars_Model.Army a ON u.Army = a.%ID WHERE e.Battle = :battleId AND e.EventType = 'UNIT_MOVED' AND a.Side = 'AI')
    &sql(SELECT COUNT(DISTINCT u.PositionY), COUNT(*), MIN(u.PositionX), MAX(u.PositionX) INTO :aiLineRowsAfterMove, :aiLineCountAfterMove, :aiLineMinAfterMove, :aiLineMaxAfterMove FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND t.Code IN ('SPEARMEN','HEAVY_INFANTRY','MERCENARIES'))
    do $$$AssertEquals(aiMovementPlans, 1, "The AI commander records one movement plan at the end of the human turn")
    do $$$AssertTrue(aiMovementEvents > 0, "The AI moves at least one unit")
    set movementTrace = advancedTurn.data.aiMovementTrace
    do $$$AssertTrue($isobject(movementTrace), "The turn response includes an AI movement trace")
    do $$$AssertEquals(movementTrace.%Size(), aiMovementEvents, "The trace includes every AI unit that moved")
    for traceIndex = 0:1:(movementTrace.%Size() - 1) {
        set tracedMovement = movementTrace.%Get(traceIndex), tracedPosition = tracedMovement.%Get("from"), tracedPath = tracedMovement.path
        do $$$AssertTrue(tracedPath.%Size() > 0, "Every traced movement contains at least one step")
        for pathIndex = 0:1:(tracedPath.%Size() - 1) {
            set tracedStep = tracedPath.%Get(pathIndex), tracedDeltaX = tracedStep.x - tracedPosition.x, tracedDeltaY = tracedStep.y - tracedPosition.y
            if tracedDeltaX < 0 set tracedDeltaX = -tracedDeltaX
            if tracedDeltaY < 0 set tracedDeltaY = -tracedDeltaY
            do $$$AssertEquals(tracedDeltaX + tracedDeltaY, 1, "Each AI animation step advances exactly one cardinal cell")
            set tracedPosition = tracedStep
        }
        set tracedDestination = tracedMovement.%Get("to")
        do $$$AssertEquals(tracedPosition.x, tracedDestination.x, "The horizontal trace ends at the persisted destination")
        do $$$AssertEquals(tracedPosition.y, tracedDestination.y, "The vertical trace ends at the persisted destination")
    }
    do $$$AssertEquals(aiLineRowsAfterMove, 1, "Heavy infantry and spearmen remain on one cohesive row")
    do $$$AssertEquals(aiLineCountAfterMove, aiLineMaxAfterMove - aiLineMinAfterMove + 1, "The AI movement does not open gaps in its main line")
    set resetUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(mobileUnitId)
    do $$$AssertEquals(resetUnit.HasMoved, 0, "The next round resets the moved indicator")
    do $$$AssertEquals(resetUnit.MovementSpent, 0, "The next round restores movement points")
    set responseHumanArmy = ""
    for responseArmyIndex = 0:1:(advancedTurn.data.battle.armies.%Size() - 1) {
        set responseArmy = advancedTurn.data.battle.armies.%Get(responseArmyIndex)
        if responseArmy.side = "HUMAN" set responseHumanArmy = responseArmy
    }
    do $$$AssertTrue($isobject(responseHumanArmy), "The next-turn response includes the human army")
    if $isobject(responseHumanArmy) {
        for responseUnitIndex = 0:1:(responseHumanArmy.units.%Size() - 1) {
            set responseUnit = responseHumanArmy.units.%Get(responseUnitIndex)
            continue:'responseUnit.active
            do $$$AssertEquals(responseUnit.hasMoved, 0, "Every active human unit is immediately available after the AI turn")
            do $$$AssertEquals(responseUnit.hasAttacked, 0, "Every active human unit recovers its attack in the response")
            do $$$AssertEquals(responseUnit.movementSpent, 0, "Every active human unit has no movement spent in the response")
            do $$$AssertEquals(responseUnit.remainingMovement, responseUnit.type.speed, "Every active human unit recovers its complete movement in the response")
        }
    }

    set aiArmy = ..FindArmy(battleId, "AI")
    do $$$AssertNotTrue(##class(BronzeWars.Rules.DeploymentValidator).HasDuplicatePositions(aiArmy), "The AI deployment has no duplicate positions")
    set aiArmyId = aiArmy.%Id()
    &sql(SELECT COUNT(*) INTO :aiUnitCount FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1)
    &sql(SELECT SUM(COALESCE(p.GrainCost, t.GrainCost)) INTO :aiGrain FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID LEFT JOIN BronzeWars_Model.UnitProfile p ON u.UnitProfile = p.%ID WHERE u.Army = :aiArmyId AND u.Active = 1)
    do $$$AssertTrue(aiUnitCount > 0, "The commander creates a non-empty AI army")
    do $$$AssertEquals(aiGrain, 100, "The AI commander spends the complete grain budget")

    &sql(SELECT COUNT(*) INTO :deploymentEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'UNIT_DEPLOYED')
    &sql(SELECT COUNT(*) INTO :armySelectionEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_ARMY_SELECTED')
    &sql(SELECT COUNT(*) INTO :commanderSelectionEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_COMMANDER_SELECTED')
    &sql(SELECT COUNT(*) INTO :startedEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'BATTLE_STARTED')
    &sql(SELECT COUNT(*) INTO :phaseEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'PHASE_CHANGED')
    &sql(SELECT COUNT(*) INTO :plannedEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_DEPLOYMENT_PLANNED')
    do $$$AssertEquals(deploymentEvents, human.units.%Size() + aiUnitCount, "Deployment events exist for all human and AI placements")
    do $$$AssertEquals(armySelectionEvents, 1, "The AI army selection is recorded once")
    do $$$AssertEquals(commanderSelectionEvents, 1, "The random AI commander selection is recorded once")
    do $$$AssertEquals(startedEvents, 1, "One BATTLE_STARTED event is recorded")
    do $$$AssertEquals(phaseEvents, 1, "One PHASE_CHANGED event is recorded")
    do $$$AssertEquals(plannedEvents, 1, "The AI deployment plan is recorded")
}

Method Test04ArmyCompositionBudget()
{
    set composition = [{"code":"SPEARMEN","quantity":4},{"code":"HEAVY_INFANTRY","quantity":4},{"code":"LIGHT_CAVALRY","quantity":2}]
    set result = ##class(BronzeWars.Interop.Client).CreateBattle({"name":"Custom army test","units":(composition)})
    do $$$AssertTrue(result.ok, "A repeated-unit composition is accepted")
    do $$$AssertEquals(result.data.battle.armies.%Get(0).units.%Size(), 10, "All selected human units are created")

    set overBudget = [{"code":"CHARIOTS","quantity":5}]
    set result = ##class(BronzeWars.Interop.Client).CreateBattle({"name":"Over budget test","units":(overBudget)})
    do $$$AssertEquals(result.code, "GRAIN_BUDGET_EXCEEDED", "A composition over 100 grain is rejected")
}

Method Test05AdjacentMeleeCombat()
{
    set battleJSON = ..CreateBattle("Adjacent melee combat test"), battleId = battleJSON.id
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    do $$$AssertStatusOK(sc, "Combat battle can be opened")
    set battle.Status = "IN_PROGRESS", battle.Phase = "MOVEMENT", battle.CurrentRound = 1
    set sc = battle.%Save()
    do $$$AssertStatusOK(sc, "Combat fixture battle can be started")

    set attacker = ##class(BronzeWars.Model.BattleUnit).%OpenId(battleJSON.armies.%Get(0).units.%Get(0).id, , .sc)
    do $$$AssertStatusOK(sc, "Attacker can be opened")
    set attacker.PositionX = 5, attacker.PositionY = 5, attacker.IsDeployed = 1, attacker.Morale = 80
    set sc = attacker.%Save()
    do $$$AssertStatusOK(sc, "Attacker can be prepared")

    set aiArmy = ..FindArmy(battleId, "AI")
    set defenderType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_INFANTRY")
    set defenderProfile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(defenderType.%Id(), aiArmy.Faction)
    set defender = ##class(BronzeWars.Model.BattleUnit).%New(defenderType, defenderProfile)
    set defender.Battle = battle, defender.Army = aiArmy, defender.Name = "Melee defender"
    set defender.PositionX = 5, defender.PositionY = 4, defender.IsDeployed = 1, defender.Morale = 100
    set sc = defender.%Save()
    do $$$AssertStatusOK(sc, "Defender can be prepared")

    set attackerStats = attacker.UnitType
    if $isobject(attacker.UnitProfile) set attackerStats = attacker.UnitProfile
    set defenderStats = defender.UnitType
    if $isobject(defender.UnitProfile) set defenderStats = defender.UnitProfile
    set expected = ##class(BronzeWars.Rules.Combat).Resolve({
        "attacker":{"code":(attacker.UnitType.Code),"side":(attacker.Army.Side),"x":(attacker.PositionX),"y":(attacker.PositionY),"strength":(attacker.CurrentStrength),"morale":(attacker.Morale),"attack":(attackerStats.Attack),"attackModifier":(##class(BronzeWars.Model.UnitModifier).GetAttackModifier(attacker.UnitType, defender.UnitType)),"defense":(attackerStats.Defense),"damage":(attackerStats.Damage)},
        "defender":{"code":(defender.UnitType.Code),"side":(defender.Army.Side),"x":(defender.PositionX),"y":(defender.PositionY),"strength":(defender.CurrentStrength),"morale":(defender.Morale),"attack":(defenderStats.Attack),"attackModifier":(##class(BronzeWars.Model.UnitModifier).GetAttackModifier(defender.UnitType, attacker.UnitType)),"defense":(defenderStats.Defense),"damage":(defenderStats.Damage)}
    })
    set attackerBefore = attacker.CurrentStrength, defenderBefore = defender.CurrentStrength
    set result = ##class(BronzeWars.Interop.Client).AttackUnit(battleId, attacker.%Id(), defender.%Id())
    do $$$AssertTrue(result.ok, "Adjacent units can resolve melee combat through the production")
    do $$$AssertEquals(result.data.combat.attackerCasualties, expected.attackerCasualties, "The attacker receives the calculated casualties")
    do $$$AssertEquals(result.data.combat.defenderCasualties, expected.defenderCasualties, "The defender receives the calculated casualties")
    set responseDefenderMorale = ""
    for armyIndex = 0:1:(result.data.battle.armies.%Size() - 1) {
        set responseArmy = result.data.battle.armies.%Get(armyIndex)
        for responseUnitIndex = 0:1:(responseArmy.units.%Size() - 1) {
            set responseUnit = responseArmy.units.%Get(responseUnitIndex)
            if responseUnit.id = defender.%Id() set responseDefenderMorale = responseUnit.morale
        }
    }
    do $$$AssertEquals(responseDefenderMorale, 100 - expected.defenderCasualties, "The combat response immediately exposes updated defender morale")
    set storedAttacker = ##class(BronzeWars.Model.BattleUnit).%OpenId(attacker.%Id())
    set storedDefender = ##class(BronzeWars.Model.BattleUnit).%OpenId(defender.%Id())
    do storedAttacker.%Reload()
    do storedDefender.%Reload()
    do $$$AssertEquals(storedAttacker.CurrentStrength, attackerBefore - expected.attackerCasualties, "Attacker casualties are persisted")
    do $$$AssertEquals(storedDefender.CurrentStrength, defenderBefore - expected.defenderCasualties, "Defender casualties are persisted")
    do $$$AssertEquals(storedAttacker.Morale, 80 - expected.attackerCasualties, "Attacker morale falls by its casualties")
    do $$$AssertEquals(storedDefender.Morale, 100 - expected.defenderCasualties, "Defender morale falls by its casualties")
    do $$$AssertTrue(storedAttacker.HasAttacked, "The attacker is marked as having attacked")
    &sql(SELECT COUNT(*) INTO :combatEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'ATTACK_RESOLVED')
    do $$$AssertEquals(combatEvents, 1, "The resolved combat is recorded once")

    set repeated = ##class(BronzeWars.Interop.Client).AttackUnit(battleId, attacker.%Id(), defender.%Id())
    do $$$AssertEquals(repeated.code, "UNIT_ALREADY_ATTACKED", "A unit cannot attack twice in the same turn")

    set rangedUnitId = ""
    for unitIndex = 0:1:(battleJSON.armies.%Get(0).units.%Size() - 1) {
        set candidate = battleJSON.armies.%Get(0).units.%Get(unitIndex)
        if (candidate.type.code = "LIGHT_CAVALRY") && (rangedUnitId = "") set rangedUnitId = candidate.id
    }
    set rangedAttacker = ##class(BronzeWars.Model.BattleUnit).%OpenId(rangedUnitId)
    set rangedAttacker.PositionX = 5, rangedAttacker.PositionY = 6, rangedAttacker.IsDeployed = 1
    set sc = rangedAttacker.%Save()
    do $$$AssertStatusOK(sc, "Ranged attacker can be prepared")
    set defenderBefore = storedDefender.CurrentStrength, projectilesBefore = rangedAttacker.CurrentProjectiles
    set rangedResult = ##class(BronzeWars.Interop.Client).AttackUnit(battleId, rangedAttacker.%Id(), defender.%Id())
    do $$$AssertTrue(rangedResult.ok, "A projectile unit can attack a non-adjacent enemy")
    do $$$AssertEquals(rangedResult.data.combat.type, "RANGED", "The engagement is identified as ranged combat")
    do $$$AssertEquals(rangedResult.data.combat.attackerCasualties, 0, "The ranged attacker receives no retaliation")
    do $$$AssertTrue(rangedResult.data.combat.defenderCasualties > 0, "The ranged defender receives calculated casualties")
    do $$$AssertEquals(rangedResult.data.combat.projectilesAfter, projectilesBefore - 1, "A ranged attack consumes one projectile")
    do rangedAttacker.%Reload()
    do storedDefender.%Reload()
    do $$$AssertEquals(rangedAttacker.CurrentProjectiles, projectilesBefore - 1, "Remaining projectiles are persisted")
    do $$$AssertEquals(storedDefender.CurrentStrength, defenderBefore - rangedResult.data.combat.defenderCasualties, "Ranged casualties are persisted")
    do $$$AssertEquals(storedDefender.Morale, 100 - expected.defenderCasualties - rangedResult.data.combat.defenderCasualties, "Ranged casualties also reduce morale")

    set attacker.HasAttacked = 0, attacker.PositionX = 4, attacker.PositionY = 4
    set sc = attacker.%Save()
    do $$$AssertStatusOK(sc, "The attacker can be prepared for a repeated flank attack")
    set defenderMoraleBeforeFlank = storedDefender.Morale
    set flankResult = ##class(BronzeWars.Interop.Client).AttackUnit(battleId, attacker.%Id(), defender.%Id())
    do $$$AssertTrue(flankResult.ok, "A flank attack can be resolved through the production")
    do $$$AssertEquals(flankResult.data.combat.attackDirection, "FLANK", "The combat response identifies the flank attack")
    do $$$AssertEquals(flankResult.data.combat.defenderPositionMoralePenalty, 10, "The combat response exposes the ten-point flank penalty")
    do storedDefender.%Reload()
    set expectedFlankMorale = defenderMoraleBeforeFlank - ##class(BronzeWars.Rules.Morale).LossForCasualties(storedDefender, flankResult.data.combat.defenderCasualties) - 10
    if expectedFlankMorale < 0 set expectedFlankMorale = 0
    do $$$AssertEquals(storedDefender.Morale, expectedFlankMorale, "Every flank attack removes ten additional morale points")
}

Method Test06LowMoraleUnitRetreatsAroundObstacles()
{
    set battleJSON = ..CreateBattle("Low morale retreat test"), battleId = battleJSON.id
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    do $$$AssertStatusOK(sc, "Retreat battle can be opened")
    set battle.Status = "IN_PROGRESS", battle.Phase = "MOVEMENT", battle.CurrentRound = 1
    set sc = battle.%Save()
    do $$$AssertStatusOK(sc, "Retreat fixture battle can be started")

    set attacker = ##class(BronzeWars.Model.BattleUnit).%OpenId(battleJSON.armies.%Get(0).units.%Get(0).id, , .sc)
    do $$$AssertStatusOK(sc, "Retreat attacker can be opened")
    set attacker.PositionX = 5, attacker.PositionY = 5, attacker.IsDeployed = 1, attacker.Morale = 100
    set sc = attacker.%Save()
    do $$$AssertStatusOK(sc, "Retreat attacker can be prepared")

    set aiArmy = ..FindArmy(battleId, "AI")
    set defenderType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_INFANTRY")
    set defenderProfile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(defenderType.%Id(), aiArmy.Faction)
    set defender = ##class(BronzeWars.Model.BattleUnit).%New(defenderType, defenderProfile)
    set defender.Battle = battle, defender.Army = aiArmy, defender.Name = "Retreating defender"
    set defender.PositionX = 5, defender.PositionY = 4, defender.IsDeployed = 1, defender.Morale = 20
    set sc = defender.%Save()
    do $$$AssertStatusOK(sc, "Retreating defender can be prepared")

    set blocker = ##class(BronzeWars.Model.BattleUnit).%New(defenderType, defenderProfile)
    set blocker.Battle = battle, blocker.Army = aiArmy, blocker.Name = "Retreat blocker"
    set blocker.PositionX = 5, blocker.PositionY = 3, blocker.IsDeployed = 1
    set sc = blocker.%Save()
    do $$$AssertStatusOK(sc, "The direct retreat path can be blocked")

    set result = ##class(BronzeWars.Interop.Client).AttackUnit(battleId, attacker.%Id(), defender.%Id())
    do $$$AssertTrue(result.ok, "Combat that breaks morale is resolved")
    do $$$AssertTrue(result.data.combat.defenderCasualties > 0, "The defender suffers casualties")
    do $$$AssertEquals(result.data.combat.defenderMoraleAfter, 20 - result.data.combat.defenderCasualties, "Morale falls by exactly the casualties suffered")
    do $$$AssertTrue(result.data.combat.defenderRetreat.attempted, "A surviving unit below 20 morale attempts to retreat")
    do $$$AssertTrue(result.data.combat.defenderRetreat.moved, "The unit finds an unblocked retreat route")
    do $$$AssertEquals(result.data.combat.defenderRetreat.path.%Size(), defenderProfile.Speed, "The retreat is limited by unit speed")

    do defender.%Reload()
    do $$$AssertEquals(defender.PositionX, 4, "The retreat avoids the occupied cell")
    do $$$AssertEquals(defender.PositionY, 4, "The first detour remains on the same row")
    do $$$AssertTrue(defender.HasMoved, "A retreat consumes the movement action")
    do $$$AssertEquals(defender.MovementSpent, defenderProfile.Speed, "A retreat exhausts the unit's movement")
    &sql(SELECT COUNT(*) INTO :retreatEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'UNIT_RETREATED')
    do $$$AssertEquals(retreatEvents, 1, "The successful retreat is recorded")
}

Method Test07AIProjectileCombatPhase()
{
    set battleJSON = ..CreateBattle("AI projectile combat phase test"), battleId = battleJSON.id
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    do $$$AssertStatusOK(sc, "AI combat battle can be opened")
    set battle.Status = "IN_PROGRESS", battle.Phase = "MOVEMENT", battle.CurrentRound = 1
    set sc = battle.%Save()
    do $$$AssertStatusOK(sc, "AI combat fixture can be started")

    set nearTarget = ##class(BronzeWars.Model.BattleUnit).%OpenId(battleJSON.armies.%Get(0).units.%Get(0).id)
    set nearTarget.PositionX = 5, nearTarget.PositionY = 5, nearTarget.IsDeployed = 1, nearTarget.HasMoved = 1
    set sc = nearTarget.%Save()
    do $$$AssertStatusOK(sc, "The nearest human target can be prepared")
    set farTarget = ##class(BronzeWars.Model.BattleUnit).%OpenId(battleJSON.armies.%Get(0).units.%Get(1).id)
    set farTarget.PositionX = 8, farTarget.PositionY = 5, farTarget.IsDeployed = 1, farTarget.HasMoved = 1
    set sc = farTarget.%Save()
    do $$$AssertStatusOK(sc, "A farther human target can be prepared")

    set aiArmy = ..FindArmy(battleId, "AI")
    set attackerType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_CAVALRY")
    set attackerProfile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(attackerType.%Id(), aiArmy.Faction)
    set attacker = ##class(BronzeWars.Model.BattleUnit).%New(attackerType, attackerProfile)
    set attacker.Battle = battle, attacker.Army = aiArmy, attacker.Name = "AI mounted archer"
    set attacker.PositionX = 5, attacker.PositionY = 1, attacker.IsDeployed = 1
    set sc = attacker.%Save()
    do $$$AssertStatusOK(sc, "The AI projectile unit can be prepared")
    set projectilesBefore = attacker.CurrentProjectiles, targetStrengthBefore = nearTarget.CurrentStrength

    set result = ##class(BronzeWars.Interop.Client).NextTurn(battleId, 1)
    do $$$AssertTrue(result.ok, "The AI movement and combat phases complete")
    do $$$AssertEquals(result.data.aiCombatTrace.%Size(), 1, "Every eligible projectile unit attacks once")
    set combat = result.data.aiCombatTrace.%Get(0)
    do $$$AssertEquals(combat.attackerUnitId, attacker.%Id(), "The combat trace identifies the AI attacker")
    do $$$AssertEquals(combat.defenderUnitId, nearTarget.%Id(), "The closest target in range is prioritized")
    do $$$AssertTrue(combat.defenderCasualties > 0, "The AI ranged attack causes casualties")
    do $$$AssertEquals(result.data.aiMovementTrace.%Size(), 2, "The trace contains approach and post-attack retreat")
    do $$$AssertEquals(result.data.aiMovementTrace.%Get(0).phase, "APPROACH", "The unit first approaches projectile range")
    do $$$AssertEquals(result.data.aiMovementTrace.%Get(1).phase, "POST_ATTACK_RETREAT", "Remaining movement is used to retreat")

    do attacker.%Reload()
    do nearTarget.%Reload()
    do farTarget.%Reload()
    do $$$AssertEquals(attacker.CurrentProjectiles, projectilesBefore - 1, "The AI attack consumes one projectile")
    do $$$AssertTrue(attacker.PositionY < combat.attackFrom.y, "The projectile unit withdraws away from its target")
    do $$$AssertEquals(nearTarget.CurrentStrength, targetStrengthBefore - combat.defenderCasualties, "AI casualties are persisted on the closest target")
    do $$$AssertEquals(nearTarget.Morale, 100 - combat.defenderCasualties, "AI ranged casualties reduce target morale")
    set responseTargetMorale = ""
    for armyIndex = 0:1:(result.data.battle.armies.%Size() - 1) {
        set responseArmy = result.data.battle.armies.%Get(armyIndex)
        for responseUnitIndex = 0:1:(responseArmy.units.%Size() - 1) {
            set responseUnit = responseArmy.units.%Get(responseUnitIndex)
            if responseUnit.id = nearTarget.%Id() set responseTargetMorale = responseUnit.morale
        }
    }
    do $$$AssertEquals(responseTargetMorale, nearTarget.Morale, "The next-turn response includes updated morale without requiring a reload")
    do $$$AssertEquals(farTarget.CurrentStrength, farTarget.UnitProfile.InitialStrength, "The farther target is not attacked")
    &sql(SELECT COUNT(*) INTO :aiCombatEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_COMBAT_PHASE')
    do $$$AssertEquals(aiCombatEvents, 1, "The AI combat phase is recorded")
}

Method Test08AIAdjacentMeleeCombat()
{
    set battleJSON = ..CreateBattle("AI adjacent melee combat test"), battleId = battleJSON.id
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    do $$$AssertStatusOK(sc, "AI melee battle can be opened")
    set battle.Status = "IN_PROGRESS", battle.Phase = "MOVEMENT", battle.CurrentRound = 1
    set sc = battle.%Save()
    do $$$AssertStatusOK(sc, "AI melee fixture can be started")

    set defender = ##class(BronzeWars.Model.BattleUnit).%OpenId(battleJSON.armies.%Get(0).units.%Get(0).id)
    set defender.PositionX = 5, defender.PositionY = 5, defender.IsDeployed = 1, defender.HasMoved = 1, defender.Morale = 80
    set sc = defender.%Save()
    do $$$AssertStatusOK(sc, "The adjacent human defender can be prepared")

    set aiArmy = ..FindArmy(battleId, "AI")
    set attackerType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_INFANTRY")
    set attackerProfile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(attackerType.%Id(), aiArmy.Faction)
    set attacker = ##class(BronzeWars.Model.BattleUnit).%New(attackerType, attackerProfile)
    set attacker.Battle = battle, attacker.Army = aiArmy, attacker.Name = "AI melee attacker"
    set attacker.PositionX = 5, attacker.PositionY = 4, attacker.IsDeployed = 1, attacker.Morale = 80
    set sc = attacker.%Save()
    do $$$AssertStatusOK(sc, "The adjacent AI attacker can be prepared")
    set attackerStrengthBefore = attacker.CurrentStrength, defenderStrengthBefore = defender.CurrentStrength

    set result = ##class(BronzeWars.Interop.Client).NextTurn(battleId, 1)
    do $$$AssertTrue(result.ok, "An adjacent AI unit executes its combat phase")
    do $$$AssertEquals(result.data.aiCombatTrace.%Size(), 1, "The stationary adjacent attacker produces a combat trace")
    set combat = result.data.aiCombatTrace.%Get(0)
    do $$$AssertEquals(combat.type, "MELEE", "An adjacent AI attack is resolved as melee")
    do $$$AssertTrue(combat.attackerCasualties > 0, "The AI attacker receives defender retaliation casualties")
    do $$$AssertTrue(combat.defenderCasualties > 0, "The human defender receives attacker casualties")

    do attacker.%Reload()
    do defender.%Reload()
    do $$$AssertEquals(attacker.CurrentStrength, attackerStrengthBefore - combat.attackerCasualties, "AI attacker casualties are persisted")
    do $$$AssertEquals(defender.CurrentStrength, defenderStrengthBefore - combat.defenderCasualties, "Human defender casualties are persisted")
    do $$$AssertEquals(attacker.Morale, 80 - combat.attackerCasualties, "AI attacker casualties reduce its morale")
    do $$$AssertEquals(defender.Morale, 80 - combat.defenderCasualties, "Human defender casualties reduce its morale")
}

Method CreateBattle(name As %String) As %DynamicObject
{
    set result = ##class(BronzeWars.Interop.Client).CreateBattle({"name":(name)})
    do $$$AssertTrue(result.ok, name _ " is created")
    return result.data.battle
}

Method FindArmy(battleId As %String, side As %String) As BronzeWars.Model.Army
{
    &sql(SELECT TOP 1 %ID INTO :armyId FROM BronzeWars_Model.Army WHERE Battle = :battleId AND Side = :side)
    if SQLCODE '= 0 return ""
    return ##class(BronzeWars.Model.Army).%OpenId(armyId)
}

}
