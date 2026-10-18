Class BronzeWars.Rules.Surrender Extends %RegisteredObject
{

Parameter REASONCRITICALMORALE = "CRITICAL_MORALE";
Parameter REASONLOWFORCESANDMORALE = "LOW_FORCES_AND_MORALE";
Parameter CRITICALMORALEPERCENT = 10;
Parameter SURRENDERMORALEPERCENT = 33;
Parameter SURRENDERFORCESPERCENT = 33;

ClassMethod Metrics(units As %DynamicArray) As %DynamicObject
{
    set survivingSoldiers = 0, initialSoldiers = 0, weightedMorale = 0, withdrawnSoldiers = 0
    if '$isobject(units) return {"armyMorale":0,"initialSoldiers":0,"survivingSoldiers":0,"withdrawnSoldiers":0,"troopPercentage":0,"moralePercentage":0}

    for index = 0:1:(units.%Size()-1) {
        set unit = units.%Get(index)
        if '$isobject(unit) continue
        set soldiers = +unit.%Get("soldiers", 0)
        set initialStrength = +unit.%Get("initialStrength", soldiers)
        set active = unit.%Get("active", 1)
        if initialStrength > 0 set initialSoldiers = initialSoldiers + initialStrength
        if ('active) && (soldiers > 0) set withdrawnSoldiers = withdrawnSoldiers + soldiers
        if ('active) || (soldiers <= 0) continue
        set survivingSoldiers = survivingSoldiers + soldiers
        set weightedMorale = weightedMorale + (+unit.%Get("morale", 0) * soldiers)
    }

    set armyMorale = 0, troopPercentage = 0, moralePercentage = 0
    if survivingSoldiers > 0 set armyMorale = weightedMorale / survivingSoldiers
    if initialSoldiers > 0 {
        set troopPercentage = (survivingSoldiers * 100) / initialSoldiers
        set moralePercentage = weightedMorale / initialSoldiers
    }
    return {"armyMorale":(armyMorale),"initialSoldiers":(initialSoldiers),"survivingSoldiers":(survivingSoldiers),"withdrawnSoldiers":(withdrawnSoldiers),"troopPercentage":(troopPercentage),"moralePercentage":(moralePercentage)}
}

ClassMethod Evaluate(armyMorale As %Numeric, troopPercentage As %Numeric, moralePercentage As %Numeric, ownSurvivingSoldiers As %Integer, enemySurvivingSoldiers As %Integer, surrenderPressureTurns As %Integer = 0) As %DynamicObject
{
    // Retain the legacy pressure field and argument for stored battles and API compatibility.
    set result = {"surrendered":false,"reason":null,"armyMorale":(+armyMorale),"troopPercentage":(+troopPercentage),"moralePercentage":(+moralePercentage),"relativeStrength":null,"surrenderPressureTurns":0}

    if enemySurvivingSoldiers <= 0 {
        set result.surrenderPressureTurns = 0
        return result
    }

    if ownSurvivingSoldiers > 0 {
        set relativeStrength = ownSurvivingSoldiers / enemySurvivingSoldiers
        set result.relativeStrength = relativeStrength
    } else {
        set result.relativeStrength = 0
    }

    if moralePercentage < ..#CRITICALMORALEPERCENT {
        set result.surrendered = 1
        set result.reason = ..#REASONCRITICALMORALE
        return result
    }

    if (troopPercentage < ..#SURRENDERFORCESPERCENT) && (moralePercentage < ..#SURRENDERMORALEPERCENT) {
        set result.surrendered = 1
        set result.reason = ..#REASONLOWFORCESANDMORALE
        return result
    }

    set result.surrenderPressureTurns = 0
    return result
}

ClassMethod EvaluateArmies(army As BronzeWars.Model.Army, enemyArmy As BronzeWars.Model.Army) As %DynamicObject
{
    set ownMetrics = ..ArmyMetrics(army), enemyMetrics = ..ArmyMetrics(enemyArmy)
    return ..Evaluate(ownMetrics.armyMorale, ownMetrics.troopPercentage, ownMetrics.moralePercentage, ownMetrics.survivingSoldiers, enemyMetrics.survivingSoldiers, army.SurrenderPressureTurns)
}

ClassMethod ArmyMetrics(army As BronzeWars.Model.Army) As %DynamicObject
{
    return ..Metrics(..ArmyUnits(army))
}

ClassMethod ArmyUnits(army As BronzeWars.Model.Army) As %DynamicArray [ Private ]
{
    set units = ##class(%DynamicArray).%New()
    if '$isobject(army) return units
    set armyId = army.%Id()
    &sql(DECLARE SurrenderUnitCursor CURSOR FOR
        SELECT %ID
        FROM BronzeWars_Model.BattleUnit
        WHERE Army = :armyId)
    &sql(OPEN SurrenderUnitCursor)
    for {
        &sql(FETCH SurrenderUnitCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId)
        if '$isobject(unit) continue
        set initialStrength = unit.UnitType.InitialStrength
        if $isobject(unit.UnitProfile) set initialStrength = unit.UnitProfile.InitialStrength
        do units.%Push({"morale":(unit.Morale),"soldiers":(unit.CurrentStrength),"initialStrength":(initialStrength),"active":(unit.Active)})
    }
    &sql(CLOSE SurrenderUnitCursor)
    return units
}

}
