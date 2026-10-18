Class BronzeWars.AI.CampaignStrategy Extends %RegisteredObject
{
ClassMethod Decide(situation As %DynamicObject) As %DynamicObject
{
    set contextId = $system.Util.CreateGUID()
    try {
        if '$isobject(situation) return ##class(BronzeWars.Service.Result).Error(400, "INVALID_STRATEGY_CONTEXT", "Falta la situacion de campana.")
        if (situation.%GetTypeOf("armies") '= "array") || (situation.%GetTypeOf("options") '= "array") || (situation.armies.%Size() > 4) || (situation.armies.%Size() < 1) return ##class(BronzeWars.Service.Result).Error(400, "INVALID_STRATEGY_CONTEXT", "Lote de ejercitos no valido.")
        if (situation.nation '= "egypt"), (situation.nation '= "hatti"), (situation.nation '= "nubia") return ##class(BronzeWars.Service.Result).Error(400, "INVALID_NATION", "Nacion no valida.")
        set ^BronzeWarsCampaignStrategy(contextId, "situation") = situation.%ToJSON()
        set agent = ##class(BronzeWars.AI.Agent.CampaignStrategy).%New(##class(BronzeWars.AI.Agent.CampaignStrategy).CreateProvider())
        set sc = agent.UseToolSet("BronzeWars.AI.ToolSets.CampaignSituation")
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        set sc = agent.%Init()
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        set toolResult = agent.ToolManager.ExecuteTool("GetCampaignSituation", {"contextId":(contextId)})
        if '$get(^BronzeWarsCampaignStrategy(contextId, "used")) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Strategy tool did not execute"))
        set situation = toolResult.value
        set reinforcementResult = agent.ToolManager.ExecuteTool("GetArmyReinforcementAdvice", {"contextId":(contextId)})
        if '$get(^BronzeWarsCampaignStrategy(contextId,"reinforcementUsed")) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Reinforcement advice tool did not execute"))
        if reinforcementResult.%GetTypeOf("value") '= "object" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Missing reinforcement advice"))
        do situation.%Set("reinforcementAdvice",reinforcementResult.value.advice)
        set prompt = "Resultados reales de GetCampaignSituation y GetArmyReinforcementAdvice: " _ ..ModelSituation(situation).%ToJSON() _ ". Una orden por ejercito. Copia literalmente options[].id como optionId. DEFEND y MERGE usan el id del ejercito objetivo, no coordenadas. Devuelve el JSON completo con orders y reason (motivo de una frase breve)."
        set session = agent.CreateSession({"max_tokens":768,"timeout_ms":60000})
        set response = agent.Chat(session, prompt)
        set sc = ..Parse(response.Content, situation, .answer)
        if $SYSTEM.Status.IsError(sc) {
            // A correction gets a fresh context: retaining the failed answer and
            // appending another prompt can leave no room for the complete JSON.
            set session = agent.CreateSession({"max_tokens":1024,"timeout_ms":60000})
            set response = agent.Chat(session, prompt _ " Corrige el error de un intento anterior: " _ $extract($SYSTEM.Status.GetErrorText(sc),1,240) _ ". Genera toda la respuesta desde el principio; no continues un fragmento. No omitas ejercitos ni inventes opciones.")
            set sc = ..Parse(response.Content, situation, .answer)
        }
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, $SYSTEM.Status.GetErrorText(sc) _ " Response: " _ $extract(response.Content,1,1000)))
        do answer.%Set("source", "LLM")
        kill ^BronzeWarsCampaignStrategy(contextId)
        return ##class(BronzeWars.Service.Result).Success(200, answer)
    } catch exception {
        kill ^BronzeWarsCampaignStrategy(contextId)
        return ##class(BronzeWars.Service.Result).Error(503, "CAMPAIGN_STRATEGY_UNAVAILABLE", "El modelo no ha completado una estrategia valida.", [{"field":"model","message":($extract(exception.DisplayString(),1,1500))}])
    }
}

ClassMethod ModelSituation(situation As %DynamicObject) As %DynamicObject
{
    // Keep the audited context intact for validation. Friendly merge candidates
    // are already in reinforcementAdvice; retain every enemy observation.
    set compact=##class(%DynamicObject).%FromJSON(situation.%ToJSON())
    for index=0:1:(compact.armies.%Size()-1) {
        set army=compact.armies.%Get(index)
        do army.%Remove("mergeCandidates")
    }
    return compact
}

ClassMethod OptionMenu(situation As %DynamicObject) As %DynamicArray
{
    set menu=[]
    for armyIndex=0:1:(situation.armies.%Size()-1) {
        set armyId=situation.armies.%Get(armyIndex).id, ids=[]
        for optionIndex=0:1:(situation.options.%Size()-1) {
            set option=situation.options.%Get(optionIndex)
            if option.armyId=armyId do ids.%Push(option.id)
        }
        do menu.%Push({"armyId":(armyId),"optionIds":(ids)})
    }
    return menu
}

ClassMethod CanonicalOptionId(id As %String, situation As %DynamicObject) As %String
{
    // An exact ID always wins. A coordinate alias is safe only when it identifies
    // exactly one existing option with the same army, intent and destination.
    set canonical="", matches=0
    for index=0:1:(situation.options.%Size()-1) {
        set option=situation.options.%Get(index)
        if option.id=id return id
        if option.%GetTypeOf("targetHexId")="string", (option.targetHexId[",") {
            if id=(option.armyId_":"_option.intent_":"_option.targetHexId) {
                set canonical=option.id, matches=matches+1
            }
        }
    }
    return $select(matches=1:canonical,1:"")
}

ClassMethod Parse(content As %String, situation As %DynamicObject, Output answer As %DynamicObject) As %Status
{
    try {
        set json = $zstrip(##class(BronzeWars.AI.DeploymentCommander).CleanJSON(content), "<>W", $char(9,10,13))
        try {
            set answer = ##class(%DynamicObject).%FromJSON(json)
        } catch jsonException {
            // Only a missing final root brace can be completed. Never infer an
            // unfinished string, array, nested object, field or military order.
            if '..MissingRootClose(json) return $$$ERROR($$$GeneralError, "Invalid orders JSON: incomplete or malformed response")
            try {
                set answer = ##class(%DynamicObject).%FromJSON(json _ "}")
            } catch incompleteException {
                return $$$ERROR($$$GeneralError, "Invalid orders JSON: incomplete or malformed response")
            }
        }
        if $classname(answer) '= "%Library.DynamicObject" return $$$ERROR($$$GeneralError, "Return one object with orders and reason")
        if answer.%GetTypeOf("orders") '= "array" return $$$ERROR($$$GeneralError, "Orders must be an array")
        if answer.%GetTypeOf("reason") '= "string" return $$$ERROR($$$GeneralError, "Missing strategy reason")
        if answer.orders.%Size() '= situation.armies.%Size() return $$$ERROR($$$GeneralError, "Exactly one order per army is required")
        kill seen, expected
        for armyIndex = 0:1:situation.armies.%Size()-1 {
            set expected(situation.armies.%Get(armyIndex).id) = 1
        }
        set hasDefend = 0, canDefend = 0, hasReclaim = 0, canReclaim = 0, reinforcing = 0
        kill recommendedMerge
        if situation.%GetTypeOf("reinforcementAdvice") = "array" {
            for adviceIndex=0:1:(situation.reinforcementAdvice.%Size()-1) {
                set advice=situation.reinforcementAdvice.%Get(adviceIndex)
                if advice.recommendMerge set recommendedMerge(advice.armyId)=1
            }
        }
        for index = 0:1:situation.options.%Size()-1 {
            if situation.options.%Get(index).intent = "DEFEND" set canDefend = 1
            if situation.options.%Get(index).intent = "RECLAIM" set canReclaim = 1
        }
        for index = 0:1:answer.orders.%Size()-1 {
            set order = answer.orders.%Get(index), found = 0
            if answer.orders.%GetTypeOf(index) '= "object" return $$$ERROR($$$GeneralError, "Each order must be an object with optionId")
            if order.%GetTypeOf("optionId") '= "string" return $$$ERROR($$$GeneralError, "Each order requires a string optionId")
            set canonical=..CanonicalOptionId(order.optionId,situation)
            if canonical="" return $$$ERROR($$$GeneralError, "Unknown or ambiguous option id: " _ $extract(order.optionId,1,120))
            set order.optionId=canonical
            for optionIndex = 0:1:situation.options.%Size()-1 {
                set option = situation.options.%Get(optionIndex)
                if option.id = order.optionId {
                    if '$data(expected(option.armyId)) return $$$ERROR($$$GeneralError, "Army outside current batch")
                    if $data(seen(option.armyId)) return $$$ERROR($$$GeneralError, "Duplicated army order")
                    set seen(option.armyId) = 1, found = 1
                    if option.intent = "DEFEND" set hasDefend = 1
                    if option.intent = "RECLAIM" set hasReclaim = 1
                    if option.intent = "MERGE", $data(recommendedMerge(option.armyId)) set reinforcing = 1
                }
            }
            if 'found return $$$ERROR($$$GeneralError, "Unknown option id")
        }
        if (situation.priority = "DEFEND"), canDefend, 'hasDefend, 'reinforcing return $$$ERROR($$$GeneralError, "Invaders must be defended against")
        if (situation.priority = "RECLAIM"), canReclaim, 'hasReclaim, 'reinforcing return $$$ERROR($$$GeneralError, "Occupied territory must be reclaimed")
        return $$$OK
    } catch exception {
        return $$$ERROR($$$GeneralError, "Invalid strategy response: " _ exception.Name)
    }
}

ClassMethod MissingRootClose(json As %String) As %Boolean
{
    if $extract(json,1) '= "{" return 0
    set stack = "", inString = 0, escaped = 0
    for index = 1:1:$length(json) {
        set char = $extract(json,index)
        if inString {
            if escaped { set escaped = 0 continue }
            if char = $char(92) { set escaped = 1 continue }
            if char = $char(34) set inString = 0
        } else {
            if char = $char(34) { set inString = 1 continue }
            if (char = "{") ! (char = "[") { set stack = stack _ char continue }
            if (char = "}") ! (char = "]") {
                set expected = $select(char="}":"{",1:"[")
                if $extract(stack,*) '= expected return 0
                set stack = $extract(stack,1,$length(stack)-1)
            }
        }
    }
    return (stack = "{") && 'inString
}
}
