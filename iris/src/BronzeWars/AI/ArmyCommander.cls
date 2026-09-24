Class BronzeWars.AI.ArmyCommander Extends %RegisteredObject
{

ClassMethod BuildRequest(context As %DynamicObject) As %DynamicObject
{
    set system = "Eres el comandante de un ejercito de la Edad del Bronce. Elige la composicion completa de tu ejercito antes de desplegarlo. Devuelve exclusivamente JSON valido, sin markdown."
    set doctrine = "Dispones exactamente de " _ context.grainBudget _ " medidas de grano y debes gastarlas todas. Puedes buscar superioridad numerica con unidades economicas para ampliar el frente y envolver al rival, invertir en tropas potentes, o equilibrar ambas opciones. Analiza la composicion y la anchura del frente humano. Solo puedes elegir los tipos incluidos en unitTypes y no puedes superar la capacidad de las tres filas de despliegue."
    set format = "Devuelve composition como una lista de objetos code y quantity. quantity es el numero real de unidades, no un porcentaje ni una cantidad de grano. Usa cantidades enteras positivas, no repitas codigos y calcula la suma de quantity * grainCost; debe ser exactamente " _ context.grainBudget _ ", nunca superior. Como referencia aritmetica, 4 SPEARMEN cuestan 24, 4 HEAVY_INFANTRY cuestan 36 y 2 LIGHT_CAVALRY cuestan 40: total 100. Puedes elegir cualquier otra combinacion valida. reasoning debe explicar brevemente la estrategia elegida. Contexto: " _ context.%ToJSON()

    set codes = ##class(%DynamicArray).%New()
    for index = 0:1:(context.unitTypes.%Size() - 1) do codes.%Push(context.unitTypes.%Get(index).code)
    set selection = {"type":"object","properties":{"code":{"type":"string","enum":(codes)},"quantity":{"type":"integer","minimum":1}},"required":["code","quantity"],"additionalProperties":false}
    set schema = {"type":"object","properties":{"composition":{"type":"array","minItems":1,"items":(selection)},"reasoning":{"type":"string"}},"required":["composition","reasoning"],"additionalProperties":false}
    set responseFormat = {"type":"json_schema","json_schema":{"name":"bronze_wars_army","strict":true,"schema":(schema)}}
    return {"temperature":0.35,"max_tokens":350,"response_format":(responseFormat),"messages":[{"role":"system","content":(system)},{"role":"user","content":(doctrine _ " " _ format)}]}
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
        set totalGrain = 0, totalUnits = 0
        for index = 0:1:(answer.composition.%Size() - 1) {
            set selection = answer.composition.%Get(index)
            if '$isobject(selection) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid army selection"))
            if 'selection.%IsDefined("code") ! 'selection.%IsDefined("quantity") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete army selection"))
            set code = selection.code, quantity = selection.quantity
            if '$data(costs(code)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown unit type in AI composition"))
            if $data(seen(code)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated unit type in AI composition"))
            if (selection.%GetTypeOf("quantity") '= "number") ! (quantity < 1) ! (quantity '= (quantity \ 1)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid quantity in AI composition"))
            set seen(code) = 1
            set totalGrain = totalGrain + (costs(code) * quantity), totalUnits = totalUnits + quantity
            do composition.%Push({"code":(code),"quantity":(quantity)})
        }
        if totalGrain '= context.grainBudget throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI composition must spend the complete grain budget"))
        if totalUnits > (context.board.width * 3) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI composition does not fit in the deployment zone"))
    } catch exception {
        set result = exception.AsStatus()
    }
    return result
}

}
