Class BronzeWars.AI.CampaignRecruitment Extends %RegisteredObject
{

ClassMethod Decide(capacity As %DynamicObject) As %DynamicObject
{
    set contextId = $system.Util.CreateGUID()
    try {
        if '$isobject(capacity) return ##class(BronzeWars.Service.Result).Error(400, "INVALID_CAPACITY", "Falta la capacidad de reclutamiento.")
        if (capacity.nation '= "egypt"), (capacity.nation '= "hatti"), (capacity.nation '= "nubia") return ##class(BronzeWars.Service.Result).Error(400, "INVALID_NATION", "Nacion no valida.")
        for key = "reserve","annualProduction","consumptionPerTurn","annualConsumption","troops","maxAffordableTroops","maxSustainableTroops","turn","turnsToHarvest" {
            if (capacity.%GetTypeOf(key) '= "number") || (capacity.%Get(key) < 0) return ##class(BronzeWars.Service.Result).Error(400, "INVALID_CAPACITY", "La capacidad debe contener valores numericos positivos.")
        }
        if (capacity.%GetTypeOf("units") '= "array") || (capacity.units.%Size() < 1) || (capacity.units.%Size() > 8) return ##class(BronzeWars.Service.Result).Error(400, "INVALID_CATALOGUE", "Catalogo de unidades no valido.")
        if capacity.%GetTypeOf("capitalAvailable") '= "boolean" return ##class(BronzeWars.Service.Result).Error(400, "INVALID_CAPACITY", "Falta el estado de la capital.")
        set deploymentValidation = ..ValidateDeploymentContext(capacity)
        if 'deploymentValidation.ok return deploymentValidation
        set blocked = ..RecruitmentBlock(capacity)
        if blocked '= "" return ##class(BronzeWars.Service.Result).Success(200, {"action":"wait","reason":(blocked),"source":"RULES","blockReason":(blocked)})
        set ^BronzeWarsCampaignContext(contextId, "capacity") = capacity.%ToJSON()
        set provider = ##class(BronzeWars.AI.Agent.Campaign).CreateProvider()
        set sc = provider.ValidateConfig()
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        set agent = ##class(BronzeWars.AI.Agent.Campaign).%New(provider)
        set sc = agent.UseToolSet("BronzeWars.AI.ToolSets.CampaignRecruitment")
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        set sc = agent.%Init()
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        set capacity = ..ConsultCapacity(agent, contextId)
        set session = agent.CreateSession({"max_tokens":400,"max_iterations":4,"timeout_ms":45000})
        set goal = "El servidor ya ha ejecutado GetRecruitmentCapacity. Este es su resultado real: " _ capacity.%ToJSON() _ ". Decide si reclutas este turno usando estos datos. No vuelvas a llamar a herramientas. Responde solo el JSON indicado."
        set response = agent.Chat(session, goal)
        set sc = ..ParseDecision(response.Content, capacity, .answer)
        if $SYSTEM.Status.IsError(sc) {
            set correction = "Tu orden no es valida: " _ $SYSTEM.Status.GetErrorText(sc) _ ". Corrigela eligiendo un optionId de las options de la herramienta o action wait. Responde SOLO JSON con action, optionId si reclutas y reason."
            if 'capacity.capitalAvailable set correction = "No queda espacio libre en la region de la capital o la capital se ha perdido. options esta vacio y no puedes reclutar. Responde solo JSON con action wait y reason. Ejemplo: {""action"":""wait"",""reason"":""No hay espacio de despliegue en la region de la capital""}."
            set response = agent.Chat(session, correction)
            set sc = ..ParseDecision(response.Content, capacity, .answer)
        }
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, $SYSTEM.Status.GetErrorText(sc) _ " Response: " _ response.Content))
        do answer.%Set("source", "LLM")
        do answer.%Set("model", ##class(BronzeWars.AI.Agent.Campaign).#MODEL)
        kill ^BronzeWarsCampaignContext(contextId)
        return ##class(BronzeWars.Service.Result).Success(200, answer)
    } catch exception {
        kill ^BronzeWarsCampaignContext(contextId)
        set details = []
        do details.%Push({"field":"model","message":($extract(exception.DisplayString(),1,1000))})
        return ##class(BronzeWars.Service.Result).Error(503, "CAMPAIGN_LLM_UNAVAILABLE", "El modelo local no ha completado una decision de reclutamiento valida.", details)
    }
}

ClassMethod RecruitmentBlock(capacity As %DynamicObject) As %String
{
    if capacity.annualProduction + 0.000000001 < (capacity.consumptionPerTurn * 3) return "PRODUCTION_DEFICIT"
    set cheapest = ""
    for index = 0:1:(capacity.units.%Size()-1) {
        set unit = capacity.units.%Get(index)
        if (unit.%GetTypeOf("cost") = "number"), unit.cost > 0 {
            if (cheapest = "") || (unit.cost < cheapest) set cheapest = unit.cost
        }
    }
    if (cheapest = "") || (capacity.reserve < (cheapest * ##class(BronzeWars.Rules.ArmyBudget).#MINUNITS)) return "INSUFFICIENT_GRAIN"
    return ""
}

ClassMethod ValidateDeploymentContext(capacity As %DynamicObject) As %DynamicObject
{
    if (capacity.%Get("deploymentArea") '= "capital_region") || (capacity.%GetTypeOf("freeDeploymentHexes") '= "number") {
        return ##class(BronzeWars.Service.Result).Error(409, "CAMPAIGN_CLIENT_OUTDATED", "Recarga la pagina para actualizar las reglas de despliegue regional.")
    }
    set free = capacity.freeDeploymentHexes
    if (free < 0) || (free '= (free \ 1)) || (capacity.%GetTypeOf("capitalAvailable") '= "boolean") || (capacity.capitalAvailable '= (free > 0)) {
        return ##class(BronzeWars.Service.Result).Error(400, "INVALID_DEPLOYMENT_CAPACITY", "El espacio disponible no coincide con las casillas libres de la region.")
    }
    return ##class(BronzeWars.Service.Result).Success(200)
}

ClassMethod ConsultCapacity(agent As %AI.Agent, contextId As %String) As %DynamicObject
{
    set toolResult = agent.ToolManager.ExecuteTool("GetRecruitmentCapacity", {"contextId":(contextId)})
    if '$get(^BronzeWarsCampaignContext(contextId, "used")) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Recruitment capacity tool failed before the model decision"))
    if toolResult.%GetTypeOf("value") '= "object" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Recruitment capacity tool returned no data"))
    set capacity = toolResult.value
    if capacity.%IsDefined("error") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Recruitment capacity tool returned an error"))
    return capacity
}

ClassMethod ParseDecision(content As %String, capacity As %DynamicObject, Output answer As %DynamicObject) As %Status
{
    try {
        set answer = ##class(%DynamicObject).%FromJSON(##class(BronzeWars.AI.DeploymentCommander).CleanJSON(content))
        return ..ValidateDecision(answer, capacity)
    } catch exception {
        return $$$ERROR($$$GeneralError, "Return one JSON object with action, optionId if recruiting, and reason")
    }
}

ClassMethod ValidateDecision(answer As %DynamicObject, capacity As %DynamicObject) As %Status
{
    if (answer.%GetTypeOf("reason") '= "string") return $$$ERROR($$$GeneralError, "Missing recruitment reason")
    if answer.action = "wait" return $$$OK
    if (answer.%GetTypeOf("optionId") = "string"), (capacity.%GetTypeOf("options") = "array") {
        set foundOption = 0
        for optionIndex = 0:1:capacity.options.%Size()-1 {
            set option = capacity.options.%Get(optionIndex)
            if option.id = answer.optionId do answer.%Set("quantities", option.quantities) set foundOption = 1
        }
        if 'foundOption return $$$ERROR($$$GeneralError, "Unknown recruitment option")
    }
    if (answer.action '= "recruit") || (answer.%GetTypeOf("quantities") '= "object") || 'capacity.capitalAvailable return $$$ERROR($$$GeneralError, "Invalid recruitment action")
    set count = 0, cost = 0, iterator = answer.quantities.%GetIterator()
    while iterator.%GetNext(.code, .quantity) {
        if (answer.quantities.%GetTypeOf(code) '= "number") || (quantity '= (quantity \ 1)) || (quantity < 1) || (quantity > 99) return $$$ERROR($$$GeneralError, "Invalid recruitment quantity")
        set found = 0
        for index = 0:1:capacity.units.%Size()-1 {
            set unit = capacity.units.%Get(index)
            if unit.code = code {
                set found = 1, cost = cost + (quantity * unit.cost), count = count + quantity
                if quantity > unit.maxAffordable return $$$ERROR($$$GeneralError, "Unaffordable recruitment quantity")
            }
        }
        if 'found return $$$ERROR($$$GeneralError, "Unknown national unit")
    }
    if count < ##class(BronzeWars.Rules.ArmyBudget).#MINUNITS return $$$ERROR($$$GeneralError, "Army requires at least four divisions")
    if cost > capacity.reserve return $$$ERROR($$$GeneralError, "Unaffordable army")
    if capacity.%IsDefined("annualProduction"), capacity.%IsDefined("consumptionPerTurn") {
        if ..RecruitmentBlock(capacity) '= "" return $$$ERROR($$$GeneralError, "Recruitment blocked by production or reserves")
    }
    return $$$OK
}

}
