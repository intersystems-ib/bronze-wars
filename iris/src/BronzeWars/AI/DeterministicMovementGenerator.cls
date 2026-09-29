Class BronzeWars.AI.DeterministicMovementGenerator Extends %RegisteredObject
{

ClassMethod Generate(context As %DynamicObject, Output movements As %DynamicArray, strategy As %String = "TACTICAL") As %Status
{
    set movements = ##class(%DynamicArray).%New()
    set strategy = $zconvert(strategy, "U")
    if strategy = "REGROUP" return ..GenerateRegroup(context, .movements)
    if strategy = "ADVANCE" return ..GenerateAdvance(context, .movements)
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

ClassMethod GenerateAdvance(context As %DynamicObject, Output movements As %DynamicArray) As %Status [ Private ]
{
    set movements = ##class(%DynamicArray).%New()
    kill occupied, planned
    for index = 0:1:(context.humanUnits.%Size() - 1) {
        set unit = context.humanUnits.%Get(index), occupied(unit.x _ "," _ unit.y) = unit.unitId
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), occupied(unit.x _ "," _ unit.y) = unit.unitId
    }

    // Move the front ranks first so following units can occupy the cells they vacate.
    for row = (context.board.height-1):-1:0 {
        for index = 0:1:(context.aiUnits.%Size() - 1) {
            set unit = context.aiUnits.%Get(index)
            continue:(unit.y'=row)
            set x = unit.x, y = unit.y
            kill occupied(x _ "," _ y)
            // Projectile units use their mobility to enter range. The rest of
            // the army advances one cell so the main formation remains intact.
            set projectileUnit = (unit.code="LIGHT_INFANTRY") ! (unit.code="LIGHT_CAVALRY") ! (unit.code="CHARIOTS") ! (unit.code="ARCHERS")
            if projectileUnit, (unit.attackRange>1) {
                set nearestAdvance = ..NearestHumanDistance(x, y, context)
                set advanceDistance = nearestAdvance - unit.attackRange
                if advanceDistance < 0 set advanceDistance = 0
                if advanceDistance > unit.remainingMovement set advanceDistance = unit.remainingMovement
                for advanceStep = 1:1:advanceDistance {
                    set nextY = y + 1
                    quit:(nextY>=context.board.height)!$data(occupied(x _ "," _ nextY))
                    set y = nextY
                }
            } else {
                for step = 1:1:$select(unit.remainingMovement>0:1, 1:0) {
                    set nextY = y + 1
                    quit:(nextY>=context.board.height)!$data(occupied(x _ "," _ nextY))
                    set y = nextY
                }
            }
            set occupied(x _ "," _ y) = unit.unitId
            set planned(unit.unitId _ "") = 1
            do movements.%Push({"unitId":(unit.unitId),"x":(x),"y":(y)})
        }
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index)
        if '$data(planned(unit.unitId _ "")) do movements.%Push({"unitId":(unit.unitId),"x":(unit.x),"y":(unit.y)})
    }
    return $$$OK
}

ClassMethod GenerateRegroup(context As %DynamicObject, Output movements As %DynamicArray) As %Status [ Private ]
{
    set movements = ##class(%DynamicArray).%New(), count = context.aiUnits.%Size()
    if count = 0 return $$$OK
    set totalX = 0, totalY = 0
    kill occupied
    for index = 0:1:(context.humanUnits.%Size() - 1) {
        set unit = context.humanUnits.%Get(index), occupied(unit.x _ "," _ unit.y) = unit.unitId
    }
    for index = 0:1:(count - 1) {
        set unit = context.aiUnits.%Get(index)
        set totalX = totalX + unit.x, totalY = totalY + unit.y
        set occupied(unit.x _ "," _ unit.y) = unit.unitId
    }
    set centerX = $justify(totalX / count, 0, 0), centerY = $justify(totalY / count, 0, 0)

    for index = 0:1:(count - 1) {
        set unit = context.aiUnits.%Get(index), x = unit.x, y = unit.y
        kill occupied(x _ "," _ y)
        set distanceX = centerX - x, distanceY = centerY - y
        set absoluteX = distanceX if absoluteX < 0 set absoluteX = -absoluteX
        set absoluteY = distanceY if absoluteY < 0 set absoluteY = -absoluteY
        if absoluteX >= absoluteY {
            do ..MoveOnAxis(.x, .y, centerX, "X", unit.remainingMovement, context, .occupied)
            if (x=unit.x), (y=unit.y) do ..MoveOnAxis(.x, .y, centerY, "Y", unit.remainingMovement, context, .occupied)
        } else {
            do ..MoveOnAxis(.x, .y, centerY, "Y", unit.remainingMovement, context, .occupied)
            if (x=unit.x), (y=unit.y) do ..MoveOnAxis(.x, .y, centerX, "X", unit.remainingMovement, context, .occupied)
        }
        set occupied(x _ "," _ y) = unit.unitId
        do movements.%Push({"unitId":(unit.unitId),"x":(x),"y":(y)})
    }
    return $$$OK
}

ClassMethod MoveOnAxis(ByRef x As %Integer, ByRef y As %Integer, target As %Integer, axis As %String, available As %Integer, context As %DynamicObject, ByRef occupied) [ Private ]
{
    set current = $select(axis="X":x, 1:y)
    if current = target return
    set direction = $select(target<current:-1, 1:1)
    for step = 1:1:available {
        set nextX = x, nextY = y
        if axis = "X" set nextX = x + direction
        if axis = "Y" set nextY = y + direction
        quit:(nextX<0)!(nextX>=context.board.width)!(nextY<0)!(nextY>=context.board.height)!$data(occupied(nextX _ "," _ nextY))
        set x = nextX, y = nextY, current = current + direction
        quit:current=target
    }
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
