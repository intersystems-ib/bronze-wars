Class BronzeWars.AI.MovementRecommendationGenerator Extends %RegisteredObject
{

ClassMethod Generate(context As %DynamicObject, Output recommendations As %DynamicArray) As %Status
{
    set recommendations = ##class(%DynamicArray).%New()
    set sc = ##class(BronzeWars.AI.DeterministicMovementGenerator).Generate(context, .offensive)
    if $SYSTEM.Status.IsError(sc) return sc
    set sc = ..GenerateDefensive(context, .defensive)
    if $SYSTEM.Status.IsError(sc) return sc

    kill offensiveById, defensiveById, originalOccupied
    for index = 0:1:(context.humanUnits.%Size() - 1) {
        set unit = context.humanUnits.%Get(index), originalOccupied(unit.x _ "," _ unit.y) = unit.unitId
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), originalOccupied(unit.x _ "," _ unit.y) = unit.unitId
    }
    for index = 0:1:(offensive.%Size() - 1) {
        set movement = offensive.%Get(index), offensiveById(movement.unitId _ "") = movement
    }
    for index = 0:1:(defensive.%Size() - 1) {
        set movement = defensive.%Get(index), defensiveById(movement.unitId _ "") = movement
    }
    set offensiveLineBlocked = 0
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), unitId = unit.unitId _ ""
        continue:'##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code)
        set offensiveMove = offensiveById(unitId), target = offensiveMove.x _ "," _ offensiveMove.y
        if $data(originalOccupied(target)), (originalOccupied(target) '= unit.unitId) set offensiveLineBlocked = 1
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), unitId = unit.unitId _ ""
        set offensiveMove = offensiveById(unitId), defensiveMove = defensiveById(unitId)
        if offensiveLineBlocked, ##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code) set offensiveMove = {"x":(unit.x),"y":(unit.y)}
        do recommendations.%Push({"unitId":(unit.unitId),"code":(unit.code),"O":{"x":(offensiveMove.x),"y":(offensiveMove.y)},"N":{"x":(unit.x),"y":(unit.y)},"D":{"x":(defensiveMove.x),"y":(defensiveMove.y)}})
    }
    return $$$OK
}

ClassMethod Compact(context As %DynamicObject, Output compact As %DynamicObject) As %Status
{
    set compact = {"legend":{"O":"ofensivo","N":"neutral","D":"defensivo"},"units":(##class(%DynamicArray).%New())}
    set sc = ..Generate(context, .recommendations)
    if $SYSTEM.Status.IsError(sc) return sc
    for index = 0:1:(recommendations.%Size() - 1) {
        set recommendation = recommendations.%Get(index)
        set entry = ##class(%DynamicArray).%New()
        do entry.%Push(+(recommendation.unitId)), entry.%Push(recommendation.code)
        for stance = "O","N","D" {
            set destination = recommendation.%Get(stance), point = ##class(%DynamicArray).%New()
            do point.%Push(destination.x), point.%Push(destination.y), entry.%Push(point)
        }
        do compact.units.%Push(entry)
    }
    return $$$OK
}

ClassMethod GenerateDefensive(context As %DynamicObject, Output movements As %DynamicArray) As %Status [ Private ]
{
    set movements = ##class(%DynamicArray).%New()
    kill occupied, originalOccupied, planned
    for index = 0:1:(context.humanUnits.%Size() - 1) {
        set unit = context.humanUnits.%Get(index), occupied(unit.x _ "," _ unit.y) = unit.unitId, originalOccupied(unit.x _ "," _ unit.y) = unit.unitId
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), occupied(unit.x _ "," _ unit.y) = unit.unitId, originalOccupied(unit.x _ "," _ unit.y) = unit.unitId
    }

    set lineCanRetreat = 1
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index)
        continue:'##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code)
        if (unit.remainingMovement<1) ! (unit.y<1) ! $data(occupied(unit.x _ "," _ (unit.y-1))) set lineCanRetreat = 0
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index)
        continue:'##class(BronzeWars.AI.DeploymentCommander).IsMainLineCode(unit.code)
        set x = unit.x, y = unit.y
        if lineCanRetreat {
            kill occupied(x _ "," _ y)
            set y = y - 1, occupied(x _ "," _ y) = unit.unitId
        }
        set planned(unit.unitId _ "") = {"unitId":(unit.unitId),"x":(x),"y":(y)}
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index), unitId = unit.unitId _ ""
        continue:$data(planned(unitId))
        set x = unit.x, y = unit.y
        kill occupied(x _ "," _ y)
        for step = 1:1:unit.remainingMovement {
            set nextY = y - 1
            quit:(nextY<0)!$data(occupied(x _ "," _ nextY))!$data(originalOccupied(x _ "," _ nextY))
            set y = nextY
        }
        set occupied(x _ "," _ y) = unit.unitId
        set planned(unitId) = {"unitId":(unit.unitId),"x":(x),"y":(y)}
    }
    for index = 0:1:(context.aiUnits.%Size() - 1) {
        set unit = context.aiUnits.%Get(index)
        do movements.%Push(planned(unit.unitId _ ""))
    }
    return $$$OK
}

}
