Class BronzeWars.AI.DeploymentCommander Extends %RegisteredObject
{

ClassMethod BuildRequest(context As %DynamicObject) As %DynamicObject
{
    set count = context.units.%Size()
    set unitIds = ##class(%DynamicArray).%New()
    for index = 0:1:(count - 1) {
        set unit = context.units.%Get(index)
        do unitIds.%Push(+(unit.unitId))
    }
    set goal = "Despliega las unidades " _ unitIds.%ToJSON() _ " de la batalla " _ context.battleId _ ". Consulta RecommendDeploymentPositions para cada unidad; la tool obtiene de la base de datos el tipo de comandante, el frente enemigo y las posiciones aliadas. Elige una opcion recomendada libre por unidad. Devuelve solo JSON compacto con {""placements"":[[id,x,y],...],""reasoning"":""...""}, sin omitir ni repetir unidades o casillas."
    set maxIterations = (count * 2) + 4
    if maxIterations > 32 set maxIterations = 32
    return {"battleId":(context.battleId),"unitIds":(unitIds),"goal":(goal),"max_iterations":(maxIterations)}
}

ClassMethod ParseAndValidate(content As %String, context As %DynamicObject, Output proposal As %DynamicArray, Output reasoning As %String) As %Status
{
    set proposal = ##class(%DynamicArray).%New(), reasoning = "", result = $$$OK
    try {
        set json = ..CleanJSON(content)
        set answer = ##class(%DynamicObject).%FromJSON(json)
        if $classname(answer) = "%Library.DynamicArray" {
            set placements = answer
        } else {
            if answer.%GetTypeOf("placements") '= "array" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM response has no placements array"))
            set placements = answer.placements
            if answer.%IsDefined("reasoning") set reasoning = answer.reasoning
        }
        if placements.%Size() '= context.units.%Size() throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM response has an unexpected unit count"))

        kill allowed, seenUnit, seenCell, mainLine, mobileFlank
        set minimumX = context.board.width, maximumX = -1, mainMinimumX = context.board.width, mainMaximumX = -1
        for index = 0:1:(context.units.%Size() - 1) {
            set unit = context.units.%Get(index)
            set allowed(unit.unitId _ "") = unit.code
        }
        for index = 0:1:(placements.%Size() - 1) {
            set placement = placements.%Get(index)
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
            if ..IsForwardLineCode(code), (y '= 2) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Skirmish troops, archers and chariots must use the forward deployment line"))
            if ##class(BronzeWars.AI.DeterministicDeploymentGenerator).IsCavalryCode(code), (y '= 1) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Cavalry must cover the flanks of the second deployment line"))
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

ClassMethod HasPlacementPayload(content As %String) As %Boolean
{
    set valid = 0
    try {
        set answer = ##class(%DynamicObject).%FromJSON(..CleanJSON(content))
        if $classname(answer) = "%Library.DynamicArray" set valid = 1
        if $classname(answer) = "%Library.DynamicObject", answer.%GetTypeOf("placements") = "array" set valid = 1
    } catch exception {
        set valid = 0
    }
    return valid
}

ClassMethod IsMainLineCode(code As %String) As %Boolean
{
    return (code = "SPEARMEN") ! (code = "HEAVY_INFANTRY") ! (code = "MERCENARIES")
}

ClassMethod IsFlankingCode(code As %String) As %Boolean
{
    return (code = "LIGHT_INFANTRY") ! (code = "LIGHT_CAVALRY") ! (code = "HEAVY_CAVALRY") ! (code = "CHARIOTS")
}

ClassMethod IsForwardLineCode(code As %String) As %Boolean
{
    return (code = "LIGHT_INFANTRY") ! (code = "ARCHERS") ! (code = "CHARIOTS")
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
