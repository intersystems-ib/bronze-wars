Class BronzeWars.Rules.FormationMorale Extends %RegisteredObject
{

ClassMethod Apply(battle As BronzeWars.Model.Battle, Output changedUnits As %Integer) As %Status
{
    set changedUnits = 0, battleId = battle.%Id(), sc = $$$OK
    &sql(DECLARE FormationUnitCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Battle = :battleId AND Active = 1 AND IsDeployed = 1)
    &sql(OPEN FormationUnitCursor)
    for {
        &sql(FETCH FormationUnitCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, 4, .sc)
        quit:$SYSTEM.Status.IsError(sc)
        continue:'..IsSupportedUnitCode(unit.UnitType.Code)
        set armyId = unit.Army.%Id(), row = unit.PositionY, leftX = unit.PositionX - 1, rightX = unit.PositionX + 1
        &sql(SELECT COUNT(*) INTO :leftCount FROM BronzeWars_Model.BattleUnit WHERE Army = :armyId AND Active = 1 AND IsDeployed = 1 AND PositionX = :leftX AND PositionY = :row)
        &sql(SELECT COUNT(*) INTO :rightCount FROM BronzeWars_Model.BattleUnit WHERE Army = :armyId AND Active = 1 AND IsDeployed = 1 AND PositionX = :rightX AND PositionY = :row)
        set morale = ..MoraleForNeighbors((leftCount > 0) + (rightCount > 0))
        if unit.Morale '= morale {
            set unit.Morale = morale
            set sc = unit.%Save()
            quit:$SYSTEM.Status.IsError(sc)
            set changedUnits = changedUnits + 1
        }
    }
    &sql(CLOSE FormationUnitCursor)
    return sc
}

ClassMethod MoraleForNeighbors(neighborCount As %Integer) As %Integer
{
    if neighborCount < 0 set neighborCount = 0
    if neighborCount > 2 set neighborCount = 2
    return 70 + (neighborCount * 10)
}

ClassMethod IsSupportedUnitCode(code As %String) As %Boolean
{
    return (code = "LIGHT_INFANTRY") ! (code = "HEAVY_INFANTRY") ! (code = "MERCENARIES") ! (code = "SPEARMEN")
}

}
