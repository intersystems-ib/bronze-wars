Class BronzeWars.Tests.BattleWithdrawalTest Extends %UnitTest.TestCase
{
Method TestWithdrawnMetrics()
{
    set units=[{"soldiers":30,"initialStrength":60,"morale":17,"active":false},{"soldiers":60,"initialStrength":60,"morale":80,"active":true},{"soldiers":0,"initialStrength":60,"morale":0,"active":true}]
    set metrics=##class(BronzeWars.Rules.Surrender).Metrics(units)
    do $$$AssertEquals(metrics.survivingSoldiers,60,"Withdrawn survivors are not remaining combatants")
    do $$$AssertEquals(metrics.withdrawnSoldiers,30,"Withdrawn survivors are retained as fled troops")
    do $$$AssertEquals(metrics.initialSoldiers,180,"Original force still includes losses and withdrawals")
    do $$$AssertEquals(metrics.armyMorale,80,"Withdrawn morale does not dilute the remaining army")
    set units=[{"soldiers":30,"initialStrength":30,"morale":17,"active":false}]
    set metrics=##class(BronzeWars.Rules.Surrender).Metrics(units)
    do $$$AssertEquals(metrics.survivingSoldiers,0,"An entirely withdrawn army has no combatants")
    do $$$AssertEquals(metrics.moralePercentage,0,"An entirely withdrawn army has no remaining battle morale")
}

Method Fixture() As %DynamicObject
{
    set input={"gameId":($system.Util.CreateGUID()),"playerNation":"egypt","encounter":{"id":"withdrawal-test","attackerId":1,"defenderId":2},"attacker":{"id":1,"designId":"egypt","name":"Withdrawal test human","morale":100,"units":[{"code":"LIGHT_INFANTRY","quantity":1,"strengths":[60]}]},"defender":{"id":2,"designId":"hatti","name":"Withdrawal test AI","morale":17,"units":[{"code":"LIGHT_INFANTRY","quantity":1,"strengths":[20]}]},"terrain":"PLAINS"}
    set created=##class(BronzeWars.Service.CampaignBattle).Create(input)
    do $$$AssertTrue(created.ok,"Campaign withdrawal fixture is created")
    set value=created.data.battle, battle=##class(BronzeWars.Model.Battle).%OpenId(value.id)
    set battle.Status="IN_PROGRESS", battle.Phase="MOVEMENT", battle.CurrentRound=1
    do $$$AssertStatusOK(battle.%Save(),"Fixture is in progress")
    set human=##class(BronzeWars.Model.BattleUnit).%OpenId(value.armies.%Get(0).units.%Get(0).id)
    set human.IsDeployed=1, human.PositionX=5, human.PositionY=9, human.HasMoved=1
    do $$$AssertStatusOK(human.%Save(),"Human combatant is deployed")
    set ai=##class(BronzeWars.Model.BattleUnit).%OpenId(value.armies.%Get(1).units.%Get(0).id)
    set ai.PositionX=8, ai.PositionY=1
    do $$$AssertStatusOK(ai.%Save(),"AI combatant is near its withdrawal edge")
    return {"battleId":(value.id),"humanId":(human.%Id()),"aiId":(ai.%Id())}
}

Method TestLastAIWithdrawalFinishesTurn()
{
    set fixture=..Fixture()
    set result=##class(BronzeWars.Interop.Client).NextTurn(fixture.battleId,1)
    do $$$AssertTrue(result.ok,"Withdrawal turn succeeds")
    quit:'result.ok
    set battle=result.data.battle
    do $$$AssertEquals(battle.status,"FINISHED","The last retreating enemy ends the battle in the same turn")
    do $$$AssertEquals(battle.finishReason,"WITHDRAWAL","Fleeing survivors are distinguished from annihilation")
    do $$$AssertTrue(battle.outcome.armies.%Get(0).winner,"The human army wins")
    do $$$AssertEquals(battle.outcome.armies.%Get(1).fled,20,"Withdrawn troops are counted as fled")
    do $$$AssertEquals(battle.outcome.armies.%Get(1).casualties,0,"Withdrawal does not create extra deaths")
    set reloaded=##class(BronzeWars.Interop.Client).GetBattle(fixture.battleId)
    do $$$AssertEquals(reloaded.data.battle.status,"FINISHED","The victory survives a fresh API read")
    set battleId=fixture.battleId
    &sql(SELECT COUNT(*) INTO :events FROM BronzeWars_Model.BattleEvent WHERE Battle=:battleId AND EventType='BATTLE_FINISHED')
    do $$$AssertEquals(events,1,"Reload does not finalize the same battle twice")
}

Method TestRecoverAlreadyEmptyBattle()
{
    for mode="WITHDRAWAL","ANNIHILATION","HUMAN_WITHDRAWAL" {
        set fixture=..Fixture(), id=$select(mode="HUMAN_WITHDRAWAL":fixture.humanId,1:fixture.aiId)
        set unit=##class(BronzeWars.Model.BattleUnit).%OpenId(id)
        set unit.Active=0, unit.IsDeployed=0
        if mode="ANNIHILATION" set unit.CurrentStrength=0
        do $$$AssertStatusOK(unit.%Save(),"Already-empty fixture is saved")
        set result=##class(BronzeWars.Interop.Client).GetBattle(fixture.battleId)
        do $$$AssertTrue(result.ok,"Reading an already-empty battle succeeds")
        do $$$AssertEquals(result.data.battle.status,"FINISHED","Reading repairs an old battle with no opposing combatants")
        do $$$AssertEquals(result.data.battle.finishReason,$select(mode="ANNIHILATION":"ANNIHILATION",1:"WITHDRAWAL"),"The repair records the actual cause")
        do $$$AssertTrue(result.data.battle.outcome.armies.%Get($select(mode="HUMAN_WITHDRAWAL":1,1:0)).winner,"The side remaining on the battlefield wins")
    }
}

Method TestPartialWithdrawalDoesNotEndBattle()
{
    set fixture=..Fixture(), ai=##class(BronzeWars.Model.BattleUnit).%OpenId(fixture.aiId)
    set ai.Morale=100
    do $$$AssertStatusOK(ai.%Save(),"The remaining AI formation is healthy")
    set fled=##class(BronzeWars.Model.BattleUnit).%New(ai.UnitType,ai.UnitProfile)
    set fled.Battle=ai.Battle, fled.Army=ai.Army, fled.CurrentStrength=20, fled.CampaignInitialStrength=20, fled.Active=0, fled.IsDeployed=0, fled.Morale=17
    do $$$AssertStatusOK(fled.%Save(),"A second formation has already fled")
    set result=##class(BronzeWars.Interop.Client).GetBattle(fixture.battleId)
    do $$$AssertEquals(result.data.battle.status,"IN_PROGRESS","One withdrawal does not defeat an army with remaining combatants")
    set metrics=##class(BronzeWars.Rules.Surrender).ArmyMetrics(ai.Army)
    do $$$AssertEquals(metrics.survivingSoldiers,20,"Only the remaining formation fights")
}
}
