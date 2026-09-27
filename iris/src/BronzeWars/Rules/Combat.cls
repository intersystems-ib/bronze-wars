Class BronzeWars.Rules.Combat Extends %RegisteredObject
{

ClassMethod Resolve(context As %DynamicObject) As %DynamicObject
{
    if context.type = "RANGED" return ..ResolveRanged(context)

    set attacker = context.attacker, defender = context.defender
    set attackerFactor = ..MoraleFactor(attacker.morale, defender.morale)
    set defenderFactor = ..MoraleFactor(defender.morale, attacker.morale)
    set defenderBase = (attacker.damage * attacker.attack) / (attacker.attack + defender.defense)
    set attackerBase = (defender.damage * defender.attack) / (defender.attack + attacker.defense)
    set defenderCasualties = +$justify(defenderBase * attackerFactor, 0, 0)
    set attackerCasualties = +$justify(attackerBase * defenderFactor, 0, 0)
    if defenderCasualties > defender.strength set defenderCasualties = defender.strength
    if attackerCasualties > attacker.strength set attackerCasualties = attacker.strength
    return {
        "attackerCasualties":(attackerCasualties),
        "defenderCasualties":(defenderCasualties),
        "attackerMoraleFactor":(attackerFactor),
        "defenderMoraleFactor":(defenderFactor),
        "type":"MELEE"
    }
}

ClassMethod ResolveRanged(context As %DynamicObject) As %DynamicObject [ Private ]
{
    set attacker = context.attacker, defender = context.defender
    set distanceFactor = 1 - (.5 * (context.distance - 1) / (attacker.range - 1))
    set defenseFactor = 1 - (defender.defense / 20)
    set defenderCasualties = +$justify(attacker.damage * distanceFactor * defenseFactor, 0, 0)
    if defenderCasualties < 0 set defenderCasualties = 0
    if defenderCasualties > defender.strength set defenderCasualties = defender.strength
    return {
        "attackerCasualties":0,
        "defenderCasualties":(defenderCasualties),
        "distance":(context.distance),
        "distanceFactor":(distanceFactor),
        "defenseFactor":(defenseFactor),
        "type":"RANGED"
    }
}

ClassMethod MoraleFactor(sourceMorale As %Numeric, opposingMorale As %Numeric) As %Numeric [ Private ]
{
    if sourceMorale <= 0 return 0
    if opposingMorale <= 0 return 1
    set factor = sourceMorale / opposingMorale
    if factor > 1 set factor = 1
    return factor
}

}
