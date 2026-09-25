Class BronzeWars.AI.DeploymentCommander Extends %RegisteredObject
{

ClassMethod BuildRequest(context As %DynamicObject) As %DynamicObject
{
    set system = "Eres un comandante " _ context.commanderName _ " de la Edad del Bronce. Despliega todas las unidades y responde solo JSON compacto."
    set count = context.units.%Size()
    set units = ##class(%DynamicArray).%New()
    for index = 0:1:(count - 1) {
        set unit = context.units.%Get(index)
        set compactUnit = ##class(%DynamicArray).%New()
        do compactUnit.%Push(+(unit.unitId))
        do compactUnit.%Push(unit.code)
        do units.%Push(compactUnit)
    }
    set user = "Doctrina: " _ context.commanderDoctrine _ " Tablero ancho=" _ context.board.width _ ". Enemigo x=" _ context.humanFormation.minX _ ".." _ context.humanFormation.maxX _ ". Unidades [id,tipo]=" _ units.%ToJSON() _ ". Devuelve {placements:[[id,x,y],...]}, cada id una vez y sin repetir casillas. Filas validas y=0,1,2. Forma en y=1 una linea consecutiva de al menos " _ context.formationDoctrine.mainLineTarget _ " SPEARMEN, HEAVY_INFANTRY o MERCENARIES. ARCHERS en y=0; LIGHT_INFANTRY puede ir en y=2. Si eres flanqueador, supera el frente rival y usa unidades moviles en ambos extremos. No incluyas explicaciones."

    set unitIds = ##class(%DynamicArray).%New()
    for index = 0:1:(count - 1) do unitIds.%Push(+(context.units.%Get(index).unitId))
    set placement = {"type":"array","prefixItems":[{"type":"integer","enum":(unitIds)},{"type":"integer","minimum":0,"maximum":(context.board.width-1)},{"type":"integer","minimum":0,"maximum":2}],"minItems":3,"maxItems":3}
    set schema = {"type":"object","properties":{"placements":{"type":"array","minItems":(count),"maxItems":(count),"items":(placement)}},"required":["placements"],"additionalProperties":false}
    set responseFormat = {"type":"json_schema","json_schema":{"name":"bronze_wars_deployment","strict":true,"schema":(schema)}}
    set maxTokens = 60 + (count * 9)
    if maxTokens > 240 set maxTokens = 240
    return {"temperature":0.1,"max_tokens":(maxTokens),"response_format":(responseFormat),"messages":[{"role":"system","content":(system)},{"role":"user","content":(user)}]}
}

ClassMethod ParseAndValidate(content As %String, context As %DynamicObject, Output proposal As %DynamicArray, Output reasoning As %String) As %Status
{
    set proposal = ##class(%DynamicArray).%New(), reasoning = "", result = $$$OK
    try {
        set json = ..CleanJSON(content)
        set answer = ##class(%DynamicObject).%FromJSON(json)
        if answer.%GetTypeOf("placements") '= "array" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM response has no placements array"))
        if answer.%IsDefined("reasoning") set reasoning = answer.reasoning
        if answer.placements.%Size() '= context.units.%Size() throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM response has an unexpected unit count"))

        kill allowed, seenUnit, seenCell, mainLine, mobileFlank
        set minimumX = context.board.width, maximumX = -1, mainMinimumX = context.board.width, mainMaximumX = -1
        for index = 0:1:(context.units.%Size() - 1) {
            set unit = context.units.%Get(index)
            set allowed(unit.unitId _ "") = unit.code
        }
        for index = 0:1:(answer.placements.%Size() - 1) {
            set placement = answer.placements.%Get(index)
            if '$isobject(placement) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid LLM placement"))
            if placement.%IsDefined(0) {
                if 'placement.%IsDefined(1) ! 'placement.%IsDefined(2) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete LLM placement"))
                set unitId = placement.%Get(0) _ "", x = placement.%Get(1), y = placement.%Get(2), xType = placement.%GetTypeOf(1), yType = placement.%GetTypeOf(2)
            } else {
                if 'placement.%IsDefined("unitId") ! 'placement.%IsDefined("x") ! 'placement.%IsDefined("y") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete LLM placement"))
                set unitId = placement.unitId _ "", x = placement.x, y = placement.y, xType = placement.%GetTypeOf("x"), yType = placement.%GetTypeOf("y")
            }
            if '$data(allowed(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown unit in LLM placement"))
            if $data(seenUnit(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated unit in LLM placement"))
            if (xType '= "number") ! (yType '= "number") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Non-numeric LLM coordinates"))
            if (x '= (x \ 1)) ! (y '= (y \ 1)) ! (x < 0) ! (x >= context.board.width) ! (y < 0) ! (y > 2) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM placement outside deployment zone"))
            set cell = x _ "," _ y
            if $data(seenCell(cell)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated cell in LLM placement"))
            set seenUnit(unitId) = 1, seenCell(cell) = 1
            set code = allowed(unitId)
            if ..IsFlankingCode(code) set mobileFlank(x) = 1
            if (y = context.formationDoctrine.mainLineRow), ..IsMainLineCode(code) {
                set mainLine(x) = 1
                if x < mainMinimumX set mainMinimumX = x
                if x > mainMaximumX set mainMaximumX = x
            }
            if x < minimumX set minimumX = x
            if x > maximumX set maximumX = x
            do proposal.%Push({"unitId":(unitId),"x":(x),"y":(y)})
        }
        if context.commanderType = ##class(BronzeWars.AI.Commanders.Strategy).#FLANKER {
            if (maximumX - minimumX + 1) < context.formationDoctrine.frontageTarget throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Flanking deployment does not extend beyond the human formation"))
            if ('$data(mobileFlank(minimumX))) ! ('$data(mobileFlank(maximumX))) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Flanking deployment requires mobile units on both extremes"))
        }
        if mainMaximumX < mainMinimumX throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM deployment has no infantry main line"))
        if (mainMaximumX - mainMinimumX + 1) < context.formationDoctrine.mainLineTarget throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM infantry main line is shorter than required"))
        for lineX = mainMinimumX:1:mainMaximumX {
            if '$data(mainLine(lineX)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM infantry main line contains gaps"))
        }
    } catch exception {
        set result = exception.AsStatus()
    }
    return result
}

ClassMethod IsMainLineCode(code As %String) As %Boolean
{
    return (code = "SPEARMEN") ! (code = "HEAVY_INFANTRY") ! (code = "MERCENARIES")
}

ClassMethod IsFlankingCode(code As %String) As %Boolean
{
    return (code = "LIGHT_INFANTRY") ! (code = "LIGHT_CAVALRY") ! (code = "HEAVY_CAVALRY") ! (code = "CHARIOTS")
}

ClassMethod CleanJSON(content As %String) As %String
{
    set value = $zstrip(content, "<>W")
    set value = $replace(value, "```json", "")
    set value = $replace(value, "```JSON", "")
    set value = $replace(value, "```", "")
    return $zstrip(value, "<>W")
}

}
