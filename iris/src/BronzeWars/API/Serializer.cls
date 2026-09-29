Class BronzeWars.API.Serializer Extends %RegisteredObject
{

ClassMethod UnitType(unitType As BronzeWars.Model.UnitType, includeStats As %Boolean = 1, faction As %String = "") As %DynamicObject
{
    set value = {"id":(unitType.Code),"code":(unitType.Code),"name":(unitType.Name)}
    if includeStats {
        do value.%Set("description", unitType.Description)
        set profile = ""
        if faction '= "" set profile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(unitType.%Id(), faction)
        if $isobject(profile) {
            do ..ApplyStats(value, profile)
        } else {
            do ..ApplyStats(value, unitType)
        }
        do value.%Set("initialProjectiles", unitType.InitialProjectiles)
        set attackModifiers = ##class(%DynamicArray).%New(), attackerTypeId = unitType.%Id()
        &sql(DECLARE AttackModifierCursor CURSOR FOR
            SELECT %ID FROM BronzeWars_Model.UnitModifier
            WHERE AttackerType = :attackerTypeId AND Active = 1
            ORDER BY DefenderType)
        &sql(OPEN AttackModifierCursor)
        for {
            &sql(FETCH AttackModifierCursor INTO :modifierId)
            quit:(SQLCODE'=0)
            set modifier = ##class(BronzeWars.Model.UnitModifier).%OpenId(modifierId)
            do attackModifiers.%Push({"defenderCode":(modifier.DefenderType.Code),"value":(modifier.AttackModifier)})
        }
        &sql(CLOSE AttackModifierCursor)
        do value.%Set("attackModifiers", attackModifiers)
        if faction = "" {
            set profiles = ##class(%DynamicObject).%New(), unitTypeId = unitType.%Id()
            &sql(DECLARE ProfileCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.UnitProfile WHERE UnitType = :unitTypeId AND Active = 1 ORDER BY Faction)
            &sql(OPEN ProfileCursor)
            for {
                &sql(FETCH ProfileCursor INTO :profileId)
                quit:(SQLCODE'=0)
                set profile = ##class(BronzeWars.Model.UnitProfile).%OpenId(profileId), stats = ##class(%DynamicObject).%New()
                do ..ApplyStats(stats, profile)
                do profiles.%Set($zconvert(profile.Faction, "L"), stats)
            }
            &sql(CLOSE ProfileCursor)
            do value.%Set("profiles", profiles)
        }
    }
    return value
}

ClassMethod ApplyStats(value As %DynamicObject, source As %RegisteredObject)
{
    do value.%Set("initialStrength", source.InitialStrength)
    do value.%Set("speed", source.Speed)
    do value.%Set("attack", source.Attack)
    do value.%Set("defense", source.Defense)
    do value.%Set("attackRange", source.AttackRange)
    do value.%Set("damage", source.Damage)
    do value.%Set("attackDescription", source.AttackDescription)
    do value.%Set("grainCost", source.GrainCost)
}

ClassMethod BattleUnit(unit As BronzeWars.Model.BattleUnit, hidePosition As %Boolean = 0) As %DynamicObject
{
    set morale = $select(unit.Morale="":100, 1:unit.Morale)
    set movementSpent = $select(unit.MovementSpent="":0, 1:unit.MovementSpent)
    set speed = unit.UnitType.Speed
    if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed
    set remainingMovement = speed - movementSpent
    if remainingMovement < 0 set remainingMovement = 0
    set unitType = ..UnitType(unit.UnitType, 1, unit.Army.Faction)
    set projectiles = $select(unit.CurrentProjectiles="":unit.UnitType.InitialProjectiles, 1:unit.CurrentProjectiles)
    set value = {"id":(unit.%Id()),"name":(unit.Name),"type":(unitType),"currentStrength":(unit.CurrentStrength),"projectiles":(projectiles),"morale":(morale),"movementSpent":(movementSpent),"remainingMovement":(remainingMovement),"isDeployed":(unit.IsDeployed),"hasMoved":(unit.HasMoved),"hasAttacked":(unit.HasAttacked),"active":(unit.Active)}
    if hidePosition || 'unit.IsDeployed {
        do value.%Set("position", "", "null")
    } else {
        do value.%Set("position", {"x":(unit.PositionX),"y":(unit.PositionY)})
    }
    return value
}

ClassMethod Army(army As BronzeWars.Model.Army, hidePositions As %Boolean = 0) As %DynamicObject
{
    set value = {"id":(army.%Id()),"side":(army.Side),"faction":(army.Faction),"name":(army.Name),"units":(##class(%DynamicArray).%New())}
    if army.CommanderType = "" {
        do value.%Set("commanderType", "", "null")
        do value.%Set("commanderName", "", "null")
    } else {
        do value.%Set("commanderType", army.CommanderType)
        do value.%Set("commanderName", ##class(BronzeWars.AI.Commanders.Strategy).Label(army.CommanderType))
    }
    &sql(DECLARE UnitCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :armyId ORDER BY UnitType)
    set armyId = army.%Id()
    &sql(OPEN UnitCursor)
    for {
        &sql(FETCH UnitCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId)
        do value.units.%Push(..BattleUnit(unit, hidePositions))
    }
    &sql(CLOSE UnitCursor)
    return value
}

ClassMethod Battle(battle As BronzeWars.Model.Battle, hideAIPositions As %Boolean = 0) As %DynamicObject
{
    set value = {"id":(battle.%Id()),"name":(battle.Name),"status":(battle.Status),"phase":(battle.Phase),"currentRound":(battle.CurrentRound),"createdAt":(..Timestamp(battle.CreatedAt)),"board":{"width":(battle.BoardWidth),"height":(battle.BoardHeight)},"armies":(##class(%DynamicArray).%New())}
    if battle.StartedAt = "" do value.%Set("startedAt", "", "null")
    if battle.StartedAt '= "" do value.%Set("startedAt", ..Timestamp(battle.StartedAt))
    if battle.FinishedAt = "" do value.%Set("finishedAt", "", "null")
    if battle.FinishedAt '= "" do value.%Set("finishedAt", ..Timestamp(battle.FinishedAt))
    set battleId = battle.%Id()
    &sql(DECLARE ArmyCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.Army WHERE Battle = :battleId ORDER BY Side DESC)
    &sql(OPEN ArmyCursor)
    for {
        &sql(FETCH ArmyCursor INTO :armyId)
        quit:(SQLCODE'=0)
        set army = ##class(BronzeWars.Model.Army).%OpenId(armyId)
        set hide = hideAIPositions && (army.Side = "AI")
        do value.armies.%Push(..Army(army, hide))
    }
    &sql(CLOSE ArmyCursor)
    return value
}

ClassMethod Deployment(battle As BronzeWars.Model.Battle) As %DynamicObject
{
    set height = battle.BoardHeight
    set value = {"battleId":(battle.%Id()),"phase":(battle.Phase),"board":{"width":(battle.BoardWidth),"height":(height)},"zones":{"human":{"minX":0,"maxX":(battle.BoardWidth-1),"minY":(height-3),"maxY":(height-1)},"ai":{"minX":0,"maxX":(battle.BoardWidth-1),"minY":0,"maxY":2}},"armies":(##class(%DynamicArray).%New()),"ready":{"human":false,"ai":false}}
    set battleId = battle.%Id()
    &sql(DECLARE DeploymentArmyCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.Army WHERE Battle = :battleId ORDER BY Side DESC)
    &sql(OPEN DeploymentArmyCursor)
    for {
        &sql(FETCH DeploymentArmyCursor INTO :armyId)
        quit:(SQLCODE'=0)
        set army = ##class(BronzeWars.Model.Army).%OpenId(armyId)
        set hide = (army.Side = "AI")
        do value.armies.%Push(..Army(army, hide))
        do value.ready.%Set($zconvert(army.Side, "L"), ##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(army))
    }
    &sql(CLOSE DeploymentArmyCursor)
    return value
}

ClassMethod Timestamp(value As %TimeStamp) As %String
{
    return $extract(value, 1, 10) _ "T" _ $extract(value, 12, 19) _ "Z"
}

}
