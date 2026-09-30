Class BronzeWars.Rules.Surrender Extends %RegisteredObject
{

Parameter REASONCRITICALMORALE = "CRITICAL_MORALE";
Parameter REASONSUSTAINEDDISADVANTAGE = "SUSTAINED_DISADVANTAGE";

ClassMethod Metrics(units As %DynamicArray) As %DynamicObject
{
    set survivingSoldiers = 0, weightedMorale = 0
    if '$isobject(units) return {"armyMorale":0,"survivingSoldiers":0}

    for index = 0:1:(units.%Size()-1) {
        set unit = units.%Get(index)
        if '$isobject(unit) continue
        set soldiers = +unit.%Get("soldiers", 0)
        if soldiers <= 0 continue
        set survivingSoldiers = survivingSoldiers + soldiers
        set weightedMorale = weightedMorale + (+unit.%Get("morale", 0) * soldiers)
    }
    set armyMorale = 0
    if survivingSoldiers > 0 set armyMorale = weightedMorale / survivingSoldiers
    return {"armyMorale":(armyMorale),"survivingSoldiers":(survivingSoldiers)}
}

ClassMethod Evaluate(armyMorale As %Numeric, ownSurvivingSoldiers As %Integer, enemySurvivingSoldiers As %Integer, surrenderPressureTurns As %Integer = 0) As %DynamicObject
{
    set pressure = +surrenderPressureTurns
    if pressure < 0 set pressure = 0
    set result = {"surrendered":false,"reason":null,"armyMorale":(+armyMorale),"relativeStrength":null,"surrenderPressureTurns":(pressure)}

    if enemySurvivingSoldiers <= 0 {
        set result.surrenderPressureTurns = 0
        return result
    }

    set relativeStrength = ownSurvivingSoldiers / enemySurvivingSoldiers
    set result.relativeStrength = relativeStrength
    if armyMorale <= 10 {
        set result.surrendered = 1
        set result.reason = ..#REASONCRITICALMORALE
        return result
    }

    if (armyMorale <= 30) && (relativeStrength <= .5) && (relativeStrength < .9) {
        set pressure = pressure + 1
        set result.surrenderPressureTurns = pressure
        if pressure >= 2 {
            set result.surrendered = 1
            set result.reason = ..#REASONSUSTAINEDDISADVANTAGE
        }
        return result
    }

    set result.surrenderPressureTurns = 0
    return result
}

ClassMethod EvaluateArmies(army As BronzeWars.Model.Army, enemyArmy As BronzeWars.Model.Army) As %DynamicObject
{
    set ownMetrics = ..ArmyMetrics(army), enemyMetrics = ..ArmyMetrics(enemyArmy)
    return ..Evaluate(ownMetrics.armyMorale, ownMetrics.survivingSoldiers, enemyMetrics.survivingSoldiers, army.SurrenderPressureTurns)
}

ClassMethod ArmyMetrics(army As BronzeWars.Model.Army) As %DynamicObject
{
    return ..Metrics(..ActiveUnits(army))
}

ClassMethod ActiveUnits(army As BronzeWars.Model.Army) As %DynamicArray [ Private ]
{
    set units = ##class(%DynamicArray).%New()
    if '$isobject(army) return units
    set armyId = army.%Id()
    &sql(DECLARE SurrenderUnitCursor CURSOR FOR
        SELECT Morale, CurrentStrength
        FROM BronzeWars_Model.BattleUnit
        WHERE Army = :armyId AND Active = 1 AND CurrentStrength > 0)
    &sql(OPEN SurrenderUnitCursor)
    for {
        &sql(FETCH SurrenderUnitCursor INTO :morale, :soldiers)
        quit:(SQLCODE'=0)
        do units.%Push({"morale":(morale),"soldiers":(soldiers)})
    }
    &sql(CLOSE SurrenderUnitCursor)
    return units
}

}
