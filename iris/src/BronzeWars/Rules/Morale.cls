Class BronzeWars.Rules.Morale Extends %RegisteredObject
{

Parameter ATTACKMINIMUM = 20;

ClassMethod LossForCasualties(unit As BronzeWars.Model.BattleUnit, casualties As %Integer) As %Integer
{
    if casualties <= 0 return 0

    set initialStrength = unit.UnitType.InitialStrength
    if $isobject(unit.UnitProfile) set initialStrength = unit.UnitProfile.InitialStrength
    if initialStrength <= 0 return casualties

    set loss = +$justify((casualties * 100) / initialStrength, 0, 0)
    if loss < 1 set loss = 1
    return loss
}

ClassMethod AfterCasualties(unit As BronzeWars.Model.BattleUnit, moraleBefore As %Integer, casualties As %Integer) As %Integer
{
    set moraleAfter = moraleBefore - ..LossForCasualties(unit, casualties)
    if moraleAfter < 0 set moraleAfter = 0
    return moraleAfter
}

ClassMethod RecoveryForStrength(unit As BronzeWars.Model.BattleUnit) As %Integer
{
    if '$isobject(unit) return 0

    set initialStrength = unit.UnitType.InitialStrength
    if $isobject(unit.UnitProfile) set initialStrength = unit.UnitProfile.InitialStrength
    if initialStrength <= 0 return 0

    set recovery = +$justify((20 * unit.CurrentStrength) / initialStrength, 0, 0)
    if recovery < 0 set recovery = 0
    if recovery > 20 set recovery = 20
    return recovery
}

ClassMethod CanAttack(unit As BronzeWars.Model.BattleUnit) As %Boolean
{
    if '$isobject(unit) return 0
    return unit.Morale > ..#ATTACKMINIMUM
}

ClassMethod IsCriticallyDepleted(unit As BronzeWars.Model.BattleUnit) As %Boolean
{
    if '$isobject(unit) return 0

    set initialStrength = unit.UnitType.InitialStrength
    if $isobject(unit.UnitProfile) set initialStrength = unit.UnitProfile.InitialStrength
    if initialStrength <= 0 return 0
    return (unit.CurrentStrength * 3) <= initialStrength
}

}
