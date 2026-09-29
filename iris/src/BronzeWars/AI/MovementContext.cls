Class BronzeWars.AI.MovementContext Extends %RegisteredObject
{

ClassMethod Build(battleId As %String, Output context As %DynamicObject) As %Status
{
    set context = "", sc = $$$OK
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) return sc
    if '$isobject(battle) return $$$ERROR($$$GeneralError, "Battle not found")

    &sql(SELECT TOP 1 %ID INTO :humanArmyId FROM BronzeWars_Model.Army WHERE Battle = :battleId AND Side = 'HUMAN')
    if SQLCODE '= 0 return $$$ERROR($$$GeneralError, "Human army not found")
    &sql(SELECT TOP 1 %ID INTO :aiArmyId FROM BronzeWars_Model.Army WHERE Battle = :battleId AND Side = 'AI')
    if SQLCODE '= 0 return $$$ERROR($$$GeneralError, "AI army not found")
    set aiArmy = ##class(BronzeWars.Model.Army).%OpenId(aiArmyId)
    set commanderType = aiArmy.CommanderType
    if commanderType = "" set commanderType = ##class(BronzeWars.AI.Commanders.Strategy).#BALANCED
    &sql(SELECT MIN(PositionX), MAX(PositionX) INTO :humanMinX, :humanMaxX FROM BronzeWars_Model.BattleUnit WHERE Army = :humanArmyId AND Active = 1 AND IsDeployed = 1)

    set situation = ##class(BronzeWars.AI.Tools.BattleSituation).GetBattleSituation(battleId)
    if situation.%IsDefined("error") return $$$ERROR($$$GeneralError, situation.error)
    set context = {"battleId":(battleId),"round":(battle.CurrentRound),"commanderType":(commanderType),"commanderName":(##class(BronzeWars.AI.Commanders.Strategy).Label(commanderType)),"commanderDoctrine":(##class(BronzeWars.AI.Commanders.Strategy).Doctrine(commanderType)),"battleSituation":(situation),"board":{"width":(battle.BoardWidth),"height":(battle.BoardHeight)},"humanFormation":{"minX":(humanMinX),"maxX":(humanMaxX)},"humanUnits":(##class(%DynamicArray).%New()),"aiUnits":(##class(%DynamicArray).%New())}
    for side = "HUMAN","AI" {
        set armyId = $select(side="HUMAN":humanArmyId, 1:aiArmyId)
        &sql(DECLARE MovementContextCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :armyId AND Active = 1 AND IsDeployed = 1 ORDER BY %ID)
        &sql(OPEN MovementContextCursor)
        for {
            &sql(FETCH MovementContextCursor INTO :unitId)
            quit:(SQLCODE'=0)
            set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId), speed = unit.UnitType.Speed, attackRange = unit.UnitType.AttackRange
            if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed, attackRange = unit.UnitProfile.AttackRange
            set remaining = speed - $select(unit.MovementSpent="":0, 1:unit.MovementSpent)
            if remaining < 0 set remaining = 0
            set value = {"unitId":(unitId),"code":(unit.UnitType.Code),"x":(unit.PositionX),"y":(unit.PositionY),"remainingMovement":(remaining),"attackRange":(attackRange),"projectiles":(unit.CurrentProjectiles),"morale":(unit.Morale)}
            if side = "HUMAN" do context.humanUnits.%Push(value)
            if side = "AI" do context.aiUnits.%Push(value)
        }
        &sql(CLOSE MovementContextCursor)
    }
    return sc
}

}
