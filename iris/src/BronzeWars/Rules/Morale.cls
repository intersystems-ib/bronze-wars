Class BronzeWars.Rules.Morale Extends %RegisteredObject
{

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

}
