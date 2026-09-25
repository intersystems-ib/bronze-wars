Class BronzeWars.Tests.ModelTest Extends %UnitTest.TestCase
{

Method Test01SeedContainsExpectedUnits()
{
    set sc = ##class(BronzeWars.Data.Seed).Run()
    do $$$AssertStatusOK(sc, "The seed completes successfully")

    &sql(SELECT COUNT(*) INTO :unitCount FROM BronzeWars_Model.UnitType WHERE Active = 1)
    do $$$AssertEquals(unitCount, 8, "Exactly eight active master unit types exist")

    do ..AssertUnit("LIGHT_INFANTRY", "Infantería ligera", 100, 2, 4, 2, 2, 5, "Proyectiles ligeros")
    do ..AssertUnit("HEAVY_INFANTRY", "Infantería pesada", 100, 1, 7, 9, 1, 8, "Cuerpo a cuerpo")
    do ..AssertUnit("MERCENARIES", "Mercenarios", 100, 2, 6, 6, 1, 7, "Cuerpo a cuerpo")
    set mercenaries = ##class(BronzeWars.Model.UnitType).CodeIndexOpen("MERCENARIES")
    do $$$AssertEquals(mercenaries.GrainCost, 8, "Mercenaries cost the infantry average plus one")
    do ..AssertUnit("SPEARMEN", "Lanceros", 100, 1, 6, 5, 1, 7, "Cuerpo a cuerpo")
    do ..AssertUnit("LIGHT_CAVALRY", "Caballería ligera", 60, 3, 5, 3, 2, 7, "Jabalinas")
    do ..AssertUnit("HEAVY_CAVALRY", "Caballería pesada", 50, 2, 9, 8, 1, 10, "Cuerpo a cuerpo")
    do ..AssertUnit("CHARIOTS", "Carros", 20, 3, 5, 3, 5, 5, "Flechas")
    do ..AssertUnit("ARCHERS", "Arqueros", 80, 2, 4, 2, 6, 4, "Flechas")
    do ..AssertProfile("CHARIOTS", "EGYPTIAN", 3, 5, 3)
    do ..AssertProfile("CHARIOTS", "ASSYRIAN", 3, 8, 7)
    do ..AssertProfile("MERCENARIES", "EGYPTIAN", 2, 6, 6)
    do ..AssertProfile("MERCENARIES", "ASSYRIAN", 2, 6, 6)
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
    do $$$AssertEquals(unit.CurrentStrength, 60, "A new battle unit copies its type's initial strength")
    do $$$AssertEquals(unit.Morale, 100, "A new battle unit starts with full morale")
    do $$$AssertEquals(unit.MovementSpent, 0, "A new battle unit has spent no movement")
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

Method Test09FormationMoraleScale()
{
    do $$$AssertEquals(##class(BronzeWars.Rules.FormationMorale).MoraleForNeighbors(0), 70, "An isolated infantry unit starts with 70 morale")
    do $$$AssertEquals(##class(BronzeWars.Rules.FormationMorale).MoraleForNeighbors(1), 80, "An infantry unit with one neighbor starts with 80 morale")
    do $$$AssertEquals(##class(BronzeWars.Rules.FormationMorale).MoraleForNeighbors(2), 90, "An infantry unit with two neighbors starts with 90 morale")
    do $$$AssertTrue(##class(BronzeWars.Rules.FormationMorale).IsSupportedUnitCode("SPEARMEN"), "Spearmen use formation morale")
    do $$$AssertTrue(##class(BronzeWars.Rules.FormationMorale).IsSupportedUnitCode("LIGHT_INFANTRY"), "Light infantry uses formation morale")
    do $$$AssertNotTrue(##class(BronzeWars.Rules.FormationMorale).IsSupportedUnitCode("LIGHT_CAVALRY"), "Cavalry keeps its initial morale")
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
    set sc = ##class(BronzeWars.AI.MovementRecommendationGenerator).Generate(context, .recommendations)
    do $$$AssertStatusOK(sc, "The AI Hub tool can calculate offensive, neutral, and defensive recommendations")
    do $$$AssertEquals(recommendations.%Size(), context.aiUnits.%Size(), "Every AI unit receives three recommendations")
    set choices = ##class(%DynamicArray).%New()
    for index = 0:1:(recommendations.%Size() - 1) {
        set recommendation = recommendations.%Get(index)
        do $$$AssertTrue(recommendation.%IsDefined("O") && recommendation.%IsDefined("N") && recommendation.%IsDefined("D"), "A unit recommendation exposes O, N, and D")
        set choice = ##class(%DynamicArray).%New()
        do choice.%Push(+(recommendation.unitId)), choice.%Push("O"), choices.%Push(choice)
    }
    set choiceAnswer = {"choices":(choices)}
    set sc = ##class(BronzeWars.AI.MovementCommander).ParseChoices(choiceAnswer.%ToJSON(), context, .chosenMovements, .choiceReasoning)
    do $$$AssertStatusOK(sc, "Compact AI Hub choices resolve to a valid complete movement plan")
    do $$$AssertEquals(chosenMovements.%Size(), context.aiUnits.%Size(), "Compact choices retain every AI unit")
    set movementToolSet = ##class(BronzeWars.AI.ToolSets.Movement).%New(), toolManifest = movementToolSet.%Discover().%ToJSON()
    do $$$AssertTrue($find(toolManifest, "BronzeWars.AI.ToolSets.Movement") > 0, "AI Hub identifies the packaged BronzeWars movement toolset as provider")
    do $$$AssertTrue($find(toolManifest, "RecommendMovementOptions") > 0, "The toolset publishes the BronzeWars movement recommendation tool")
    do $$$AssertTrue($find(toolManifest, "SubmitMovementChoices") > 0, "The toolset publishes the compact movement submission tool")
    set nimProvider = ##class(BronzeWars.AI.Agent.Movement).CreateProvider()
    do $$$AssertEquals(nimProvider.Name, "nim", "The movement agent uses the native AI Hub NIM provider")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#BaseURL, "http://llama:8000/v1", "The NIM provider targets the local llama service")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#APIKEY, "not-needed", "The local NIM provider does not require credentials")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#MODEL, "llama-3.1-8b-instruct", "The agent uses the model alias exposed by llama.cpp")
    do $$$AssertEquals(##class(BronzeWars.AI.Agent.Movement).#MaxTokens, 400, "The agent limits LLM responses to 400 tokens")
    do $$$AssertTrue(+##class(BronzeWars.AI.Agent.Movement).#TopP = 0.9, "The agent uses the configured nucleus sampling value")
    set configuredAgent = ##class(BronzeWars.AI.Agent.Movement).%New(nimProvider)
    set configuredAgent.Model = ##class(BronzeWars.AI.Agent.Movement).#MODEL
    set sc = configuredAgent.%Init()
    do $$$AssertStatusOK(sc, "The AI Hub agent initializes from the NIM provider")
    set sc = configuredAgent.UseToolSet("BronzeWars.AI.ToolSets.Movement")
    do $$$AssertStatusOK(sc, "The movement toolset is registered explicitly with UseToolSet")
    set auditCallId = "MODEL_TEST_" _ $job _ "_" _ $piece($horolog, ",", 2)
    set auditCall = {"id":(auditCallId),"name":"RecommendMovementOptions","arguments":{"battleId":"MODEL_TEST"}}
    set auditResult = {"tool_name":"RecommendMovementOptions","result_json":"{}","display_text":""}
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
    do $$$AssertEquals(auditLog.ToolName, "RecommendMovementOptions", "The audit stores the executed tool name")
    do $$$AssertTrue(auditLog.Success, "The audit stores the successful status")
    do $$$AssertEquals(auditLog.DurationMs, 12, "The audit stores tool duration")
    set sc = ##class(BronzeWars.AI.Audit.ToolExecution).%DeleteId(auditId)
    do $$$AssertStatusOK(sc, "The test audit record is removed")
    do ##class(BronzeWars.AI.MovementSubmission).Clear("MODEL_TEST")
    set compactChoices = ""
    for index = 0:1:(choices.%Size() - 1) {
        set choice = choices.%Get(index)
        set compactChoices = compactChoices _ $select(compactChoices'="":",", 1:"") _ choice.%Get(0) _ ":" _ choice.%Get(1)
    }
    set submission = ##class(BronzeWars.AI.Tools.Movement).SubmitMovementChoices("MODEL_TEST", compactChoices)
    do $$$AssertTrue(submission.accepted, "The tool accepts choices in the compact scalar format published by the toolset")
    set sc = ##class(BronzeWars.AI.MovementSubmission).Get("MODEL_TEST", .submittedChoices)
    do $$$AssertStatusOK(sc, "The AI Hub agent can recover submitted movement choices")
    do $$$AssertEquals(submittedChoices.%Size(), choices.%Size(), "The submission retains every compact choice")
    do ##class(BronzeWars.AI.MovementSubmission).Clear("MODEL_TEST")
    kill destination
    for index = 0:1:(movements.%Size() - 1) {
        set movement = movements.%Get(index), destination(movement.unitId) = movement.x _ "," _ movement.y
    }
    do $$$AssertEquals(destination(300), "0,4", "Light infantry advances toward projectile range")
    do $$$AssertEquals(destination(200), "0,2", "The left edge of the infantry line advances")
    do $$$AssertEquals(destination(210), "10,2", "The right edge advances with the line")
    do $$$AssertEquals(destination(301), "9,0", "Heavy cavalry moves toward the nearest human flank")
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
        set composition = ##class(BronzeWars.AI.Commanders.Strategy).FallbackComposition(type, 48, target)
        set sc = ##class(BronzeWars.Rules.ArmyBudget).ValidateComposition(composition, 48, .grain, .units)
        do $$$AssertStatusOK(sc, type _ " fallback is a valid 100-grain army")
        do $$$AssertEquals(grain, 100, type _ " fallback spends all grain")
        set sc = ##class(BronzeWars.AI.Commanders.Strategy).ValidateComposition(type, composition)
        do $$$AssertStatusOK(sc, type _ " fallback reflects its commander priorities")
        set lineUnits = 0
        for compositionIndex = 0:1:(composition.%Size() - 1) {
            set selection = composition.%Get(compositionIndex)
            if ##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(selection.code) set lineUnits = lineUnits + selection.quantity
        }
        do $$$AssertTrue(lineUnits >= target, type _ " fallback supports its required main line")
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
