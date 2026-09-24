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
    set firstUnit = battle.armies.%Get(0).units.%Get(0)
    do $$$AssertTrue(firstUnit.currentStrength > 0, "Unit strength is copied from its type")
    do $$$AssertEquals(firstUnit.isDeployed, 0, "Units begin undeployed")
    do $$$AssertEquals(firstUnit.hasMoved, 0, "Units begin without movement")
    do $$$AssertEquals(firstUnit.active, 1, "Units begin active")
}

Method Test02PlacementRules()
{
    set battle1 = ..CreateBattle("Placement rules one")
    set battle2 = ..CreateBattle("Placement rules two")
    set human1 = battle1.armies.%Get(0)
    set ai1 = battle1.armies.%Get(1)
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
    set result = ##class(BronzeWars.Interop.Client).PlaceUnit(battle1.id, ai1.units.%Get(0).id, 0, 9)
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

    set aiArmy = ..FindArmy(battleId, "AI")
    do $$$AssertTrue(##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(aiArmy), "The AI is completely and legally deployed")
    do $$$AssertNotTrue(##class(BronzeWars.Rules.DeploymentValidator).HasDuplicatePositions(aiArmy), "The AI deployment has no duplicate positions")
    set aiArmyId = aiArmy.%Id()
    &sql(SELECT COUNT(*) INTO :aiUnitCount FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1)
    &sql(SELECT SUM(t.GrainCost) INTO :aiGrain FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID WHERE u.Army = :aiArmyId AND u.Active = 1)
    do $$$AssertTrue(aiUnitCount > 0, "The commander creates a non-empty AI army")
    do $$$AssertEquals(aiGrain, 100, "The AI commander spends the complete grain budget")

    &sql(SELECT COUNT(*) INTO :deploymentEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'UNIT_DEPLOYED')
    &sql(SELECT COUNT(*) INTO :armySelectionEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_ARMY_SELECTED')
    &sql(SELECT COUNT(*) INTO :startedEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'BATTLE_STARTED')
    &sql(SELECT COUNT(*) INTO :phaseEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'PHASE_CHANGED')
    &sql(SELECT COUNT(*) INTO :plannedEvents FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_DEPLOYMENT_PLANNED')
    do $$$AssertEquals(deploymentEvents, human.units.%Size() + aiUnitCount, "Deployment events exist for all human and AI placements")
    do $$$AssertEquals(armySelectionEvents, 1, "The AI army selection is recorded once")
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
