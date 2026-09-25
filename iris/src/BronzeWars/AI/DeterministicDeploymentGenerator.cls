Class BronzeWars.AI.DeterministicDeploymentGenerator Extends %RegisteredObject
{

ClassMethod Generate(battle As BronzeWars.Model.Battle, army As BronzeWars.Model.Army, Output proposal As %DynamicArray) As %Status
{
    set context = {"board":{"width":(battle.BoardWidth),"height":(battle.BoardHeight)},"units":(##class(%DynamicArray).%New())}
    set armyId = army.%Id()
    &sql(DECLARE AIUnitCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :armyId AND Active = 1 ORDER BY UnitType)
    &sql(OPEN AIUnitCursor)
    for {
        &sql(FETCH AIUnitCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId)
        do context.units.%Push({"unitId":(unitId),"code":(unit.UnitType.Code),"name":(unit.Name)})
    }
    &sql(CLOSE AIUnitCursor)
    return ..GenerateFromContext(context, .proposal)
}

ClassMethod GenerateFromContext(context As %DynamicObject, Output proposal As %DynamicArray) As %Status
{
    set proposal = ##class(%DynamicArray).%New(), width = context.board.width, count = context.units.%Size()
    if (width * 3) < count return $$$ERROR($$$GeneralError, "Not enough cells in the AI deployment zone")

    set lineCount = 0
    for index = 0:1:(count - 1) {
        if ##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(context.units.%Get(index).code) set lineCount = lineCount + 1
    }
    set requiredLine = $select(lineCount<width:lineCount, 1:width)
    if context.%IsDefined("humanFormation") set requiredLine = context.humanFormation.frontage
    if context.%IsDefined("formationDoctrine") set requiredLine = context.formationDoctrine.mainLineTarget
    if requiredLine > width set requiredLine = width
    if lineCount < requiredLine return $$$ERROR($$$GeneralError, "Not enough infantry or spearmen for a continuous AI front")
    set lineLength = $select(lineCount<width:lineCount, 1:width)
    set targetFrontage = (count + 2) \ 3
    if targetFrontage < lineLength set targetFrontage = lineLength
    if context.%IsDefined("formationDoctrine"), context.formationDoctrine.%IsDefined("frontageTarget"), (targetFrontage < context.formationDoctrine.frontageTarget) set targetFrontage = context.formationDoctrine.frontageTarget
    if targetFrontage > width set targetFrontage = width
    set formationCenter = (width - 1) / 2
    if context.%IsDefined("humanFormation") {
        set formationCenter = (context.humanFormation.minX + context.humanFormation.maxX) / 2
    }
    set formationStart = formationCenter - ((targetFrontage - 1) / 2)
    set formationStart = formationStart \ 1
    if formationStart < 0 set formationStart = 0
    if (formationStart + targetFrontage) > width set formationStart = width - targetFrontage
    set lineStart = formationStart + ((targetFrontage - lineLength) \ 2)

    set used = ##class(%DynamicObject).%New(), usedColumns = ##class(%DynamicObject).%New(), placed = ##class(%DynamicObject).%New(), result = $$$OK
    set lineIndex = 0
    for index = 0:1:(count - 1) {
        set unit = context.units.%Get(index)
        continue:'##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code)
        continue:(lineIndex>=lineLength)
        set x = lineStart + lineIndex, y = 1, lineIndex = lineIndex + 1
        do used.%Set(x _ "," _ y, 1), usedColumns.%Set(x, 1), placed.%Set(unit.unitId _ "", 1)
        do proposal.%Push({"unitId":(unit.unitId),"x":(x),"y":(y)})
    }
    for placementPass = 1:1:2 {
        for index = 0:1:(count - 1) {
            set unit = context.units.%Get(index)
            continue:placed.%IsDefined(unit.unitId _ "")
            set isFlanking = ##class(BronzeWars.AI.DeploymentCommander).IsFlankingCode(unit.code)
            continue:(placementPass=1)&&('isFlanking)
            continue:(placementPass=2)&&(isFlanking)
            set preferredRow = ..PreferredRow(unit.code)
            set preferFlanks = ..PreferFlanks(unit.code)
            set found = ..FindCell(formationStart, targetFrontage, preferredRow, preferFlanks, 0, used, usedColumns, .x, .y)
            if 'found {
                set result = $$$ERROR($$$GeneralError, "Unable to generate a complete AI deployment")
                quit
            }
            do used.%Set(x _ "," _ y, 1)
            do usedColumns.%Set(x, 1)
            do placed.%Set(unit.unitId _ "", 1)
            do proposal.%Push({"unitId":(unit.unitId),"x":(x),"y":(y)})
        }
        quit:$SYSTEM.Status.IsError(result)
    }
    return result
}

ClassMethod PreferredRow(code As %String) As %Integer [ Private ]
{
    if code = "ARCHERS" return 0
    if (code = "LIGHT_INFANTRY") ! (code = "CHARIOTS") return 2
    return 1
}

ClassMethod PreferFlanks(code As %String) As %Boolean [ Private ]
{
    return (code = "LIGHT_CAVALRY") ! (code = "HEAVY_CAVALRY") ! (code = "CHARIOTS")
}

ClassMethod FindCell(startX As %Integer, frontage As %Integer, preferredRow As %Integer, preferFlanks As %Boolean, spreadToMatchHuman As %Boolean, used As %DynamicObject, usedColumns As %DynamicObject, Output x As %Integer, Output y As %Integer) As %Boolean [ Private ]
{
    set found = 0
    for columnPass = 0:1:1 {
        quit:found
        for rowOffset = 0:1:2 {
            quit:found
            set y = (preferredRow + rowOffset) # 3
            for position = 0:1:(frontage - 1) {
                if preferFlanks ! spreadToMatchHuman {
                    if (position # 2) = 0 set x = startX + (position \ 2)
                    if (position # 2) = 1 set x = startX + frontage - 1 - (position \ 2)
                } else {
                    set x = startX + position
                }
                continue:(columnPass=0)&&usedColumns.%IsDefined(x)
                if 'used.%IsDefined(x _ "," _ y) {
                    set found = 1
                    quit
                }
            }
        }
    }
    return found
}

}
