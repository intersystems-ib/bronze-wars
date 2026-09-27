Class BronzeWars.AI.DeterministicMovementGenerator Extends %RegisteredObject
{

ClassMethod Generate(context As %DynamicObject, Output movements As %DynamicArray) As %Status
{
    set movements = ##class(%DynamicArray).%New()
    kill occupied, planned
    for index = 0:1:(context.humanUnits.%Size() - 1) {
        set unit = context.humanUnits.%Get(index), occupied(unit.x _ "," _ unit.y) = unit.unitId
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), occupied(unit.x _ "," _ unit.y) = unit.unitId
    }

    for pass = 1:1:2 {
        for index = 0:1:(context.aiUnits.%Size() - 1) {
            set unit = context.aiUnits.%Get(index), code = unit.code
            set matches = 0
            if pass = 1 set matches = (code="LIGHT_INFANTRY") ! (code="LIGHT_CAVALRY") ! (code="CHARIOTS") ! (code="ARCHERS")
            if pass = 2 set matches = (code="HEAVY_CAVALRY")
            continue:'matches
            set x = unit.x, y = unit.y
            kill occupied(x _ "," _ y)
            if pass = 1 {
                do ..AdvanceProjectileUnit(unit, context, .occupied, .x, .y)
            }
            if pass = 2 do ..AdvanceHeavyCavalry(unit, context, .occupied, .x, .y)
            set occupied(x _ "," _ y) = unit.unitId, planned(unit.unitId _ "") = {"unitId":(unit.unitId),"x":(x),"y":(y)}
            do movements.%Push(planned(unit.unitId _ ""))
        }
        if pass = 1 do ..AdvanceMainLine(context, .occupied, .planned, movements)
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), unitId = unit.unitId _ ""
        if '$data(planned(unitId)) {
            set planned(unitId) = {"unitId":(unit.unitId),"x":(unit.x),"y":(unit.y)}
            do movements.%Push(planned(unitId))
        }
    }
    return $$$OK
}

ClassMethod AdvanceProjectileUnit(unit As %DynamicObject, context As %DynamicObject, ByRef occupied, Output x As %Integer, Output y As %Integer) [ Private ]
{
    set x = unit.x, y = unit.y, nearest = ..NearestHumanDistance(x, y, context), steps = 0
    if context.commanderType = ##class(BronzeWars.AI.Commanders.Strategy).#SKIRMISHER, nearest <= 1 {
        for step = 1:1:unit.remainingMovement {
            set nextY = y - 1
            quit:(nextY<0)!$data(occupied(x _ "," _ nextY))
            set y = nextY, nearest = ..NearestHumanDistance(x, y, context)
            quit:nearest>1
        }
        return
    }
    for {
        quit:(steps>=unit.remainingMovement)!(nearest<=unit.attackRange)
        set nextY = y + 1
        quit:(nextY>=context.board.height)!$data(occupied(x _ "," _ nextY))
        set y = nextY, steps = steps + 1, nearest = ..NearestHumanDistance(x, y, context)
    }
}

ClassMethod AdvanceMainLine(context As %DynamicObject, ByRef occupied, ByRef planned, movements As %DynamicArray) [ Private ]
{
    set canAdvance = 1
    if context.commanderType = ##class(BronzeWars.AI.Commanders.Strategy).#SKIRMISHER set canAdvance = 0
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index)
        continue:'##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code)
        if (unit.remainingMovement<1) ! ((unit.y+1)>=context.board.height) ! $data(occupied(unit.x _ "," _ (unit.y+1))) set canAdvance = 0
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index)
        continue:'##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code)
        set x = unit.x, y = unit.y
        if canAdvance {
            kill occupied(x _ "," _ y)
            set y = y + 1, occupied(x _ "," _ y) = unit.unitId
        }
        set planned(unit.unitId _ "") = {"unitId":(unit.unitId),"x":(x),"y":(y)}
        do movements.%Push(planned(unit.unitId _ ""))
    }
}

ClassMethod AdvanceHeavyCavalry(unit As %DynamicObject, context As %DynamicObject, ByRef occupied, Output x As %Integer, Output y As %Integer) [ Private ]
{
    set x = unit.x, y = unit.y, leftDistance = x - context.humanFormation.minX, rightDistance = context.humanFormation.maxX - x
    if leftDistance < 0 set leftDistance = -leftDistance
    if rightDistance < 0 set rightDistance = -rightDistance
    set targetX = $select(leftDistance<=rightDistance:context.humanFormation.minX, 1:context.humanFormation.maxX)
    if x '= targetX {
        set direction = $select(targetX<x:-1, 1:1)
        for step = 1:1:unit.remainingMovement {
            set nextX = x + direction
            quit:(nextX<0)!(nextX>=context.board.width)!$data(occupied(nextX _ "," _ y))
            set x = nextX
            quit:x=targetX
        }
    } else {
        for step = 1:1:unit.remainingMovement {
            set nextY = y + 1
            quit:(nextY>=context.board.height)!$data(occupied(x _ "," _ nextY))
            set y = nextY
        }
    }
}

ClassMethod NearestHumanDistance(x As %Integer, y As %Integer, context As %DynamicObject) As %Integer [ Private ]
{
    set nearest = context.board.width + context.board.height
    for index = 0:1:(context.humanUnits.%Size() - 1) {
        set enemy = context.humanUnits.%Get(index), dx = enemy.x - x, dy = enemy.y - y
        if dx < 0 set dx = -dx
        if dy < 0 set dy = -dy
        set distance = dx + dy
        if distance < nearest set nearest = distance
    }
    return nearest
}

}
