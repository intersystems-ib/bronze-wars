Class BronzeWars.AI.DeploymentCommander Extends %RegisteredObject
{

ClassMethod BuildRequest(context As %DynamicObject) As %DynamicObject
{
    set system = "Eres el comandante de un ejercito de la Edad del Bronce. Debes desplegar todas las unidades en las filas 0, 1 y 2. El enemigo esta hacia filas crecientes. Devuelve exclusivamente JSON valido, sin markdown."
    set doctrine = "La prioridad tactica es evitar que el ejercito humano envuelva tus flancos. Tu frente, medido desde la menor hasta la mayor coordenada x ocupada, debe igualar o superar la anchura indicada en humanFormation.frontage siempre que el tablero lo permita. Puedes organizar el ejercito en dos filas: forma una linea principal cohesionada en la fila 1 y coloca los arqueros protegidos detras, en la fila 0. Coloca caballeria y carros en los flancos, pero durante el despliegue deben conservar el contacto y el apoyo mutuo con el resto de la formacion; no los separes para cargar, porque las cargas se decidiran durante la batalla. La infanteria pesada y los lanceros sostienen el centro. La infanteria ligera puede adelantarse a la fila 2 para escaramucear, sin quedar aislada. Evita amontonar unidades en pocas columnas y evita huecos innecesarios."
    set count = context.units.%Size()
    set format = "Hay exactamente " _ count _ " unidades. placements debe contener exactamente " _ count _ " objetos. Incluye cada unitId exactamente una vez, sin repetir casillas. El despliegue humano ocupa de x=" _ context.humanFormation.minX _ " a x=" _ context.humanFormation.maxX _ ", con una anchura de frente de " _ context.humanFormation.frontage _ ". reasoning debe explicar como se iguala o supera ese frente y como se protegen los flancos."
    set user = doctrine _ " " _ format _ " Datos de la batalla: " _ context.%ToJSON()

    set unitIds = ##class(%DynamicArray).%New()
    for index = 0:1:(count - 1) do unitIds.%Push(+(context.units.%Get(index).unitId))
    set placement = {"type":"object","properties":{"unitId":{"type":"integer","enum":(unitIds)},"x":{"type":"integer","minimum":0,"maximum":(context.board.width-1)},"y":{"type":"integer","minimum":0,"maximum":2}},"required":["unitId","x","y"],"additionalProperties":false}
    set schema = {"type":"object","properties":{"placements":{"type":"array","minItems":(count),"maxItems":(count),"items":(placement)},"reasoning":{"type":"string"}},"required":["placements","reasoning"],"additionalProperties":false}
    set responseFormat = {"type":"json_schema","json_schema":{"name":"bronze_wars_deployment","strict":true,"schema":(schema)}}
    return {"temperature":0.1,"max_tokens":450,"response_format":(responseFormat),"messages":[{"role":"system","content":(system)},{"role":"user","content":(user)}]}
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

        kill allowed, seenUnit, seenCell
        set minimumX = context.board.width, maximumX = -1
        for index = 0:1:(context.units.%Size() - 1) {
            set unit = context.units.%Get(index)
            set allowed(unit.unitId _ "") = 1
        }
        for index = 0:1:(answer.placements.%Size() - 1) {
            set placement = answer.placements.%Get(index)
            if '$isobject(placement) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid LLM placement"))
            if 'placement.%IsDefined("unitId") ! 'placement.%IsDefined("x") ! 'placement.%IsDefined("y") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete LLM placement"))
            set unitId = placement.unitId _ "", x = placement.x, y = placement.y
            if '$data(allowed(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown unit in LLM placement"))
            if $data(seenUnit(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated unit in LLM placement"))
            if (placement.%GetTypeOf("x") '= "number") ! (placement.%GetTypeOf("y") '= "number") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Non-numeric LLM coordinates"))
            if (x '= (x \ 1)) ! (y '= (y \ 1)) ! (x < 0) ! (x >= context.board.width) ! (y < 0) ! (y > 2) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM placement outside deployment zone"))
            set cell = x _ "," _ y
            if $data(seenCell(cell)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated cell in LLM placement"))
            set seenUnit(unitId) = 1, seenCell(cell) = 1
            if x < minimumX set minimumX = x
            if x > maximumX set maximumX = x
            do proposal.%Push({"unitId":(unitId),"x":(x),"y":(y)})
        }
        if context.%IsDefined("humanFormation"), ((maximumX - minimumX + 1) < context.humanFormation.frontage) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM deployment frontage is narrower than the human formation"))
    } catch exception {
        set result = exception.AsStatus()
    }
    return result
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
