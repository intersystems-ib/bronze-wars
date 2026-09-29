Class BronzeWars.Tests.ModelTest Extends %UnitTest.TestCase
{

Method Test01SeedContainsExpectedUnits()
{
    set sc = ##class(BronzeWars.Data.Seed).Run()
    do $$$AssertStatusOK(sc, "The seed completes successfully")

    &sql(SELECT COUNT(*) INTO :unitCount FROM BronzeWars_Model.UnitType WHERE Active = 1)
    do $$$AssertEquals(unitCount, 8, "Exactly eight active master unit types exist")

    do ..AssertUnit("LIGHT_INFANTRY", "Infantería ligera", 60, 2, 4, 2, 2, 5, "Proyectiles ligeros")
    do ..AssertUnit("HEAVY_INFANTRY", "Infantería pesada", 100, 1, 7, 9, 1, 8, "Cuerpo a cuerpo")
    do ..AssertUnit("MERCENARIES", "Mercenarios", 100, 2, 6, 6, 1, 7, "Cuerpo a cuerpo")
    set mercenaries = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("MERCENARIES")
    do $$$AssertEquals(mercenaries.GrainCost, 8, "Mercenaries cost the infantry average plus one")
    do ..AssertUnit("SPEARMEN", "Lanceros", 100, 1, 5, 6, 1, 7, "Cuerpo a cuerpo")
    do ..AssertUnit("LIGHT_CAVALRY", "Caballería ligera", 30, 3, 5, 3, 2, 9, "Jabalinas")
    do ..AssertUnit("HEAVY_CAVALRY", "Caballería pesada", 25, 2, 9, 8, 1, 10, "Cuerpo a cuerpo")
    do ..AssertUnit("CHARIOTS", "Carros", 20, 3, 5, 3, 5, 10, "Flechas")
    do ..AssertUnit("ARCHERS", "Arqueros", 80, 2, 4, 2, 6, 8, "Flechas")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitType).CodeIndexOpen("ARCHERS").InitialProjectiles, 20, "Archers start with twenty projectiles")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitType).CodeIndexOpen("CHARIOTS").InitialProjectiles, 10, "Chariots start with ten projectiles")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_CAVALRY").InitialProjectiles, 5, "Light cavalry starts with five projectiles")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_INFANTRY").InitialProjectiles, 10, "Light infantry starts with ten projectiles")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_INFANTRY").InitialProjectiles, 0, "Melee units start without projectiles")
    do ..AssertProfile("LIGHT_INFANTRY", "EGYPTIAN", 2, 4, 2, 6)
    do ..AssertProfile("LIGHT_INFANTRY", "ASSYRIAN", 2, 3, 2, 4)
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_INFANTRY").%Id(), "EGYPTIAN").InitialStrength, 60, "Egyptian light infantry uses the reduced strength")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_INFANTRY").%Id(), "ASSYRIAN").InitialStrength, 60, "Assyrian light infantry uses the reduced strength")
    do ..AssertProfile("HEAVY_INFANTRY", "EGYPTIAN", 1, 6, 8, 8)
    do ..AssertProfile("HEAVY_INFANTRY", "ASSYRIAN", 1, 8, 10, 10)
    do ..AssertProfile("SPEARMEN", "EGYPTIAN", 1, 5, 6, 6)
    do ..AssertProfile("SPEARMEN", "ASSYRIAN", 1, 5, 6, 6)
    do ..AssertProfile("HEAVY_CAVALRY", "EGYPTIAN", 2, 8, 7, 23)
    do ..AssertProfile("HEAVY_CAVALRY", "ASSYRIAN", 2, 10, 9, 26)
    do ..AssertProfile("CHARIOTS", "EGYPTIAN", 3, 5, 3, 22)
    do ..AssertProfile("CHARIOTS", "ASSYRIAN", 3, 6, 4, 25)
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("CHARIOTS").%Id(), "EGYPTIAN").Damage, 10, "Egyptian chariot projectile damage is doubled")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("CHARIOTS").%Id(), "ASSYRIAN").Damage, 18, "Assyrian chariot projectile damage is doubled")
    do ..AssertProfile("MERCENARIES", "EGYPTIAN", 2, 6, 6, 8)
    do ..AssertProfile("MERCENARIES", "ASSYRIAN", 2, 6, 6, 8)
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_CAVALRY").%Id(), "EGYPTIAN").InitialStrength, 30, "Egyptian light cavalry uses the reduced strength")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_CAVALRY").%Id(), "EGYPTIAN").Damage, 9, "Egyptian light cavalry uses the reduced damage")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_CAVALRY").%Id(), "ASSYRIAN").Damage, 9, "Assyrian light cavalry uses the reduced damage")
    do $$$AssertEquals(##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_CAVALRY").%Id(), "ASSYRIAN").InitialStrength, 25, "Assyrian heavy cavalry uses the reduced strength")
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
    do $$$AssertEquals(unitCount, 8, "Rerunning the seed does not duplicate active unit types")
    do $$$AssertEquals(profileCount, 16, "Rerunning the seed does not duplicate faction profiles")
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
    do $$$AssertEquals(unit.CurrentStrength, 30, "A new battle unit copies its type's initial strength")
    do $$$AssertEquals(unit.CurrentProjectiles, 5, "A new battle unit copies its type's initial projectiles")
    do $$$AssertEquals(unit.Morale, 100, "A new battle unit starts with full morale")
    do $$$AssertEquals(unit.MovementSpent, 0, "A new battle unit has spent no movement")
    do $$$AssertEquals(unit.HasMoved, 0, "A new battle unit has not moved")
    do $$$AssertEquals(unit.HasAttacked, 0, "A new battle unit has not attacked")
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
    set serializedSpearmen = ##class(BronzeWars.API.Serializer).UnitType(spearmen)
    do $$$AssertTrue(serializedSpearmen.attackModifiers.%Size() > 0, "Serialized unit types expose their matchup modifiers to the battle UI")
}

Method Test10FormationFallbackCoversFrontage()
{
    set composition = ##class(BronzeWars.Rules.ArmyBudget).FormationFallback(48, 10)
    set sc = ##class(BronzeWars.Rules.ArmyBudget).ValidateComposition(composition, 48, .grain, .units)
    do $$$AssertStatusOK(sc, "The formation fallback is a valid 100-grain army")
    set lineUnits = 0
    for index = 0:1:(composition.%Size() - 1) {
        set selection = composition.%Get(index)
        if ##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(selection.code) set lineUnits = lineUnits + selection.quantity
    }
    do $$$AssertTrue(lineUnits >= 10, "The fallback contains enough troops for the requested continuous front")

    set context = {"board":{"width":16,"height":12},"humanFormation":{"minX":0,"maxX":9,"frontage":10},"formationDoctrine":{"mainLineTarget":10,"mainLineRow":1},"units":(##class(%DynamicArray).%New())}
    set unitId = 1
    for index = 0:1:(composition.%Size() - 1) {
        set selection = composition.%Get(index)
        for number = 1:1:selection.quantity {
            do context.units.%Push({"unitId":(unitId),"code":(selection.code),"name":(selection.code)})
            set unitId = unitId + 1
        }
    }
    set sc = ##class(BronzeWars.AI.DeterministicDeploymentGenerator).GenerateFromContext(context, .placements)
    do $$$AssertStatusOK(sc, "The fallback deployment fits entirely inside the board")
    set answer = {"placements":(placements),"reasoning":"Test formation"}
    set sc = ##class(BronzeWars.AI.DeploymentCommander).ParseAndValidate(answer.%ToJSON(), context, .validated, .reasoning)
    do $$$AssertStatusOK(sc, "The fallback deployment satisfies the same cohesion rules as an LLM plan")
    set compactPlacements = ##class(%DynamicArray).%New()
    for placementIndex = 0:1:(placements.%Size() - 1) {
        set placement = placements.%Get(placementIndex), compactPlacement = ##class(%DynamicArray).%New()
        do compactPlacement.%Push(+(placement.unitId))
        do compactPlacement.%Push(placement.x)
        do compactPlacement.%Push(placement.y)
        do compactPlacements.%Push(compactPlacement)
    }
    set compactAnswer = {"placements":(compactPlacements)}
    set sc = ##class(BronzeWars.AI.DeploymentCommander).ParseAndValidate(compactAnswer.%ToJSON(), context, .validated, .reasoning)
    do $$$AssertStatusOK(sc, "The compact LLM deployment format passes the same validation")
    set sc = ##class(BronzeWars.AI.DeploymentCommander).ParseAndValidate(compactPlacements.%ToJSON(), context, .validated, .reasoning)
    do $$$AssertStatusOK(sc, "A bare compact placement array returned by the AI agent passes validation")
}

Method Test11DeterministicAIMovementDoctrine()
{
    set context = {"board":{"width":16,"height":12},"humanFormation":{"minX":0,"maxX":9},"humanUnits":(##class(%DynamicArray).%New()),"aiUnits":(##class(%DynamicArray).%New())}
    for x = 0:1:9 do context.humanUnits.%Push({"unitId":(100+x),"code":"HEAVY_INFANTRY","x":(x),"y":9,"remainingMovement":1,"attackRange":1,"morale":90})
    for x = 0:1:10 do context.aiUnits.%Push({"unitId":(200+x),"code":"SPEARMEN","x":(x),"y":1,"remainingMovement":1,"attackRange":1,"morale":90})
    do context.aiUnits.%Push({"unitId":300,"code":"LIGHT_INFANTRY","x":0,"y":2,"remainingMovement":2,"attackRange":2,"morale":70})
    do context.aiUnits.%Push({"unitId":301,"code":"HEAVY_CAVALRY","x":10,"y":0,"remainingMovement":2,"attackRange":1,"morale":100})

    set sc = ##class(BronzeWars.AI.DeterministicMovementGenerator).Generate(context, .movements)
    do $$$AssertStatusOK(sc, "The deterministic commander produces an AI movement plan")
    set answer = {"movements":(movements),"reasoning":"Test tactics"}
    set sc = ##class(BronzeWars.AI.MovementCommander).ParseAndValidate(answer.%ToJSON(), context, .validated, .reasoning)
    do $$$AssertStatusOK(sc, "The deterministic plan satisfies movement and cohesion validation")
    set nimProvider = ##class(BronzeWars.AI.Agent.Movement).CreateProvider()
    do $$$AssertEquals(nimProvider.Name, "nim", "The movement agent uses the native AI Hub NIM provider")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#BaseURL, "http://llama:8000/v1", "The NIM provider targets the local llama service")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#APIKEY, "not-needed", "The local NIM provider does not require credentials")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#MODEL, "llama-3.1-8b-instruct", "The agent uses the model alias exposed by llama.cpp")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#MaxTokens, 400, "The agent limits LLM responses to 400 tokens")
    do $$$AssertTrue(+##class(BronzeWars.AI.Agent.Movement).#TopP = 0.9, "The agent uses the configured nucleus sampling value")
    set auditCallId = "MODEL_TEST_" _ $job _ "_" _ $piece($horolog, ",", 2)
    set auditCall = {"id":(auditCallId),"name":"GetBattleSituation","arguments":{"battleId":"MODEL_TEST"}}
    set auditResult = {"tool_name":"GetBattleSituation","result_json":"{}","display_text":""}
    set auditPolicy = ##class(BronzeWars.AI.Policies.ToolAudit).%New()
    set sc = auditPolicy.%LogExecution(auditCall, {"domain":"movement"}, auditResult, 12, $$$OK)
    do $$$AssertStatusOK(sc, "The AI audit policy persists a successful tool execution")
    set auditStatement = ##class(%SQL.Statement).%New()
    set sc = auditStatement.%Prepare("SELECT TOP 1 ID FROM BronzeWars_AI_Audit.ToolExecution WHERE CallId = ? ORDER BY ID DESC")
    do $$$AssertStatusOK(sc, "The audit lookup query can be prepared")
    set auditResultSet = auditStatement.%Execute(auditCallId), auditFound = auditResultSet.%Next()
    do $$$AssertTrue(auditFound, "The audited tool call can be found by its call identifier")
    if auditFound set auditId = auditResultSet.%Get("ID")
    set auditLog = ##class(BronzeWars.AI.Audit.ToolExecution).%OpenId(auditId)
    do $$$AssertEquals(auditLog.ToolName, "GetBattleSituation", "The audit stores the executed tool name")
    do $$$AssertTrue(auditLog.Success, "The audit stores the successful status")
    do $$$AssertEquals(auditLog.DurationMs, 12, "The audit stores tool duration")
    set sc = ##class(BronzeWars.AI.Audit.ToolExecution).%DeleteId(auditId)
    do $$$AssertStatusOK(sc, "The test audit record is removed")
    kill destination
    for index = 0:1:(movements.%Size() - 1) {
        set movement = movements.%Get(index), destination(movement.unitId) = movement.x _ "," _ movement.y
    }
    do $$$AssertEquals(destination(300), "0,4", "Light infantry advances toward projectile range")
    do $$$AssertEquals(destination(200), "0,2", "The left edge of the infantry line advances")
    do $$$AssertEquals(destination(210), "10,2", "The right edge advances with the line")
    do $$$AssertEquals(destination(301), "9,0", "Heavy cavalry moves toward the nearest human flank")

    set context.commanderType = "DEFENSIVE", context.round = 2
    set sc = ##class(BronzeWars.AI.DeterministicMovementGenerator).Generate(context, .defensiveMovements)
    do $$$AssertStatusOK(sc, "A defensive commander can plan an even-numbered round")
    set movedCount = 0
    for index = 0:1:(defensiveMovements.%Size() - 1) {
        set movement = defensiveMovements.%Get(index)
        for unitIndex = 0:1:(context.aiUnits.%Size() - 1) {
            set originalUnit = context.aiUnits.%Get(unitIndex)
            if originalUnit.unitId = movement.unitId, ((originalUnit.x '= movement.x) || (originalUnit.y '= movement.y)) set movedCount = movedCount + 1
        }
    }
    do $$$AssertTrue(movedCount > 0, "A defensive commander advances instead of holding every even-numbered round")

    set decision = "{""strategy"":""ADVANCE"",""reasoning"":""The battle is favorable""}"
    set sc = ##class(BronzeWars.AI.MovementCommander).ParseDecision(decision, "ADVANCE", .strategy, .decisionReasoning)
    do $$$AssertStatusOK(sc, "A movement strategy matching the tool result is accepted")
    do $$$AssertEquals(strategy, "ADVANCE", "The validated movement strategy is retained")
    set sc = ##class(BronzeWars.AI.MovementCommander).ParseDecision(decision, "REGROUP", .strategy, .decisionReasoning)
    do $$$AssertStatusNotOK(sc, "A movement strategy contradicting the tool result is rejected")

    set advanceContext = {"board":{"width":12,"height":12},"humanUnits":(##class(%DynamicArray).%New()),"aiUnits":(##class(%DynamicArray).%New())}
    do advanceContext.humanUnits.%Push({"unitId":900,"x":0,"y":10})
    do advanceContext.aiUnits.%Push({"unitId":901,"code":"SPEARMEN","x":0,"y":1,"remainingMovement":1})
    do advanceContext.aiUnits.%Push({"unitId":902,"code":"LIGHT_CAVALRY","x":5,"y":2,"remainingMovement":3})
    set sc = ##class(BronzeWars.AI.DeterministicMovementGenerator).Generate(advanceContext, .advanceMovements, "ADVANCE")
    do $$$AssertStatusOK(sc, "The favorable battle strategy produces a general advance")
    do $$$AssertEquals(advanceMovements.%Get(0).y, 3, "The front unit advances one cell")
    do $$$AssertEquals(advanceMovements.%Get(1).y, 2, "The rear unit advances one cell")

    set regroupContext = {"board":{"width":12,"height":12},"humanUnits":(##class(%DynamicArray).%New()),"aiUnits":(##class(%DynamicArray).%New())}
    do regroupContext.aiUnits.%Push({"unitId":911,"code":"SPEARMEN","x":0,"y":1,"remainingMovement":1})
    do regroupContext.aiUnits.%Push({"unitId":912,"code":"LIGHT_CAVALRY","x":10,"y":1,"remainingMovement":3})
    set sc = ##class(BronzeWars.AI.DeterministicMovementGenerator).Generate(regroupContext, .regroupMovements, "REGROUP")
    do $$$AssertStatusOK(sc, "The unfavorable battle strategy produces a regrouping movement")
    do $$$AssertEquals(regroupMovements.%Get(0).x, 1, "The left unit moves toward the army center")
    do $$$AssertEquals(regroupMovements.%Get(1).x, 7, "The right unit uses its movement to approach the army center")
}

Method Test12CommanderArchetypes()
{
    set types = $listbuild("DEFENSIVE", "AGGRESSIVE", "SKIRMISHER", "FLANKER", "BALANCED")
    for typeIndex = 1:1:$listlength(types) {
        set type = $listget(types, typeIndex)
        do $$$AssertTrue(##class(BronzeWars.AI.Commanders.Strategy).IsValid(type), type _ " is a valid commander archetype")
        do $$$AssertNotEquals(##class(BronzeWars.AI.Commanders.Strategy).Label(type), "", type _ " has a display name")
        do $$$AssertNotEquals(##class(BronzeWars.AI.Commanders.Strategy).Doctrine(type), "", type _ " has composition doctrine")
        do $$$AssertNotEquals(##class(BronzeWars.AI.Commanders.Strategy).MovementInstruction(type), "", type _ " has movement doctrine")
        set target = ##class(BronzeWars.AI.Commanders.Strategy).MainLineTarget(type, 10, 16)
        for faction = "EGYPTIAN","ASSYRIAN" {
            set composition = ##class(BronzeWars.AI.Commanders.Strategy).FallbackComposition(type, 48, target, faction)
            set sc = ##class(BronzeWars.Rules.ArmyBudget).ValidateComposition(composition, 48, .grain, .units, faction)
            do $$$AssertStatusOK(sc, type _ "/" _ faction _ " fallback is a valid 100-grain army")
            do $$$AssertEquals(grain, 100, type _ "/" _ faction _ " fallback spends all grain")
            do $$$AssertTrue(units <= ##class(BronzeWars.Rules.ArmyBudget).#AIMaxUnits, type _ "/" _ faction _ " fallback never exceeds fourteen units")
            set sc = ##class(BronzeWars.AI.Commanders.Strategy).ValidateComposition(type, composition)
            do $$$AssertStatusOK(sc, type _ "/" _ faction _ " fallback reflects its commander priorities")
            set lineUnits = 0, largestQuantity = 0
            for compositionIndex = 0:1:(composition.%Size() - 1) {
                set selection = composition.%Get(compositionIndex)
                if ##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(selection.code) set lineUnits = lineUnits + selection.quantity
                if selection.quantity > largestQuantity set largestQuantity = selection.quantity
                if type = "SKIRMISHER", selection.code = "ARCHERS" set hasSkirmisherArchers = 1
                if type = "SKIRMISHER", selection.code = "LIGHT_INFANTRY" set hasSkirmisherInfantry = 1
                if type = "SKIRMISHER", selection.code = "LIGHT_CAVALRY" set hasSkirmisherCavalry = 1
            }
            do $$$AssertTrue(composition.%Size() >= 3, type _ "/" _ faction _ " fallback uses at least three troop types")
            do $$$AssertTrue((largestQuantity * 2) <= (units + 1), type _ "/" _ faction _ " fallback is not dominated by one troop type")
            do $$$AssertTrue(lineUnits >= target, type _ "/" _ faction _ " fallback supports its required main line")
            if type = "SKIRMISHER" {
                do $$$AssertTrue($get(hasSkirmisherArchers), faction _ " skirmisher includes archers")
                do $$$AssertTrue($get(hasSkirmisherInfantry), faction _ " skirmisher includes light infantry")
                do $$$AssertTrue($get(hasSkirmisherCavalry), faction _ " skirmisher includes light cavalry")
            }
            kill hasSkirmisherArchers, hasSkirmisherInfantry, hasSkirmisherCavalry
        }
    }
    for randomIndex = 1:1:20 do $$$AssertTrue(##class(BronzeWars.AI.Commanders.Strategy).IsValid(##class(BronzeWars.AI.Commanders.Strategy).RandomType()), "Random selection always returns a known archetype")

    set compactContext = {"commanderType":"BALANCED","grainBudget":100,"board":{"width":16},"formationDoctrine":{"mainLineTarget":8},"unitTypes":(##class(%DynamicArray).%New())}
    do compactContext.unitTypes.%Push({"code":"SPEARMEN","grainCost":6})
    do compactContext.unitTypes.%Push({"code":"HEAVY_INFANTRY","grainCost":9})
    do compactContext.unitTypes.%Push({"code":"LIGHT_CAVALRY","grainCost":20})
    set compactContent = "{""composition"":[[""SPEARMEN"",4],[""HEAVY_INFANTRY"",4],[""LIGHT_CAVALRY"",2]]}"
    set sc = ##class(BronzeWars.AI.ArmyCommander).ParseAndValidate(compactContent, compactContext, .compactComposition, .compactReasoning)
    do $$$AssertStatusOK(sc, "The compact LLM army format passes strategic and budget validation")
    do $$$AssertEquals(compactComposition.%Size(), 3, "The compact army response retains every selected type")

    set oversizedContext = {"commanderType":"BALANCED","grainBudget":100,"board":{"width":16},"formationDoctrine":{"mainLineTarget":8},"unitTypes":(##class(%DynamicArray).%New())}
    do oversizedContext.unitTypes.%Push({"code":"SPEARMEN","grainCost":6})
    do oversizedContext.unitTypes.%Push({"code":"ARCHERS","grainCost":7})
    do oversizedContext.unitTypes.%Push({"code":"MERCENARIES","grainCost":8})
    set oversizedContent = "{""composition"":[[""SPEARMEN"",8],[""ARCHERS"",4],[""MERCENARIES"",3]]}"
    set sc = ##class(BronzeWars.AI.ArmyCommander).ParseAndValidate(oversizedContent, oversizedContext, .oversizedComposition, .oversizedReasoning)
    do $$$AssertStatusNotOK(sc, "A valid-budget LLM response with fifteen units is rejected")

    set incompleteSkirmishers = [{"code":"LIGHT_INFANTRY","quantity":5},{"code":"SPEARMEN","quantity":4},{"code":"ARCHERS","quantity":3}]
    set sc = ##class(BronzeWars.AI.Commanders.Strategy).ValidateComposition("SKIRMISHER", incompleteSkirmishers)
    do $$$AssertStatusNotOK(sc, "A skirmisher army without light cavalry is rejected")
}

Method Test13FlankingDeploymentUsesMobileExtremes()
{
    set context = {"commanderType":"FLANKER","commanderName":"Flanqueador","commanderDoctrine":"Test","board":{"width":16,"height":12},"humanFormation":{"minX":0,"maxX":9,"frontage":10},"formationDoctrine":{"mainLineTarget":8,"frontageTarget":11,"mainLineRow":1},"units":(##class(%DynamicArray).%New())}
    set composition = ##class(BronzeWars.AI.Commanders.Strategy).FallbackComposition("FLANKER", 48, 8), unitId = 1
    for compositionIndex = 0:1:(composition.%Size() - 1) {
        set selection = composition.%Get(compositionIndex)
        for quantityIndex = 1:1:selection.quantity {
            do context.units.%Push({"unitId":(unitId),"code":(selection.code),"name":(selection.code)})
            set unitId = unitId + 1
        }
    }
    set sc = ##class(BronzeWars.AI.DeterministicDeploymentGenerator).GenerateFromContext(context, .placements)
    do $$$AssertStatusOK(sc, "The flanking fallback can be deployed")
    set answer = {"placements":(placements),"reasoning":"Mobile units on both flanks"}
    set sc = ##class(BronzeWars.AI.DeploymentCommander).ParseAndValidate(answer.%ToJSON(), context, .validated, .reasoning)
    do $$$AssertStatusOK(sc, "The flanking fallback extends the enemy frontage with mobile units on both extremes")
    for placementIndex = 0:1:(placements.%Size() - 1) {
        set placement = placements.%Get(placementIndex), code = ""
        for unitIndex = 0:1:(context.units.%Size() - 1) {
            set deploymentUnit = context.units.%Get(unitIndex)
            if deploymentUnit.unitId = placement.unitId set code = deploymentUnit.code
        }
        if ##class(BronzeWars.AI.DeploymentCommander).IsForwardLineCode(code) do $$$AssertEquals(placement.y, 2, code _ " deploys on the line closest to the enemy")
        if ##class(BronzeWars.AI.DeterministicDeploymentGenerator).IsCavalryCode(code) do $$$AssertEquals(placement.y, 1, code _ " deploys on a flank of the second line")
    }

    set defensiveContext = {"commanderType":"DEFENSIVE","board":{"width":16,"height":12},"humanFormation":{"minX":3,"maxX":8,"frontage":6},"formationDoctrine":{"mainLineTarget":6,"frontageTarget":6,"mainLineRow":1},"units":(##class(%DynamicArray).%New())}
    for defensiveId = 1:1:8 do defensiveContext.units.%Push({"unitId":(defensiveId),"code":"SPEARMEN","name":"SPEARMEN"})
    set sc = ##class(BronzeWars.AI.DeterministicDeploymentGenerator).GenerateFromContext(defensiveContext, .defensivePlacements)
    do $$$AssertStatusOK(sc, "The defensive deployment leaves surplus line troops in reserve")
    set reserveCount = 0
    for placementIndex = 0:1:(defensivePlacements.%Size() - 1) {
        if defensivePlacements.%Get(placementIndex).y = 0 set reserveCount = reserveCount + 1
    }
    do $$$AssertEquals(reserveCount, 2, "Defensive surplus units use the third deployment line as reserve")

    set wideTarget = ##class(BronzeWars.AI.Commanders.Strategy).MainLineTarget("FLANKER", 16, 16)
    set wideComposition = ##class(BronzeWars.AI.Commanders.Strategy).FallbackComposition("FLANKER", 48, wideTarget)
    set sc = ##class(BronzeWars.Rules.ArmyBudget).ValidateComposition(wideComposition, 48, .wideGrain, .wideUnits)
    do $$$AssertStatusOK(sc, "The wide flanking fallback is a valid 100-grain army")
    do $$$AssertEquals(wideGrain, 100, "The wide flanking fallback spends all grain")
    set sc = ##class(BronzeWars.AI.Commanders.Strategy).ValidateComposition("FLANKER", wideComposition)
    do $$$AssertStatusOK(sc, "The wide flanking fallback retains mobile flank units and unit variety")
    set wideLineUnits = 0
    for compositionIndex = 0:1:(wideComposition.%Size() - 1) {
        set selection = wideComposition.%Get(compositionIndex)
        if ##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(selection.code) set wideLineUnits = wideLineUnits + selection.quantity
    }
    do $$$AssertTrue(wideLineUnits >= wideTarget, "The wide flanking fallback can form its required continuous line")
}

Method Test14MeleeCombatFormula()
{
    set context = {
        "attacker":{"strength":100,"morale":80,"attack":8,"defense":4,"damage":10},
        "defender":{"strength":100,"morale":100,"attack":6,"defense":8,"damage":6}
    }
    set result = ##class(BronzeWars.Rules.Combat).Resolve(context)
    do $$$AssertEquals(result.defenderCasualties, 4, "Attacker damage is reduced by defense and its lower morale")
    do $$$AssertEquals(result.attackerCasualties, 4, "Defender retaliation uses its capped morale factor")
    do $$$AssertEquals(result.attackerMoraleFactor, .8, "Attacker morale factor is the morale ratio")
    do $$$AssertEquals(result.defenderMoraleFactor, 1, "A favorable morale ratio is capped at one")

    set context.attacker.strength = 2, context.defender.strength = 3
    set result = ##class(BronzeWars.Rules.Combat).Resolve(context)
    do $$$AssertEquals(result.attackerCasualties, 2, "Attacker casualties cannot exceed its remaining strength")
    do $$$AssertEquals(result.defenderCasualties, 3, "Defender casualties cannot exceed its remaining strength")

    set context.attacker.strength = 100, context.defender.strength = 100
    set context.attacker.morale = 0, context.defender.morale = 100
    set result = ##class(BronzeWars.Rules.Combat).Resolve(context)
    do $$$AssertEquals(result.defenderCasualties, 0, "A unit with zero morale inflicts no casualties")
    do $$$AssertEquals(result.attackerMoraleFactor, 0, "Zero morale produces a zero morale factor")

    set rangedContext = {
        "type":"RANGED",
        "distance":4,
        "attacker":{"strength":80,"morale":100,"attack":4,"defense":2,"damage":8,"range":7,"projectiles":8},
        "defender":{"strength":100,"morale":100,"attack":7,"defense":10,"damage":8,"range":1,"projectiles":0}
    }
    set result = ##class(BronzeWars.Rules.Combat).Resolve(rangedContext)
    do $$$AssertEquals(result.distanceFactor, .75, "Ranged damage decreases linearly with distance")
    do $$$AssertEquals(result.defenseFactor, .5, "Ranged defense factor uses half the defense score")
    do $$$AssertEquals(result.defenderCasualties, 3, "Ranged casualties use damage, distance, and defense")
    do $$$AssertEquals(result.attackerCasualties, 0, "A ranged defender does not retaliate")

    set rangedContext.attacker.code = "ARCHERS", rangedContext.defender.code = "LIGHT_CAVALRY"
    set rangedContext.defender.defense = 3
    set result = ##class(BronzeWars.Rules.Combat).Resolve(rangedContext)
    do $$$AssertEquals(result.defenderDefenseModifier, 2, "Light cavalry gains two defense against projectiles")
    do $$$AssertEquals(result.defenderEffectiveDefense, 5, "Light cavalry projectile defense is applied to ranged combat")

    set cavalryContext = {
        "attacker":{"code":"HEAVY_CAVALRY","strength":25,"morale":100,"attack":9,"defense":8,"damage":10},
        "defender":{"code":"SPEARMEN","strength":100,"morale":100,"attack":5,"defense":6,"damage":7}
    }
    set result = ##class(BronzeWars.Rules.Combat).Resolve(cavalryContext)
    do $$$AssertEquals(result.defenderDefenseModifier, 2, "Spearmen gain two defense against cavalry")
    do $$$AssertEquals(result.defenderEffectiveDefense, 8, "Spearmen cavalry defense is applied to melee combat")

    set cavalryContext.attacker.code = "CHARIOTS"
    set result = ##class(BronzeWars.Rules.Combat).Resolve(cavalryContext)
    do $$$AssertEquals(result.defenderDefenseModifier, 2, "Spearmen also gain two defense against chariots")

    set modifierContext = {
        "attacker":{"code":"SPEARMEN","strength":100,"morale":100,"attack":5,"attackModifier":3,"defense":6,"damage":7},
        "defender":{"code":"HEAVY_CAVALRY","strength":25,"morale":100,"attack":9,"attackModifier":2,"defense":8,"damage":10}
    }
    set result = ##class(BronzeWars.Rules.Combat).Resolve(modifierContext)
    do $$$AssertEquals(result.attackerEffectiveAttack, 8, "The attacker matchup bonus is applied to melee attack")
    do $$$AssertEquals(result.defenderEffectiveAttack, 11, "The defender matchup bonus is applied to melee retaliation")
    do $$$AssertEquals(result.attackerAttackModifier, 3, "The attacker bonus is exposed in the combat result")

    set positionContext = {
        "attacker":{"side":"HUMAN","x":4,"y":4,"strength":100,"morale":100,"attack":5,"defense":5,"damage":5},
        "defender":{"side":"AI","x":5,"y":4,"strength":100,"morale":100,"attack":5,"defense":5,"damage":5}
    }
    set result = ##class(BronzeWars.Rules.Combat).Resolve(positionContext)
    do $$$AssertEquals(result.attackDirection, "FLANK", "An attack from the defender's row is a flank attack")
    do $$$AssertEquals(result.defenderPositionMoralePenalty, 10, "A flank attack applies ten points of morale penalty")
    set positionContext.attacker.x = 5, positionContext.attacker.y = 3
    set result = ##class(BronzeWars.Rules.Combat).Resolve(positionContext)
    do $$$AssertEquals(result.attackDirection, "REAR", "An AI unit attacked from the top is attacked from the rear")
    do $$$AssertEquals(result.defenderPositionMoralePenalty, 10, "A rear attack applies ten points of morale penalty")
    set positionContext.attacker.y = 5
    set result = ##class(BronzeWars.Rules.Combat).Resolve(positionContext)
    do $$$AssertEquals(result.attackDirection, "FRONT", "An AI unit attacked from below is attacked from the front")
    do $$$AssertEquals(result.defenderPositionMoralePenalty, 0, "A frontal attack does not apply a positional morale penalty")
}

Method Test14AMoraleLossIsProportionalToInitialStrength()
{
    set infantryType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("HEAVY_INFANTRY")
    set infantry = ##class(BronzeWars.Model.BattleUnit).%New(infantryType)
    do $$$AssertEquals(##class(BronzeWars.Rules.Morale).LossForCasualties(infantry, 1), 1, "One casualty costs one morale point in a 100-strength unit")

    set chariotType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("CHARIOTS")
    set chariotProfile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(chariotType.%Id(), "EGYPTIAN")
    set chariot = ##class(BronzeWars.Model.BattleUnit).%New(chariotType, chariotProfile)
    do $$$AssertEquals(##class(BronzeWars.Rules.Morale).LossForCasualties(chariot, 1), 5, "One casualty costs five morale points in a 20-strength unit")
    do $$$AssertEquals(##class(BronzeWars.Rules.Morale).AfterCasualties(chariot, 100, 3), 85, "Three chariot casualties reduce morale proportionally")

    set cavalryType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("LIGHT_CAVALRY")
    set cavalry = ##class(BronzeWars.Model.BattleUnit).%New(cavalryType)
    do $$$AssertEquals(##class(BronzeWars.Rules.Morale).LossForCasualties(cavalry, 3), 10, "Three casualties cost ten morale points in a 30-strength unit")
}

Method Test15BattleSituationTool()
{
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).DescribeMorale(80), "very high", "Morale 80 is very high")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).DescribeMorale(60), "high", "Morale 60 is high")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).DescribeMorale(40), "normal", "Morale 40 is normal")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).DescribeMorale(20), "low", "Morale 20 is low")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).DescribeMorale(19), "very low", "Morale below 20 is very low")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).Classify(49, 50), "BAD", "Low morale and at least fifty percent casualties are unfavorable")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).RecommendedStrategy(49, 50), "REGROUP", "An unfavorable battle recommends regrouping")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).Classify(51, 49), "GOOD", "High morale and fewer than fifty percent casualties are favorable")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).RecommendedStrategy(51, 49), "ADVANCE", "A favorable battle recommends a general advance")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).Classify(50, 49), "NEUTRAL", "A boundary value of fifty morale retains tactical behavior")
    do $$$AssertEquals(##class(BronzeWars.AI.Tools.BattleSituation).Classify(51, 50), "NEUTRAL", "Mixed indicators retain tactical behavior")

    set battle = ##class(BronzeWars.Model.Battle).%New()
    set battle.Name = "Battle situation tool test"
    set sc = battle.%Save()
    do $$$AssertStatusOK(sc, "The battle situation fixture can be saved")
    set battleId = battle.%Id()

    set army = ##class(BronzeWars.Model.Army).%New()
    set army.Battle = battle
    set army.Name = "AI situation test army"
    set army.Side = "AI"
    set army.Faction = "EGYPTIAN"
    set sc = army.%Save()
    do $$$AssertStatusOK(sc, "The AI army situation fixture can be saved")
    set armyId = army.%Id()

    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("SPEARMEN")
    set firstUnit = ##class(BronzeWars.Model.BattleUnit).%New(unitType)
    set firstUnit.Battle = battle, firstUnit.Army = army, firstUnit.Name = "Situation unit one"
    set firstUnit.CurrentStrength = 80, firstUnit.Morale = 80
    set sc = firstUnit.%Save()
    do $$$AssertStatusOK(sc, "The first situation unit can be saved")
    set firstUnitId = firstUnit.%Id()

    set secondUnit = ##class(BronzeWars.Model.BattleUnit).%New(unitType)
    set secondUnit.Battle = battle, secondUnit.Army = army, secondUnit.Name = "Situation unit two"
    set secondUnit.CurrentStrength = 60, secondUnit.Morale = 60
    set sc = secondUnit.%Save()
    do $$$AssertStatusOK(sc, "The second situation unit can be saved")
    set secondUnitId = secondUnit.%Id()

    set situation = ##class(BronzeWars.AI.Tools.BattleSituation).GetBattleSituation(battleId)
    do $$$AssertEquals(situation.averageMorale, 70, "The tool reports numeric average morale for threshold decisions")
    do $$$AssertEquals(situation.morale, "high", "The tool classifies the average active morale")
    do $$$AssertEquals(situation.casualtiesPercentage, 30, "The tool reports casualties against total initial strength")
    do $$$AssertEquals(situation.battleState, "GOOD", "The tool classifies a favorable battle")
    do $$$AssertEquals(situation.recommendedStrategy, "ADVANCE", "The tool recommends the strategy required by the thresholds")

    set situationToolSet = ##class(BronzeWars.AI.ToolSets.BattleSituation).%New()
    set toolManifest = situationToolSet.%Discover().%ToJSON()
    do $$$AssertTrue($find(toolManifest, "BronzeWars.AI.ToolSets.BattleSituation") > 0, "AI Hub identifies the battle situation toolset as provider")
    do $$$AssertTrue($find(toolManifest, "GetBattleSituation") > 0, "The toolset publishes the battle situation tool")

    set sc = ##class(BronzeWars.Model.BattleUnit).%DeleteId(firstUnitId)
    do $$$AssertStatusOK(sc, "The first situation unit is removed")
    set sc = ##class(BronzeWars.Model.BattleUnit).%DeleteId(secondUnitId)
    do $$$AssertStatusOK(sc, "The second situation unit is removed")
    set sc = ##class(BronzeWars.Model.Army).%DeleteId(armyId)
    do $$$AssertStatusOK(sc, "The situation army is removed")
    set sc = ##class(BronzeWars.Model.Battle).%DeleteId(battleId)
    do $$$AssertStatusOK(sc, "The situation battle is removed")
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
    set unitType.InitialProjectiles = 0
    set unitType.GrainCost = 1
    return unitType
}

Method AssertProfile(code As %String, faction As %String, speed As %Integer, attack As %Integer, defense As %Integer, grainCost As %Integer)
{
    set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(code)
    set profile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(unitType.%Id(), faction)
    do $$$AssertTrue($isobject(profile), code _ "/" _ faction _ " profile exists")
    if '$isobject(profile) quit
    do $$$AssertEquals(profile.Speed, speed, faction _ " speed matches")
    do $$$AssertEquals(profile.Attack, attack, faction _ " attack matches")
    do $$$AssertEquals(profile.Defense, defense, faction _ " defense matches")
    do $$$AssertEquals(profile.GrainCost, grainCost, faction _ " grain cost matches")
}
}
