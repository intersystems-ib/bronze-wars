Class BronzeWars.AI.MovementCommander Extends %RegisteredObject
{

ClassMethod BuildAgentGoal(context As %DynamicObject) As %String
{
    set instruction = ##class(BronzeWars.AI.Commanders.Strategy).MovementInstruction(context.commanderType)
    return "Planifica el movimiento de la batalla " _ context.battleId _ ". Eres un comandante " _ context.commanderName _ ". " _ instruction _ " Ejecuta el flujo de herramientas configurado y finaliza cuando SubmitMovementChoices confirme todas las elecciones."
}

ClassMethod ParseChoices(content As %String, context As %DynamicObject, Output movements As %DynamicArray, Output reasoning As %String) As %Status
{
    set movements = ##class(%DynamicArray).%New(), reasoning = "", result = $$$OK
    try {
        set json = ##class(BronzeWars.AI.DeploymentCommander).CleanJSON(content)
        set answer = ##class(%DynamicObject).%FromJSON(json)
        if answer.%GetTypeOf("choices") '= "array" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI Hub response has no choices array"))
        if answer.choices.%Size() '= context.aiUnits.%Size() throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI Hub response has an unexpected unit count"))

        set sc = ##class(BronzeWars.AI.MovementRecommendationGenerator).Generate(context, .recommendations)
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        kill recommendationById, seen
        for index = 0:1:(recommendations.%Size() - 1) {
            set recommendation = recommendations.%Get(index), recommendationById(recommendation.unitId _ "") = recommendation
        }
        set offensiveCount = 0, neutralCount = 0, defensiveCount = 0
        for index = 0:1:(answer.choices.%Size() - 1) {
            set choice = answer.choices.%Get(index)
            if ('$isobject(choice)) ! (choice.%Size() '= 2) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid AI Hub movement choice"))
            set unitId = choice.%Get(0) _ "", stance = $zconvert(choice.%Get(1), "U")
            if '$data(recommendationById(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown unit in AI Hub movement choice"))
            if $data(seen(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated unit in AI Hub movement choice"))
            if (stance '= "O") && (stance '= "N") && (stance '= "D") throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Unknown AI Hub movement stance"))
            set stanceById(unitId) = stance, seen(unitId) = 1
            if stance = "O" set offensiveCount = offensiveCount + 1
            if stance = "N" set neutralCount = neutralCount + 1
            if stance = "D" set defensiveCount = defensiveCount + 1
        }
        set sc = ##class(BronzeWars.AI.DeterministicMovementGenerator).Generate(context, .executionOrder)
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        for index = 0:1:(executionOrder.%Size() - 1) {
            set orderedUnit = executionOrder.%Get(index), unitId = orderedUnit.unitId _ "", recommendation = recommendationById(unitId), destination = recommendation.%Get(stanceById(unitId))
            do movements.%Push({"unitId":(+unitId),"x":(destination.x),"y":(destination.y)})
        }
        set validationAnswer = {"movements":(movements),"reasoning":"AI Hub tool choices"}
        set sc = ..ParseAndValidate(validationAnswer.%ToJSON(), context, .validated, .ignoredReasoning)
        if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
        set movements = validated
        set reasoning = "AI Hub eligio " _ offensiveCount _ " movimientos ofensivos, " _ neutralCount _ " neutrales y " _ defensiveCount _ " defensivos a partir de recomendaciones validadas."
    } catch exception {
        set result = exception.AsStatus()
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
