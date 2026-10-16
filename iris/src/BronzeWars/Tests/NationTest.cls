Class BronzeWars.Tests.NationTest Extends %UnitTest.TestCase
{

Method Test01NationalProfiles()
{
    set sc = ##class(BronzeWars.Data.Seed).Run()
    do $$$AssertStatusOK(sc, "National profiles are seeded")
    set sc = ##class(BronzeWars.Data.Seed).Run()
    do $$$AssertStatusOK(sc, "National profiles can be seeded repeatedly")
    &sql(SELECT COUNT(*) INTO :profileCount FROM BronzeWars_Model.UnitProfile WHERE Faction = 'NUBIAN' AND Active = 1)
    do $$$AssertEquals(profileCount, 3, "Nubia has exactly its three illustrated troop types")
    &sql(SELECT COUNT(*) INTO :profileCount FROM BronzeWars_Model.UnitProfile WHERE Faction = 'SEA_PEOPLES' AND Active = 1)
    do $$$AssertEquals(profileCount, 4, "Sea Peoples have exactly their four illustrated troop types")
    set archers = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("ARCHERS")
    set nubian = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(archers.%Id(), "NUBIAN")
    set seaPeoples = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(archers.%Id(), "SEA_PEOPLES")
    do $$$AssertEquals(nubian.Attack, 5, "Nubian archers gain one attack")
    do $$$AssertEquals(nubian.Defense, 1, "Nubian archers trade one defense")
    do $$$AssertEquals(nubian.Damage, 9, "Nubian archers gain one damage")
    do $$$AssertEquals(seaPeoples.Defense, 3, "Sea Peoples archers gain one defense")
    do $$$AssertEquals(seaPeoples.Damage, 7, "Sea Peoples archers trade one damage")
}

Method Test02CreateNationalArmies()
{
    for faction = "NUBIAN","SEA_PEOPLES" {
        set result = ##class(BronzeWars.Interop.Client).CreateBattle({"name":("National army " _ faction),"faction":(faction)})
        do $$$AssertTrue(result.ok, faction _ " can create a battle through the production")
        if 'result.ok continue
        set army = result.data.battle.armies.%Get(0), spent = 0
        do $$$AssertEquals(army.faction, faction, "The selected nation is persisted")
        for index = 0:1:(army.units.%Size()-1) {
            set unit = army.units.%Get(index)
            set stored = ##class(BronzeWars.Model.BattleUnit).%OpenId(unit.id)
            do $$$AssertEquals(stored.UnitProfile.Faction, faction, "Each battle unit uses its national profile")
            do $$$AssertEquals(unit.type.attack, stored.UnitProfile.Attack, "The API exposes national attack")
            do $$$AssertEquals(unit.type.defense, stored.UnitProfile.Defense, "The API exposes national defense")
            do $$$AssertEquals(unit.type.damage, stored.UnitProfile.Damage, "The API exposes national damage")
            set spent = spent + unit.type.grainCost
        }
        do $$$AssertEquals(spent, 100, "The national default army spends exactly one hundred grain")
        set invalid = ##class(BronzeWars.Interop.Client).CreateBattle({"name":"Unavailable cavalry","faction":(faction),"units":[{"code":"HEAVY_CAVALRY","quantity":1}]})
        do $$$AssertNotTrue(invalid.ok, "The API rejects cavalry absent from the national roster")
        do $$$AssertEquals(invalid.status, 422, "Unavailable troops return a validation error")
    }
    set invalid = ##class(BronzeWars.Interop.Client).CreateBattle({"name":"Unavailable heavy infantry","faction":"NUBIAN","units":[{"code":"HEAVY_INFANTRY","quantity":1}]})
    do $$$AssertNotTrue(invalid.ok, "Nubia cannot select Sea Peoples heavy infantry")
}

Method Test03SpearmenKeepMatchupAdvantages()
{
    set spearmen = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("SPEARMEN")
    for faction = "NUBIAN","SEA_PEOPLES" {
        set serialized = ##class(BronzeWars.API.Serializer).UnitType(spearmen, 1, faction)
        kill modifiers
        for index = 0:1:(serialized.attackModifiers.%Size()-1) {
            set modifier = serialized.attackModifiers.%Get(index)
            set modifiers(modifier.defenderCode) = modifier.value
        }
        do $$$AssertEquals(modifiers("LIGHT_CAVALRY"), 3, "National spearmen retain their light cavalry advantage")
        do $$$AssertEquals(modifiers("HEAVY_CAVALRY"), 3, "National spearmen retain their heavy cavalry advantage")
        do $$$AssertEquals(modifiers("CHARIOTS"), 2, "National spearmen retain their chariot advantage")
        do $$$AssertEquals(modifiers("HEAVY_INFANTRY"), -2, "National spearmen retain their heavy infantry disadvantage")
    }
}

}
