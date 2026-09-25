Class BronzeWars.AI.ArmyCommander Extends %RegisteredObject
{

ClassMethod BuildRequest(context As %DynamicObject) As %DynamicObject
{
    set system = "Eres un comandante " _ context.commanderName _ " de la Edad del Bronce. Elige un ejercito y responde solo JSON compacto."
    set available = ##class(%DynamicArray).%New()
    for index = 0:1:(context.unitTypes.%Size() - 1) {
        set unitType = context.unitTypes.%Get(index)
        set availableUnit = ##class(%DynamicArray).%New()
        do availableUnit.%Push(unitType.code)
        do availableUnit.%Push(unitType.grainCost)
        do available.%Push(availableUnit)
    }
    set doctrine = "Doctrina: " _ context.commanderDoctrine _ " Presupuesto exacto=" _ context.grainBudget _ ". Maximo unidades=" _ (context.board.width * 3) _ ". Minimo unidades de SPEARMEN, HEAVY_INFANTRY o MERCENARIES=" _ ..TargetLineLength(context) _ ". Tipos [codigo,coste]=" _ available.%ToJSON() _ "."
    set format = "Devuelve {composition:[[codigo,cantidad],...]}. Cantidades enteras positivas, codigos sin repetir y suma coste*cantidad exactamente " _ context.grainBudget _ ". Si eres flanqueador incluye al menos dos unidades moviles: LIGHT_INFANTRY, LIGHT_CAVALRY, HEAVY_CAVALRY o CHARIOTS. No incluyas explicaciones."

    set codes = ##class(%DynamicArray).%New()
    for index = 0:1:(context.unitTypes.%Size() - 1) do codes.%Push(context.unitTypes.%Get(index).code)
    set selection = {"type":"array","prefixItems":[{"type":"string","enum":(codes)},{"type":"integer","minimum":1}],"minItems":2,"maxItems":2}
    set schema = {"type":"object","properties":{"composition":{"type":"array","minItems":1,"items":(selection)}},"required":["composition"],"additionalProperties":false}
    set responseFormat = {"type":"json_schema","json_schema":{"name":"bronze_wars_army","strict":true,"schema":(schema)}}
    return {"temperature":0.25,"max_tokens":140,"response_format":(responseFormat),"messages":[{"role":"system","content":(system)},{"role":"user","content":(doctrine _ " " _ format)}]}
}

ClassMethod BuildCorrectionRequest(context As %DynamicObject, invalidContent As %String, validationError As %String) As %DynamicObject
{
    set request = ..BuildRequest(context)
    do request.messages.%Push({"role":"assistant","content":(invalidContent)})
    set correction = "La propuesta anterior no es valida: " _ validationError _ ". Recalcula las cantidades. Debes gastar exactamente 100 medidas, no asignar porcentajes. El maximo es " _ (context.board.width * 3) _ " unidades. Comprueba explicitamente cada quantity * grainCost y devuelve unicamente el objeto JSON corregido."
    do request.messages.%Push({"role":"user","content":(correction)})
    return request
}

ClassMethod ParseAndValidate(content As %String, context As %DynamicObject, Output composition As %DynamicArray, Output reasoning As %String) As %Status
{
    set composition = ##class(%DynamicArray).%New(), reasoning = "", result = $$$OK
    try {
        set json = ##class(BronzeWars.AI.DeploymentCommander).CleanJSON(content)
        set answer = ##class(%DynamicObject).%FromJSON(json)
        if answer.%GetTypeOf("composition") '= "array" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM response has no composition array"))
        if answer.%IsDefined("reasoning") set reasoning = answer.reasoning

        kill costs, seen
        for index = 0:1:(context.unitTypes.%Size() - 1) {
            set unitType = context.unitTypes.%Get(index)
            set costs(unitType.code) = unitType.grainCost
        }
        set totalGrain = 0, totalUnits = 0, lineUnits = 0
        for index = 0:1:(answer.composition.%Size() - 1) {
            set selection = answer.composition.%Get(index)
            if '$isobject(selection) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid army selection"))
            if selection.%IsDefined(0) {
                if 'selection.%IsDefined(1) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete army selection"))
                set code = selection.%Get(0), quantity = selection.%Get(1), quantityType = selection.%GetTypeOf(1)
            } else {
                if 'selection.%IsDefined("code") ! 'selection.%IsDefined("quantity") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete army selection"))
                set code = selection.code, quantity = selection.quantity, quantityType = selection.%GetTypeOf("quantity")
            }
            if '$data(costs(code)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown unit type in AI composition"))
            if $data(seen(code)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated unit type in AI composition"))
            if (quantityType '= "number") ! (quantity < 1) ! (quantity '= (quantity \ 1)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid quantity in AI composition"))
            set seen(code) = 1
            set totalGrain = totalGrain + (costs(code) * quantity), totalUnits = totalUnits + quantity
            if ##class(BronzeWars.Rules.FormationMorale).IsSupportedUnitCode(code), (code '= "LIGHT_INFANTRY") set lineUnits = lineUnits + quantity
            do composition.%Push({"code":(code),"quantity":(quantity)})
        }
        if totalGrain '= context.grainBudget throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI composition must spend the complete grain budget"))
        if totalUnits > (context.board.width * 3) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI composition does not fit in the deployment zone"))
        if lineUnits < ..TargetLineLength(context) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI composition does not contain enough infantry or spearmen for the required front"))
        set sc = ##class(BronzeWars.AI.Commanders.Strategy).ValidateComposition(context.commanderType, composition)
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
    } catch exception {
        set result = exception.AsStatus()
    }
    return result
}

ClassMethod TargetLineLength(context As %DynamicObject) As %Integer
{
    if context.%IsDefined("formationDoctrine") return context.formationDoctrine.mainLineTarget
    return ##class(BronzeWars.AI.Commanders.Strategy).MainLineTarget(context.commanderType, context.humanFormation.frontage, context.board.width)
}

}
