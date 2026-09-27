Class BronzeWars.Data.Seed Extends %RegisteredObject
{
ClassMethod Run() As %Status
{
    set sc = ..SeedUnitTypes()
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..SeedUnitProfiles()
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..SeedModifiers()
    return:$SYSTEM.Status.IsError(sc) sc
    return ..BackfillBattleUnitTurnState()
}

ClassMethod BackfillBattleUnitTurnState() As %Status [ Private ]
{
    &sql(UPDATE BronzeWars_Model.BattleUnit SET Morale = 100 WHERE Morale IS NULL)
    if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to initialize battle unit morale: " _ SQLCODE _ " " _ $get(%msg))
    &sql(UPDATE BronzeWars_Model.BattleUnit SET MovementSpent = 0 WHERE MovementSpent IS NULL)
    if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to initialize battle unit movement: " _ SQLCODE _ " " _ $get(%msg))
    &sql(DECLARE ProjectileCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE CurrentProjectiles IS NULL)
    &sql(OPEN ProjectileCursor)
    for {
        &sql(FETCH ProjectileCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId)
        set unit.CurrentProjectiles = unit.UnitType.InitialProjectiles
        set sc = unit.%Save()
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE ProjectileCursor)
            return sc
        }
    }
    &sql(CLOSE ProjectileCursor)

    &sql(DECLARE AttackStateCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE HasAttacked IS NULL)
    &sql(OPEN AttackStateCursor)
    for {
        &sql(FETCH AttackStateCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId)
        set unit.HasAttacked = 0
        set sc = unit.%Save()
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE AttackStateCursor)
            return sc
        }
    }
    &sql(CLOSE AttackStateCursor)
    return $$$OK
}

ClassMethod SeedUnitTypes() As %Status [ Private ]
{
    set sc = ..UpsertUnitType("LIGHT_INFANTRY", "Infantería ligera", "Escaramuceadores, honderos y tropas poco protegidas.", 100, 2, 4, 2, 2, 5, "Proyectiles ligeros", 10)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertUnitType("HEAVY_INFANTRY", "Infantería pesada", "Tropas con armadura, escudos pesados, lanzas cortas y espadas.", 100, 1, 7, 9, 1, 8, "Cuerpo a cuerpo", 0)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertUnitType("MERCENARIES", "Mercenarios", "Soldados profesionales versátiles, con protección y capacidad de combate intermedias.", 100, 2, 6, 6, 1, 7, "Cuerpo a cuerpo", 0)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertUnitType("SPEARMEN", "Lanceros", "Buenos contra caballería y carros, malos contra infantería pesada y ligeramente protegidos.", 100, 1, 6, 5, 1, 7, "Cuerpo a cuerpo", 0)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertUnitType("LIGHT_CAVALRY", "Caballería ligera", "Rápida y equipada con armas arrojadizas.", 30, 3, 5, 3, 2, 14, "Jabalinas", 5)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertUnitType("HEAVY_CAVALRY", "Caballería pesada", "Menos rápida, bien protegida y destinada al choque.", 25, 2, 9, 8, 1, 10, "Cuerpo a cuerpo", 0)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertUnitType("CHARIOTS", "Carros", "Plataformas móviles cuyo equipamiento depende de la facción.", 20, 3, 5, 3, 5, 10, "Flechas", 10)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertUnitType("ARCHERS", "Arqueros", "Especialistas en disparo lejano.", 80, 2, 4, 2, 6, 8, "Flechas", 20)
    return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..SetUnitTypeActive("LIGHT_CHARIOTS", 0)
    return:$SYSTEM.Status.IsError(sc) sc
    return ..SetUnitTypeActive("HEAVY_CHARIOTS", 0)
}

ClassMethod SeedUnitProfiles() As %Status [ Private ]
{
    for faction = "EGYPTIAN","ASSYRIAN" {
        set sc = ..CopyProfile("LIGHT_INFANTRY", faction) return:$SYSTEM.Status.IsError(sc) sc
        set sc = ..CopyProfile("HEAVY_INFANTRY", faction) return:$SYSTEM.Status.IsError(sc) sc
        set sc = ..CopyProfile("MERCENARIES", faction) return:$SYSTEM.Status.IsError(sc) sc
        set sc = ..CopyProfile("SPEARMEN", faction) return:$SYSTEM.Status.IsError(sc) sc
        set sc = ..CopyProfile("LIGHT_CAVALRY", faction) return:$SYSTEM.Status.IsError(sc) sc
        set sc = ..CopyProfile("HEAVY_CAVALRY", faction) return:$SYSTEM.Status.IsError(sc) sc
        set sc = ..CopyProfile("ARCHERS", faction) return:$SYSTEM.Status.IsError(sc) sc
    }
    set sc = ..UpsertUnitProfile("CHARIOTS", "EGYPTIAN", 20, 3, 5, 3, 5, 10, "Flechas", 25)
    return:$SYSTEM.Status.IsError(sc) sc
    return ..UpsertUnitProfile("CHARIOTS", "ASSYRIAN", 15, 3, 8, 7, 2, 18, "Jabalinas", 25)
}

ClassMethod SeedModifiers() As %Status [ Private ]
{
    set sc = ..UpsertModifier("LIGHT_INFANTRY", "SPEARMEN", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("HEAVY_INFANTRY", "LIGHT_INFANTRY", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("HEAVY_INFANTRY", "SPEARMEN", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("SPEARMEN", "LIGHT_CAVALRY", 3) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("SPEARMEN", "HEAVY_CAVALRY", 3) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("SPEARMEN", "CHARIOTS", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("SPEARMEN", "HEAVY_INFANTRY", -2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("LIGHT_CAVALRY", "ARCHERS", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("HEAVY_CAVALRY", "ARCHERS", 3) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("HEAVY_CAVALRY", "LIGHT_INFANTRY", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("CHARIOTS", "LIGHT_INFANTRY", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("CHARIOTS", "HEAVY_INFANTRY", -2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("CHARIOTS", "ARCHERS", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("ARCHERS", "LIGHT_INFANTRY", 2) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("ARCHERS", "HEAVY_INFANTRY", -3) return:$SYSTEM.Status.IsError(sc) sc
    set sc = ..UpsertModifier("ARCHERS", "HEAVY_CAVALRY", -2)
    return sc
}

ClassMethod UpsertUnitType(code As %String, name As %String, description As %String, initialStrength As %Integer, speed As %Integer, attack As %Integer, defense As %Integer, attackRange As %Integer, damage As %Integer, attackDescription As %String, initialProjectiles As %Integer) As %Status [ Private ]
{
    set sc = $$$OK
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(code, .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    set previousStrength = initialStrength
    if '$isobject(unitType) {
        set unitType = ##class(BronzeWars.Model.UnitType).%New()
        set unitType.Code = code
    } else {
        set previousStrength = unitType.InitialStrength
    }
    set unitType.Name = name
    set unitType.Description = description
    set unitType.InitialStrength = initialStrength
    set unitType.Speed = speed
    set unitType.Attack = attack
    set unitType.Defense = defense
    set unitType.AttackRange = attackRange
    set unitType.Damage = damage
    set unitType.AttackDescription = attackDescription
    set unitType.InitialProjectiles = initialProjectiles
    set unitType.GrainCost = ##class(BronzeWars.Rules.ArmyBudget).GrainCost(code)
    set unitType.Active = 1
    set sc = unitType.%Save()
    return:$SYSTEM.Status.IsError(sc) sc
    if previousStrength '= initialStrength {
        set unitTypeId = unitType.%Id()
        &sql(UPDATE BronzeWars_Model.BattleUnit
             SET CurrentStrength = ROUND((CurrentStrength * :initialStrength) / :previousStrength, 0)
             WHERE UnitType = :unitTypeId AND UnitProfile IS NULL)
        if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to rescale battle units for " _ code _ ": " _ SQLCODE _ " " _ $get(%msg))
    }
    return $$$OK
}

ClassMethod UpsertModifier(attackerCode As %String, defenderCode As %String, attackModifier As %Integer) As %Status [ Private ]
{
    set sc = $$$OK
    set attacker = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(attackerCode, .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    return:'$isobject(attacker) $$$ERROR($$$GeneralError, "Unknown attacker unit type: " _ attackerCode)
    set defender = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(defenderCode, .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    return:'$isobject(defender) $$$ERROR($$$GeneralError, "Unknown defender unit type: " _ defenderCode)
    set unitModifier = ##class(BronzeWars.Model.UnitModifier).MatchupIndexOpen(attacker.%Id(), defender.%Id(), .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    if '$isobject(unitModifier) set unitModifier = ##class(BronzeWars.Model.UnitModifier).%New()
    set unitModifier.AttackerType = attacker
    set unitModifier.DefenderType = defender
    set unitModifier.AttackModifier = attackModifier
    set unitModifier.Active = 1
    return unitModifier.%Save()
}

ClassMethod SetUnitTypeActive(code As %String, active As %Boolean) As %Status [ Private ]
{
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(code, .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    if '$isobject(unitType) return $$$OK
    set unitType.Active = active
    return unitType.%Save()
}

ClassMethod CopyProfile(code As %String, faction As %String) As %Status [ Private ]
{
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(code, .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    if '$isobject(unitType) return $$$ERROR($$$GeneralError, "Unknown unit type: " _ code)
    return ..UpsertUnitProfile(code, faction, unitType.InitialStrength, unitType.Speed, unitType.Attack, unitType.Defense, unitType.AttackRange, unitType.Damage, unitType.AttackDescription, unitType.GrainCost)
}

ClassMethod UpsertUnitProfile(code As %String, faction As %String, initialStrength As %Integer, speed As %Integer, attack As %Integer, defense As %Integer, attackRange As %Integer, damage As %Integer, attackDescription As %String, grainCost As %Integer) As %Status [ Private ]
{
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(code, .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    if '$isobject(unitType) return $$$ERROR($$$GeneralError, "Unknown unit type: " _ code)
    set profile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(unitType.%Id(), faction, .sc)
    return:$SYSTEM.Status.IsError(sc) sc
    set previousStrength = initialStrength
    if '$isobject(profile) {
        set profile = ##class(BronzeWars.Model.UnitProfile).%New()
    } else {
        set previousStrength = profile.InitialStrength
    }
    set profile.UnitType = unitType, profile.Faction = faction
    set profile.InitialStrength = initialStrength, profile.Speed = speed
    set profile.Attack = attack, profile.Defense = defense, profile.AttackRange = attackRange
    set profile.Damage = damage, profile.AttackDescription = attackDescription
    set profile.GrainCost = grainCost, profile.Active = 1
    set sc = profile.%Save()
    return:$SYSTEM.Status.IsError(sc) sc
    if previousStrength '= initialStrength {
        set profileId = profile.%Id()
        &sql(UPDATE BronzeWars_Model.BattleUnit
             SET CurrentStrength = ROUND((CurrentStrength * :initialStrength) / :previousStrength, 0)
             WHERE UnitProfile = :profileId)
        if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to rescale " _ faction _ " battle units for " _ code _ ": " _ SQLCODE _ " " _ $get(%msg))
    }
    return $$$OK
}
}
