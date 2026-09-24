Class BronzeWars.Tests.ModelTest Extends %UnitTest.TestCase
{

Method Test01SeedContainsExpectedUnits()
{
    set sc = ##class(BronzeWars.Data.Seed).Run()
    do $$$AssertStatusOK(sc, "The seed completes successfully")

    &sql(SELECT COUNT(*) INTO :unitCount FROM BronzeWars_Model.UnitType WHERE Active = 1)
    do $$$AssertEquals(unitCount, 7, "Exactly seven active master unit types exist")

    do ..AssertUnit("LIGHT_INFANTRY", "Infantería ligera", 100, 2, 4, 2, 2, 5, "Proyectiles ligeros")
    do ..AssertUnit("HEAVY_INFANTRY", "Infantería pesada", 100, 1, 7, 9, 1, 8, "Cuerpo a cuerpo")
    do ..AssertUnit("SPEARMEN", "Lanceros", 100, 1, 6, 5, 1, 7, "Cuerpo a cuerpo")
    do ..AssertUnit("LIGHT_CAVALRY", "Caballería ligera", 60, 3, 5, 3, 2, 7, "Jabalinas")
    do ..AssertUnit("HEAVY_CAVALRY", "Caballería pesada", 50, 2, 9, 8, 1, 10, "Cuerpo a cuerpo")
    do ..AssertUnit("CHARIOTS", "Carros", 20, 3, 5, 3, 5, 5, "Flechas")
    do ..AssertUnit("ARCHERS", "Arqueros", 80, 2, 4, 2, 6, 4, "Flechas")
    do ..AssertProfile("CHARIOTS", "EGYPTIAN", 3, 5, 3)
    do ..AssertProfile("CHARIOTS", "ASSYRIAN", 3, 8, 7)
}

Method Test02SeedIsIdempotent()
{
    set sc = ##class(BronzeWars.Data.Seed).Run()
    do $$$AssertStatusOK(sc, "First seed execution succeeds")
    set sc = ##class(BronzeWars.Data.Seed).Run()
    do $$$AssertStatusOK(sc, "Second seed execution succeeds")

    &sql(SELECT COUNT(*) INTO :unitCount FROM BronzeWars_Model.UnitType WHERE Active = 1)
    &sql(SELECT COUNT(*) INTO :profileCount FROM BronzeWars_Model.UnitProfile WHERE Active = 1)
    &sql(SELECT COUNT(*) INTO :modifierCount FROM BronzeWars_Model.UnitModifier m JOIN BronzeWars_Model.UnitType a ON m.AttackerType = a.%ID JOIN BronzeWars_Model.UnitType d ON m.DefenderType = d.%ID WHERE m.Active = 1 AND a.Active = 1 AND d.Active = 1)
    do $$$AssertEquals(unitCount, 7, "Rerunning the seed does not duplicate active unit types")
    do $$$AssertEquals(profileCount, 14, "Rerunning the seed does not duplicate faction profiles")
    do $$$AssertEquals(modifierCount, 16, "Rerunning the seed does not duplicate active modifiers")
}

Method Test03DuplicateUnitCodeIsRejected()
{
    set unitType = ..NewValidUnitType("LIGHT_INFANTRY")
    do $$$AssertStatusNotOK(unitType.%Save(), "A duplicate unit code is rejected")
}

Method Test04DuplicateModifierPairIsRejected()
{
    set attacker = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("SPEARMEN")
    set defender = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_CAVALRY")
    set modifier = ##class(BronzeWars.Model.UnitModifier).%New()
    set modifier.AttackerType = attacker
    set modifier.DefenderType = defender
    set modifier.AttackModifier = 99
    do $$$AssertStatusNotOK(modifier.%Save(), "A duplicate attacker/defender pair is rejected")
}

Method Test05AttackAndDefenseValidation()
{
    set unitType = ..NewValidUnitType("INVALID_ATTACK_TEST")
    set unitType.Attack = 0
    do $$$AssertStatusNotOK(unitType.%Save(), "Attack below 1 is rejected")

    set unitType = ..NewValidUnitType("INVALID_DEFENSE_TEST")
    set unitType.Defense = 11
    do $$$AssertStatusNotOK(unitType.%Save(), "Defense above 10 is rejected")
}

Method Test06BattleUnitGetsInitialStrength()
{
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_CAVALRY")
    set unit = ##class(BronzeWars.Model.BattleUnit).%New(unitType)
    do $$$AssertEquals(unit.CurrentStrength, 60, "A new battle unit copies its type's initial strength")
    do $$$AssertEquals(unit.HasMoved, 0, "A new battle unit has not moved")
    do $$$AssertEquals(unit.Active, 1, "A new battle unit is active")
}

Method Test07DeployedUnitRequiresCoordinates()
{
    set battle = ##class(BronzeWars.Model.Battle).%New()
    set battle.Name = "Validation battle"
    set army = ##class(BronzeWars.Model.Army).%New()
    set army.Battle = battle
    set army.Name = "Validation army"
    set army.Side = "HUMAN"
    set army.Faction = "EGYPTIAN"
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("SPEARMEN")
    set unit = ##class(BronzeWars.Model.BattleUnit).%New(unitType)
    set unit.Battle = battle
    set unit.Army = army
    set unit.IsDeployed = 1
    set unit.PositionX = 2
    do $$$AssertStatusNotOK(unit.%ValidateObject(), "A deployed unit without both coordinates is rejected")
}

Method Test08KnownAndMissingModifiers()
{
    set spearmen = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("SPEARMEN")
    set heavyCavalry = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_CAVALRY")
    set archers = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("ARCHERS")

    do $$$AssertEquals(##class(BronzeWars.Model.UnitModifier).GetAttackModifier(spearmen, heavyCavalry), 3, "Spearmen receive +3 against heavy cavalry")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitModifier).GetAttackModifier(spearmen, archers), 0, "A matchup without a rule has modifier 0")
}

Method AssertUnit(code As %String, name As %String, strength As %Integer, speed As %Integer, attack As %Integer, defense As %Integer, attackRange As %Integer, damage As %Integer, attackDescription As %String)
{
    set sc = 1
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(code, .sc)
    do $$$AssertStatusOK(sc, code _ " can be opened")
    do $$$AssertTrue($isobject(unitType), code _ " exists")
    if '$isobject(unitType) quit
    do $$$AssertEquals(unitType.Name, name, code _ " name matches")
    do $$$AssertEquals(unitType.InitialStrength, strength, code _ " strength matches")
    do $$$AssertEquals(unitType.Speed, speed, code _ " speed matches")
    do $$$AssertEquals(unitType.Attack, attack, code _ " attack matches")
    do $$$AssertEquals(unitType.Defense, defense, code _ " defense matches")
    do $$$AssertEquals(unitType.AttackRange, attackRange, code _ " range matches")
    do $$$AssertEquals(unitType.Damage, damage, code _ " damage matches")
    do $$$AssertEquals(unitType.AttackDescription, attackDescription, code _ " attack description matches")
}

Method NewValidUnitType(code As %String) As BronzeWars.Model.UnitType
{
    set unitType = ##class(BronzeWars.Model.UnitType).%New()
    set unitType.Code = code
    set unitType.Name = "Test unit"
    set unitType.Description = "Test-only unit type"
    set unitType.InitialStrength = 10
    set unitType.Speed = 1
    set unitType.Attack = 5
    set unitType.Defense = 5
    set unitType.AttackRange = 1
    set unitType.Damage = 1
    set unitType.AttackDescription = "Test"
    set unitType.GrainCost = 1
    return unitType
}

Method AssertProfile(code As %String, faction As %String, speed As %Integer, attack As %Integer, defense As %Integer)
{
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(code)
    set profile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(unitType.%Id(), faction)
    do $$$AssertTrue($isobject(profile), code _ "/" _ faction _ " profile exists")
    if '$isobject(profile) quit
    do $$$AssertEquals(profile.Speed, speed, faction _ " speed matches")
    do $$$AssertEquals(profile.Attack, attack, faction _ " attack matches")
    do $$$AssertEquals(profile.Defense, defense, faction _ " defense matches")
}
}
