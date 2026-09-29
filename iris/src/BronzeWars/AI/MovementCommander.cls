Class BronzeWars.AI.MovementCommander Extends %RegisteredObject
{

ClassMethod BuildDecisionRequest(context As %DynamicObject) As %DynamicObject
{
    set goal = "Decide la estrategia global de movimiento para la batalla " _ context.battleId _ ". Debes consultar GetBattleSituation con ese battleId y aplicar literalmente sus umbrales. Devuelve solo el JSON solicitado."
    return {"battleId":(context.battleId),"goal":(goal),"max_iterations":4}
}

ClassMethod ParseDecision(content As %String, expectedStrategy As %String, Output strategy As %String, Output reasoning As %String) As %Status
{
    set strategy = "", reasoning = "", result = $$$OK
    try {
        set json = ##class(BronzeWars.AI.DeploymentCommander).CleanJSON(content)
        set answer = ##class(%DynamicObject).%FromJSON(json)
        if answer.%GetTypeOf("strategy") '= "string" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM movement decision has no strategy"))
        set strategy = $zconvert(answer.strategy, "U")
        if (strategy '= "REGROUP") && (strategy '= "ADVANCE") && (strategy '= "TACTICAL") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown LLM movement strategy"))
        if strategy '= expectedStrategy throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM movement strategy contradicts the battle situation"))
        if answer.%IsDefined("reasoning") set reasoning = answer.reasoning
    } catch exception {
        set normalizedContent = $zconvert(content, "U")
        set otherStrategyFound = 0
        for candidate = "REGROUP","ADVANCE","TACTICAL" {
            if (candidate '= expectedStrategy), ($find(normalizedContent, candidate) > 0) set otherStrategyFound = 1
        }
        if (expectedStrategy '= ""), ($find(normalizedContent, expectedStrategy) > 0), 'otherStrategyFound {
            set strategy = expectedStrategy
            set reasoning = "El comandante selecciona " _ expectedStrategy _ " tras consultar BattleSituation."
            set result = $$$OK
        } else {
            set result = exception.AsStatus()
        }
    }
    return result
}

ClassMethod ParseAndValidate(content As %String, context As %DynamicObject, Output movements As %DynamicArray, Output reasoning As %String) As %Status
{
    set movements = ##class(%DynamicArray).%New(), reasoning = "", result = $$$OK
    try {
        set json = ##class(BronzeWars.AI.DeploymentCommander).CleanJSON(content)
        set answer = ##class(%DynamicObject).%FromJSON(json)
        if answer.%GetTypeOf("movements") '= "array" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM response has no movements array"))
        if answer.movements.%Size() '= context.aiUnits.%Size() throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "LLM movement response has an unexpected unit count"))
        if answer.%IsDefined("reasoning") set reasoning = answer.reasoning

        kill units, seen, occupied, finalLineX
        set lineRow = "", lineCount = 0, lineMin = context.board.width, lineMax = -1
        for index = 0:1:(context.humanUnits.%Size() - 1) {
            set unit = context.humanUnits.%Get(index)
            set occupied(unit.x _ "," _ unit.y) = unit.unitId
        }
        for index = 0:1:(context.aiUnits.%Size() - 1) {
            set unit = context.aiUnits.%Get(index), unitId = unit.unitId _ ""
            set units(unitId) = index, occupied(unit.x _ "," _ unit.y) = unit.unitId
        }
        for index = 0:1:(answer.movements.%Size() - 1) {
            set movement = answer.movements.%Get(index)
            if '$isobject(movement) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid AI movement"))
            set unitId = movement.unitId _ ""
            if '$data(units(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown unit in AI movement"))
            if $data(seen(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated unit in AI movement"))
            set unit = context.aiUnits.%Get(units(unitId)), x = movement.x, y = movement.y
            if (x '= (x \ 1)) ! (y '= (y \ 1)) ! (x < 0) ! (x >= context.board.width) ! (y < 0) ! (y >= context.board.height) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI movement outside board"))
            set deltaX = x - unit.x, deltaY = y - unit.y, distanceX = deltaX, distanceY = deltaY
            if distanceX < 0 set distanceX = -distanceX
            if distanceY < 0 set distanceY = -distanceY
            set distance = distanceX + distanceY
            if (distanceX > 0), (distanceY > 0) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI movement is not cardinal"))
            if distance > unit.remainingMovement throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI movement exceeds unit speed"))
            kill occupied(unit.x _ "," _ unit.y)
            set stepX = $select(deltaX<0:-1, deltaX>0:1, 1:0), stepY = $select(deltaY<0:-1, deltaY>0:1, 1:0)
            for step = 1:1:distance {
                set cell = (unit.x + (step * stepX)) _ "," _ (unit.y + (step * stepY))
                if $data(occupied(cell)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI movement path is occupied"))
            }
            set occupied(x _ "," _ y) = unit.unitId, seen(unitId) = 1
            if ##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code) {
                if lineRow = "" set lineRow = y
                if y '= lineRow throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI movement breaks infantry cohesion"))
                set finalLineX(x) = 1
                set lineCount = lineCount + 1
                if x < lineMin set lineMin = x
                if x > lineMax set lineMax = x
            }
            do movements.%Push({"unitId":(unit.unitId),"x":(x),"y":(y)})
        }
        if (lineCount > 0), ((lineMax - lineMin + 1) '= lineCount) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI movement opens gaps in infantry line"))
    } catch exception {
        set result = exception.AsStatus()
    }
    return result
}

}
