Class BronzeWars.AI.Tools.BattleSituation Extends %RegisteredObject
{

/// Description: Returns a compact summary of the AI army morale and casualties in a BronzeWars battle.
ClassMethod GetBattleSituation(battleId As %String) As %DynamicObject
{
    set result = {}
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) {
        do result.%Set("error", $SYSTEM.Status.GetErrorText(sc))
        return result
    }
    if '$isobject(battle) {
        do result.%Set("error", "Battle not found")
        return result
    }

    &sql(SELECT %ID INTO :armyId FROM BronzeWars_Model.Army WHERE Battle = :battleId AND Side = 'AI')
    if SQLCODE '= 0 {
        do result.%Set("error", "AI army not found")
        return result
    }

    &sql(
        SELECT
            COALESCE(AVG(CASE WHEN u.Active = 1 THEN u.Morale ELSE NULL END), 0),
            COALESCE(SUM(COALESCE(p.InitialStrength, t.InitialStrength)), 0),
            COALESCE(SUM(u.CurrentStrength), 0)
        INTO :averageMorale, :initialStrength, :currentStrength
        FROM BronzeWars_Model.BattleUnit u
        JOIN BronzeWars_Model.UnitType t ON u.UnitType = t.%ID
        LEFT JOIN BronzeWars_Model.UnitProfile p ON u.UnitProfile = p.%ID
        WHERE u.Army = :armyId
    )
    if SQLCODE < 0 {
        do result.%Set("error", "Unable to calculate the AI army situation")
        return result
    }

    set casualties = initialStrength - currentStrength
    if casualties < 0 set casualties = 0
    set casualtiesPercentage = 0
    if initialStrength > 0 set casualtiesPercentage = +$justify((casualties * 100) / initialStrength, 0, 1)

    set result = {
        "averageMorale":(+$justify(averageMorale, 0, 1)),
        "morale":(..DescribeMorale(averageMorale)),
        "casualtiesPercentage":(casualtiesPercentage),
        "battleState":(..Classify(averageMorale, casualtiesPercentage)),
        "recommendedStrategy":(..RecommendedStrategy(averageMorale, casualtiesPercentage))
    }
    return result
}

ClassMethod Classify(averageMorale As %Numeric, casualtiesPercentage As %Numeric) As %String
{
    if (averageMorale < 50), (casualtiesPercentage >= 50) return "BAD"
    if (averageMorale > 50), (casualtiesPercentage < 50) return "GOOD"
    return "NEUTRAL"
}

ClassMethod RecommendedStrategy(averageMorale As %Numeric, casualtiesPercentage As %Numeric) As %String
{
    set state = ..Classify(averageMorale, casualtiesPercentage)
    if state = "BAD" return "REGROUP"
    if state = "GOOD" return "ADVANCE"
    return "TACTICAL"
}

ClassMethod DescribeMorale(averageMorale As %Numeric) As %String
{
    if averageMorale >= 80 return "very high"
    if averageMorale >= 60 return "high"
    if averageMorale >= 40 return "normal"
    if averageMorale >= 20 return "low"
    return "very low"
}

}
