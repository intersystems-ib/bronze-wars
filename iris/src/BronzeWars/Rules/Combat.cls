Class BronzeWars.Rules.Combat Extends %RegisteredObject
{

ClassMethod Resolve(context As %DynamicObject) As %DynamicObject
{
    if context.type = "RANGED" return ..ResolveRanged(context)

    set attacker = context.attacker, defender = context.defender
    set attackerFactor = ..MoraleFactor(attacker.morale, defender.morale)
    set defenderFactor = ..MoraleFactor(defender.morale, attacker.morale)
    set attackerAttackModifier = attacker.%Get("attackModifier", 0)
    set defenderAttackModifier = defender.%Get("attackModifier", 0)
    set attackerAttack = attacker.attack + attackerAttackModifier
    set defenderAttack = defender.attack + defenderAttackModifier
    if attackerAttack < 0 set attackerAttack = 0
    if defenderAttack < 0 set defenderAttack = 0
    set defenderDefenseModifier = ..DefenseModifier(defender, attacker, "MELEE")
    set attackerDefenseModifier = ..DefenseModifier(attacker, defender, "MELEE")
    set defenderDefense = defender.defense + defenderDefenseModifier
    set attackerDefense = attacker.defense + attackerDefenseModifier
    set defenderBase = (attacker.damage * attackerAttack) / (attackerAttack + defenderDefense)
    set attackerBase = (defender.damage * defenderAttack) / (defenderAttack + attackerDefense)
    set defenderCasualties = +$justify(defenderBase * attackerFactor, 0, 0)
    set attackerCasualties = +$justify(attackerBase * defenderFactor, 0, 0)
    if defenderCasualties > defender.strength set defenderCasualties = defender.strength
    if attackerCasualties > attacker.strength set attackerCasualties = attacker.strength
    set result = {
        "attackerCasualties":(attackerCasualties),
        "defenderCasualties":(defenderCasualties),
        "attackerMoraleFactor":(attackerFactor),
        "defenderMoraleFactor":(defenderFactor),
        "attackerAttackModifier":(attackerAttackModifier),
        "defenderAttackModifier":(defenderAttackModifier),
        "attackerEffectiveAttack":(attackerAttack),
        "defenderEffectiveAttack":(defenderAttack),
        "attackerDefenseModifier":(attackerDefenseModifier),
        "defenderDefenseModifier":(defenderDefenseModifier),
        "attackerEffectiveDefense":(attackerDefense),
        "defenderEffectiveDefense":(defenderDefense),
        "type":"MELEE"
    }
    do ..AddPositionResult(context, result)
    return result
}

ClassMethod ResolveRanged(context As %DynamicObject) As %DynamicObject [ Private ]
{
    set attacker = context.attacker, defender = context.defender
    set distanceFactor = 1 - (.5 * (context.distance - 1) / (attacker.range - 1))
    set defenderDefenseModifier = ..DefenseModifier(defender, attacker, "RANGED")
    set defenderDefense = defender.defense + defenderDefenseModifier
    set defenseFactor = 1 - (defenderDefense / 20)
    set defenderCasualties = +$justify(attacker.damage * distanceFactor * defenseFactor, 0, 0)
    if defenderCasualties < 0 set defenderCasualties = 0
    if defenderCasualties > defender.strength set defenderCasualties = defender.strength
    set result = {
        "attackerCasualties":0,
        "defenderCasualties":(defenderCasualties),
        "distance":(context.distance),
        "distanceFactor":(distanceFactor),
        "defenseFactor":(defenseFactor),
        "defenderDefenseModifier":(defenderDefenseModifier),
        "defenderEffectiveDefense":(defenderDefense),
        "type":"RANGED"
    }
    do ..AddPositionResult(context, result)
    return result
}

ClassMethod AddPositionResult(context As %DynamicObject, result As %DynamicObject) [ Private ]
{
    set direction = ..AttackDirection(context)
    set moralePenalty = $select((direction="FLANK")||(direction="REAR"):10, 1:0)
    do result.%Set("attackDirection", direction)
    do result.%Set("defenderPositionMoralePenalty", moralePenalty)
}

ClassMethod AttackDirection(context As %DynamicObject) As %String
{
    if '$isobject(context) return "FRONT"
    if '$isobject(context.attacker) ! '$isobject(context.defender) return "FRONT"
    if 'context.attacker.%IsDefined("y") ! 'context.defender.%IsDefined("y") ! 'context.defender.%IsDefined("side") return "FRONT"

    set deltaY = context.attacker.y - context.defender.y
    if deltaY = 0 return "FLANK"
    set defenderSide = $zconvert(context.defender.side, "U")
    if (defenderSide = "AI"), (deltaY < 0) return "REAR"
    if (defenderSide = "HUMAN"), (deltaY > 0) return "REAR"
    return "FRONT"
}

ClassMethod DefenseModifier(defender As %DynamicObject, attacker As %DynamicObject, combatType As %String) As %Integer [ Private ]
{
    set defenderCode = $zconvert(defender.%Get("code", ""), "U")
    set attackerCode = $zconvert(attacker.%Get("code", ""), "U")
    if (defenderCode = "LIGHT_CAVALRY"), (combatType = "RANGED") return 2
    if defenderCode = "SPEARMEN", ((attackerCode = "LIGHT_CAVALRY") || (attackerCode = "HEAVY_CAVALRY") || (attackerCode = "CHARIOTS")) return 2
    return 0
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
