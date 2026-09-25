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
    &sql(SELECT u.Morale INTO :leftMorale FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :humanArmyId AND u.PositionX = 0 AND t.Code IN ('SPEARMEN','HEAVY_INFANTRY','LIGHT_INFANTRY','MERCENARIES'))
    &sql(SELECT u.Morale INTO :interiorMorale FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :humanArmyId AND u.PositionX = 1 AND t.Code IN ('SPEARMEN','HEAVY_INFANTRY','LIGHT_INFANTRY','MERCENARIES'))
    &sql(SELECT TOP 1 u.Morale INTO :cavalryMorale FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :humanArmyId AND t.Code IN ('LIGHT_CAVALRY','HEAVY_CAVALRY'))
    do $$$AssertEquals(leftMorale, 80, "Infantry at the end of a continuous human line starts with 80 morale")
    do $$$AssertEquals(interiorMorale, 90, "Infantry supported on both sides starts with 90 morale")
    do $$$AssertEquals(cavalryMorale, 100, "Cavalry keeps its initial morale")

    set aiArmy = ..FindArmy(battleId, "AI"), aiArmyId = aiArmy.%Id()
    do $$$AssertTrue(##class(BronzeWars.AI.Commanders.Strategy).IsValid(aiArmy.CommanderType), "Battle start selects and persists a valid random AI commander")
    do $$$AssertEquals(started.data.battle.armies.%Get(1).commanderType, aiArmy.CommanderType, "The API exposes the selected AI commander")
    do $$$AssertTrue(##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(aiArmy), "The AI is completely and legally deployed")
    &sql(SELECT COUNT(*), MIN(u.PositionX), MAX(u.PositionX) INTO :aiLineCount, :aiLineMin, :aiLineMax FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.PositionY = 1 AND t.Code IN ('SPEARMEN','HEAVY_INFANTRY','MERCENARIES'))
    &sql(SELECT MIN(PositionX), MAX(PositionX) INTO :aiFormationMin, :aiFormationMax FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1 AND IsDeployed = 1)
    &sql(SELECT COUNT(*) INTO :mobileFlankUnits FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.PositionX IN (:aiFormationMin, :aiFormationMax) AND t.Code IN ('LIGHT_INFANTRY','LIGHT_CAVALRY','HEAVY_CAVALRY','CHARIOTS'))
    &sql(SELECT COUNT(*) INTO :aiLineMoraleErrors FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.PositionY = 1 AND t.Code IN ('SPEARMEN','HEAVY_INFANTRY','MERCENARIES') AND u.Morale NOT IN (80,90))
    set expectedLine = ##class(BronzeWars.AI.Commanders.Strategy).MainLineTarget(aiArmy.CommanderType, 10, 16)
    do $$$AssertTrue(aiLineCount >= expectedLine, "The AI infantry line follows its commander doctrine")
    if aiArmy.CommanderType = "FLANKER" {
        do $$$AssertTrue((aiFormationMax - aiFormationMin + 1) > 10, "A flanking commander exceeds the human frontage")
        do $$$AssertEquals(mobileFlankUnits, 2, "A flanking commander places a mobile unit on both extremes")
    }
    do $$$AssertEquals(aiLineCount, aiLineMax - aiLineMin + 1, "The AI infantry line has no gaps")
    do $$$AssertEquals(aiLineMoraleErrors, 0, "Every unit in the AI main line receives lateral-support morale")

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
    set advancedTurn = ##class(BronzeWars.Interop.Client).NextTurn(battleId, 1)
    do $$$AssertTrue(advancedTurn.ok, "The turn can be advanced after confirmation")
    do $$$AssertEquals(advancedTurn.data.battle.currentRound, 2, "Advancing starts the next round")
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

    set aiArmy = ..FindArmy(battleId, "AI")
    do $$$AssertNotTrue(##class(BronzeWars.Rules.DeploymentValidator).HasDuplicatePositions(aiArmy), "The AI deployment has no duplicate positions")
    set aiArmyId = aiArmy.%Id()
    &sql(SELECT COUNT(*) INTO :aiUnitCount FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1)
    &sql(SELECT SUM(t.GrainCost) INTO :aiGrain FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.Active = 1)
    do $$$AssertTrue(aiUnitCount > 0, "The commander creates a non-empty AI army")
    do $$$AssertEquals(aiGrain, 100, "The AI commander spends the complete grain budget")

    &sql(SELECT COUNT(*) INTO :deploymentEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'UNIT_DEPLOYED')
    &sql(SELECT COUNT(*) INTO :armySelectionEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_ARMY_SELECTED')
    &sql(SELECT COUNT(*) INTO :commanderSelectionEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_COMMANDER_SELECTED')
    &sql(SELECT COUNT(*) INTO :startedEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'BATTLE_STARTED')
    &sql(SELECT COUNT(*) INTO :phaseEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'PHASE_CHANGED')
    &sql(SELECT COUNT(*) INTO :plannedEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_DEPLOYMENT_PLANNED')
    &sql(SELECT COUNT(*) INTO :moraleEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'FORMATION_MORALE_CALCULATED')
    do $$$AssertEquals(deploymentEvents, human.units.%Size() + aiUnitCount, "Deployment events exist for all human and AI placements")
    do $$$AssertEquals(armySelectionEvents, 1, "The AI army selection is recorded once")
    do $$$AssertEquals(commanderSelectionEvents, 1, "The random AI commander selection is recorded once")
    do $$$AssertEquals(startedEvents, 1, "One BATTLE_STARTED event is recorded")
    do $$$AssertEquals(phaseEvents, 1, "One PHASE_CHANGED event is recorded")
    do $$$AssertEquals(plannedEvents, 1, "The AI deployment plan is recorded")
    do $$$AssertEquals(moraleEvents, 1, "Formation morale is calculated once after deployment")
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
