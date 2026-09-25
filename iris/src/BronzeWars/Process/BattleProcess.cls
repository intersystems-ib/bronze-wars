Class BronzeWars.Process.BattleProcess Extends BronzeWars.Process.BaseProcess
{

Parameter ALLOWEDACTIONS = "CREATE_BATTLE,GET_BATTLE,START_BATTLE,MOVE_UNIT,NEXT_TURN";

Method OnRequest(request As BronzeWars.Message.Request, Output response As BronzeWars.Message.Response) As %Status
{
    if '..IsAllowed(request.Action) return ..SetError(.response, 500, "UNSUPPORTED_ACTION", "La operacion solicitada no esta configurada.")

    set payload = request.Payload()
    if request.Action = "CREATE_BATTLE" {
        if 'payload.%IsDefined("name") do payload.%Set("name", "Batalla BronzeWars")
        if payload.%IsDefined("name"), (payload.name = "") do payload.%Set("name", "Batalla BronzeWars")
        if 'payload.%IsDefined("boardWidth") do payload.%Set("boardWidth", 16)
        if 'payload.%IsDefined("boardHeight") do payload.%Set("boardHeight", 12)
        if 'payload.%IsDefined("faction") do payload.%Set("faction", "EGYPTIAN")
        set payload.faction = $zconvert(payload.faction, "U")
        if (payload.faction '= "EGYPTIAN") && (payload.faction '= "ASSYRIAN") return ..SetError(.response, 422, "INVALID_FACTION", "La faccion seleccionada no es valida.")
        if (payload.boardWidth < 1) ! (payload.boardHeight < 1) return ..SetError(.response, 422, "INVALID_BOARD_SIZE", "Las dimensiones del tablero deben ser positivas.")
        if (payload.boardWidth * 3) < 4 return ..SetError(.response, 422, "BOARD_TOO_NARROW", "La zona de despliegue debe admitir al menos cuatro unidades para consumir el presupuesto de la IA.")
        if payload.boardHeight < 6 return ..SetError(.response, 422, "BOARD_TOO_SHORT", "El tablero debe tener al menos seis filas.")
        if 'payload.%IsDefined("units") do payload.%Set("units", ##class(BronzeWars.Rules.ArmyBudget).DefaultComposition())
        if payload.%GetTypeOf("units") '= "array" return ..SetError(.response, 422, "INVALID_ARMY_COMPOSITION", "La composicion del ejercito debe ser una lista.")

        set normalized = ##class(%DynamicArray).%New(), grain = 0, unitCount = 0
        kill seen
        for index = 0:1:(payload.units.%Size() - 1) {
            set item = payload.units.%Get(index)
            if '$isobject(item) return ..SetError(.response, 422, "INVALID_ARMY_COMPOSITION", "Cada seleccion de unidad debe ser un objeto.")
            if 'item.%IsDefined("code") ! 'item.%IsDefined("quantity") return ..SetError(.response, 422, "INVALID_ARMY_COMPOSITION", "Cada seleccion requiere codigo y cantidad.")
            if (item.%GetTypeOf("code") '= "string") ! (item.%GetTypeOf("quantity") '= "number") return ..SetError(.response, 422, "INVALID_ARMY_COMPOSITION", "El codigo y la cantidad de cada unidad no son validos.")
            set code = $zconvert(item.code, "U"), quantity = item.quantity
            if (quantity < 0) ! (quantity '= (quantity \ 1)) return ..SetError(.response, 422, "INVALID_UNIT_QUANTITY", "Las cantidades de unidades deben ser enteros no negativos.")
            set cost = ##class(BronzeWars.Rules.ArmyBudget).GrainCost(code)
            if cost = 0 return ..SetError(.response, 422, "UNKNOWN_UNIT_TYPE", "La composicion contiene un tipo de unidad desconocido.")
            if $data(seen(code)) return ..SetError(.response, 422, "DUPLICATE_UNIT_TYPE", "Cada tipo de unidad debe aparecer una sola vez en la composicion.")
            set seen(code) = 1
            if quantity > 0 {
                do normalized.%Push({"code":(code),"quantity":(quantity)})
                set grain = grain + (cost * quantity), unitCount = unitCount + quantity
            }
        }
        if unitCount = 0 return ..SetError(.response, 422, "EMPTY_ARMY", "El ejercito debe incluir al menos una unidad.")
        if grain > ##class(BronzeWars.Rules.ArmyBudget).#TOTAL return ..SetError(.response, 422, "GRAIN_BUDGET_EXCEEDED", "La composicion supera las 100 unidades de grano disponibles.")
        if unitCount > (payload.boardWidth * 3) return ..SetError(.response, 422, "ARMY_TOO_LARGE", "El ejercito no cabe en la zona de despliegue.")
        do payload.%Set("units", normalized)
        set request.PayloadJSON = payload.%ToJSON()
    }

    if request.Action = "START_BATTLE" {
        lock +^BronzeWarsBattleLock(payload.battleId):5
        if '$test return ..SetError(.response, 409, "BATTLE_BUSY", "La batalla esta siendo modificada por otra peticion.")
        set sc = ..StartWithCommander(request, .response)
        lock -^BronzeWarsBattleLock(payload.battleId)
        return sc
    }
    if request.Action = "NEXT_TURN" {
        lock +^BronzeWarsBattleLock(payload.battleId):5
        if '$test return ..SetError(.response, 409, "BATTLE_BUSY", "La batalla esta siendo modificada por otra peticion.")
        set sc = ..AdvanceTurnWithCommander(request, .response)
        lock -^BronzeWarsBattleLock(payload.battleId)
        return sc
    }
    if request.Action = "MOVE_UNIT" {
        lock +^BronzeWarsBattleLock(payload.battleId):5
        if '$test return ..SetError(.response, 409, "BATTLE_BUSY", "La batalla esta siendo modificada por otra peticion.")
        set sc = ..SendToOperation(request, .response)
        lock -^BronzeWarsBattleLock(payload.battleId)
        return sc
    }
    return ..SendToOperation(request, .response)
}

Method AdvanceTurnWithCommander(request As BronzeWars.Message.Request, Output response As BronzeWars.Message.Response) As %Status [ Private ]
{
    set payload = request.Payload()
    set contextRequest = ##class(BronzeWars.Message.Request).%New()
    set contextRequest.Action = "PREPARE_AI_MOVEMENT"
    set contextRequest.PayloadJSON = {"battleId":(payload.battleId),"confirmIncomplete":(payload.confirmIncomplete)}.%ToJSON()
    set sc = ..SendRequestSync(..#OPERATION, contextRequest, .contextResponse)
    return:$SYSTEM.Status.IsError(sc) sc
    set contextResult = contextResponse.Result()
    if 'contextResult.ok {
        set response = contextResponse
        return $$$OK
    }
    set context = contextResult.data, source = "DETERMINISTIC_FALLBACK", reasoning = "Movimiento tactico de respaldo basado en cohesion, alcance y flancos."
    set sc = ##class(BronzeWars.AI.DeterministicMovementGenerator).Generate(context, .movements)
    if $SYSTEM.Status.IsError(sc) return ..SetError(.response, 500, "AI_MOVEMENT_FAILED", "No se ha podido generar el movimiento de la IA.")

    set llmRequest = ##class(BronzeWars.Message.Request).%New()
    set llmRequest.Action = "PLAN_AI_MOVEMENT"
    set llmRequest.PayloadJSON = {"battleId":(context.battleId),"goal":(##class(BronzeWars.AI.MovementCommander).BuildAgentGoal(context))}.%ToJSON()
    set llmStatus = ..SendRequestSync("LLM Operation", llmRequest, .llmResponse)
    if $SYSTEM.Status.IsOK(llmStatus), $isobject(llmResponse) {
        set llmResult = llmResponse.Result()
        if llmResult.ok {
            set validation = ##class(BronzeWars.AI.MovementCommander).ParseChoices(llmResult.data.content, context, .llmMovements, .llmReasoning)
            if $SYSTEM.Status.IsOK(validation) set movements = llmMovements, source = "AI_HUB_TOOL", reasoning = llmReasoning
            if $SYSTEM.Status.IsError(validation) $$$LOGWARNING("Invalid LLM movement response: " _ $SYSTEM.Status.GetErrorText(validation) _ " Content: " _ llmResult.data.content)
        }
    }
    do payload.%Set("aiMovements", movements)
    do payload.%Set("movementSource", source)
    do payload.%Set("movementReasoning", reasoning)
    set request.PayloadJSON = payload.%ToJSON()
    return ..SendToOperation(request, .response)
}

Method StartWithCommander(request As BronzeWars.Message.Request, Output response As BronzeWars.Message.Response) As %Status [ Private ]
{
    set payload = request.Payload()
    set contextRequest = ##class(BronzeWars.Message.Request).%New()
    set contextRequest.Action = "PREPARE_AI_DEPLOYMENT"
    set contextRequest.PayloadJSON = {"battleId":(payload.battleId)}.%ToJSON()
    set sc = ..SendRequestSync(..#OPERATION, contextRequest, .contextResponse)
    return:$SYSTEM.Status.IsError(sc) sc
    set contextResult = contextResponse.Result()
    if 'contextResult.ok {
        set response = contextResponse
        return $$$OK
    }
    set planningContext = contextResult.data

    set compositionSource = "DETERMINISTIC_FALLBACK", compositionReasoning = "Se ha elegido una composicion de respaldo acorde con el tipo de comandante y que consume las 100 medidas de grano."
    set targetLineLength = ##class(BronzeWars.AI.ArmyCommander).TargetLineLength(planningContext)
    set composition = ##class(BronzeWars.AI.Commanders.Strategy).FallbackComposition(planningContext.commanderType, planningContext.board.width * 3, targetLineLength)
    set armyRequest = ##class(BronzeWars.Message.Request).%New()
    set armyRequest.Action = "PLAN_AI_ARMY"
    set armyRequest.PayloadJSON = ##class(BronzeWars.AI.ArmyCommander).BuildRequest(planningContext).%ToJSON()
    set armyStatus = ..SendRequestSync("LLM Operation", armyRequest, .armyResponse)
    if $SYSTEM.Status.IsOK(armyStatus), $isobject(armyResponse) {
        set armyResult = armyResponse.Result()
        if armyResult.ok {
            set armyValidation = ##class(BronzeWars.AI.ArmyCommander).ParseAndValidate(armyResult.data.content, planningContext, .llmComposition, .llmCompositionReasoning)
            if $SYSTEM.Status.IsOK(armyValidation) set composition = llmComposition, compositionSource = "LLM", compositionReasoning = llmCompositionReasoning
            if $SYSTEM.Status.IsError(armyValidation) $$$LOGWARNING("Invalid LLM army composition; using the strategic fallback without a second model call: " _ $SYSTEM.Status.GetErrorText(armyValidation) _ " Content: " _ armyResult.data.content)
        }
    }

    set createArmyRequest = ##class(BronzeWars.Message.Request).%New()
    set createArmyRequest.Action = "CREATE_AI_UNITS"
    set createArmyRequest.PayloadJSON = {"battleId":(payload.battleId),"composition":(composition),"compositionSource":(compositionSource),"compositionReasoning":(compositionReasoning)}.%ToJSON()
    set sc = ..SendRequestSync(..#OPERATION, createArmyRequest, .createArmyResponse)
    return:$SYSTEM.Status.IsError(sc) sc
    set createArmyResult = createArmyResponse.Result()
    if 'createArmyResult.ok {
        set response = createArmyResponse
        return $$$OK
    }
    set context = createArmyResult.data

    set source = "DETERMINISTIC_FALLBACK", reasoning = "El comandante LLM no estuvo disponible o propuso un despliegue no valido."
    set llmRequest = ##class(BronzeWars.Message.Request).%New()
    set llmRequest.Action = "PLAN_AI_DEPLOYMENT"
    set llmRequest.PayloadJSON = ##class(BronzeWars.AI.DeploymentCommander).BuildRequest(context).%ToJSON()
    set llmStatus = ..SendRequestSync("LLM Operation", llmRequest, .llmResponse)
    if $SYSTEM.Status.IsOK(llmStatus), $isobject(llmResponse) {
        set llmResult = llmResponse.Result()
        if llmResult.ok {
            set validation = ##class(BronzeWars.AI.DeploymentCommander).ParseAndValidate(llmResult.data.content, context, .proposal, .llmReasoning)
            if $SYSTEM.Status.IsOK(validation) set source = "LLM", reasoning = llmReasoning
            if $SYSTEM.Status.IsError(validation) $$$LOGWARNING("Invalid LLM deployment response: " _ $SYSTEM.Status.GetErrorText(validation) _ " Content: " _ llmResult.data.content)
        }
    }
    if source '= "LLM" {
        set sc = ##class(BronzeWars.AI.DeterministicDeploymentGenerator).GenerateFromContext(context, .proposal)
        if $SYSTEM.Status.IsError(sc) return ..SetError(.response, 500, "AI_DEPLOYMENT_FAILED", "No se ha podido generar el despliegue de la IA.")
        set reasoning = "El despliegue de respaldo iguala o supera las " _ context.humanFormation.frontage _ " columnas del frente humano, mantiene una linea principal apoyada y reserva la retaguardia para los arqueros."
    }

    do payload.%Set("placements", proposal)
    do payload.%Set("deploymentSource", source)
    do payload.%Set("deploymentReasoning", reasoning)
    set request.PayloadJSON = payload.%ToJSON()
    return ..SendToOperation(request, .response)
}

}
