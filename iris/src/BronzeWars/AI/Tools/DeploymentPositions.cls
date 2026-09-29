Class BronzeWars.AI.Tools.DeploymentPositions Extends %RegisteredObject
{

/// Description: Recommends deployment cells for one AI unit after loading the commander, enemy front and allied roster from the database.
ClassMethod RecommendDeploymentPositions(battleId As %String, unitId As %String) As %DynamicObject
{
    set result = {}, battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) {
        do result.%Set("error", $SYSTEM.Status.GetErrorText(sc))
        return result
    }
    if '$isobject(battle) {
        do result.%Set("error", "Battle not found")
        return result
    }

    set requestedUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, , .sc)
    if $SYSTEM.Status.IsError(sc) {
        do result.%Set("error", $SYSTEM.Status.GetErrorText(sc))
        return result
    }
    if ('$isobject(requestedUnit)) || (requestedUnit.Battle.%Id() '= battleId) || (requestedUnit.Army.Side '= "AI") {
        do result.%Set("error", "AI battle unit not found")
        return result
    }

    &sql(SELECT %ID, CommanderType INTO :aiArmyId, :commanderType FROM BronzeWars_Model.Army WHERE Battle = :battleId AND Side = 'AI')
    if SQLCODE '= 0 {
        do result.%Set("error", "AI army not found")
        return result
    }
    &sql(SELECT %ID INTO :humanArmyId FROM BronzeWars_Model.Army WHERE Battle = :battleId AND Side = 'HUMAN')
    if SQLCODE '= 0 {
        do result.%Set("error", "Human army not found")
        return result
    }

    &sql(SELECT MIN(PositionX), MAX(PositionX) INTO :humanMinX, :humanMaxX FROM BronzeWars_Model.BattleUnit WHERE Army = :humanArmyId AND Active = 1 AND IsDeployed = 1)
    if humanMinX = "" set humanMinX = 0
    if humanMaxX = "" set humanMaxX = battle.BoardWidth - 1
    set humanFrontage = humanMaxX - humanMinX + 1
    set mainLineTarget = ##class(BronzeWars.AI.Commanders.Strategy).MainLineTarget(commanderType, humanFrontage, battle.BoardWidth)
    set frontageTarget = ##class(BronzeWars.AI.Commanders.Strategy).FrontageTarget(commanderType, humanFrontage, battle.BoardWidth)
    set context = {
        "battleId":(battleId),
        "commanderType":(commanderType),
        "board":{"width":(battle.BoardWidth),"height":(battle.BoardHeight)},
        "humanFormation":{"minX":(humanMinX),"maxX":(humanMaxX),"frontage":(humanFrontage)},
        "formationDoctrine":{"mainLineTarget":(mainLineTarget),"frontageTarget":(frontageTarget),"mainLineRow":1},
        "units":(##class(%DynamicArray).%New())
    }

    set alliedDeployment = ##class(%DynamicArray).%New()
    &sql(DECLARE DeploymentUnitCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1 ORDER BY UnitType, %ID)
    &sql(OPEN DeploymentUnitCursor)
    for {
        &sql(FETCH DeploymentUnitCursor INTO :currentUnitId)
        quit:(SQLCODE'=0)
        set currentUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(currentUnitId)
        do context.units.%Push({"unitId":(currentUnitId),"code":(currentUnit.UnitType.Code),"name":(currentUnit.Name)})
        if currentUnit.IsDeployed do alliedDeployment.%Push({"unitId":(currentUnitId),"x":(currentUnit.PositionX),"y":(currentUnit.PositionY)})
    }
    &sql(CLOSE DeploymentUnitCursor)

    set sc = ##class(BronzeWars.AI.DeterministicDeploymentGenerator).GenerateFromContext(context, .plan)
    if $SYSTEM.Status.IsError(sc) {
        do result.%Set("error", $SYSTEM.Status.GetErrorText(sc))
        return result
    }

    set primary = "", occupied = ##class(%DynamicObject).%New()
    for index = 0:1:(plan.%Size() - 1) {
        set placement = plan.%Get(index)
        if (placement.unitId _ "") = (unitId _ "") {
            set primary = placement
        } else {
            do occupied.%Set(placement.x _ "," _ placement.y, 1)
        }
    }
    if '$isobject(primary) {
        do result.%Set("error", "Unit is not part of the AI deployment plan")
        return result
    }

    set options = ##class(%DynamicArray).%New()
    do options.%Push({"x":(primary.x),"y":(primary.y),"priority":1,"recommended":true,"reason":(..PositionReason(requestedUnit.UnitType.Code, commanderType, primary.y))})
    for distance = 1:1:battle.BoardWidth {
        quit:(options.%Size()>=3)
        for direction = -1:2:1 {
            set candidateX = primary.x + (distance * direction), candidateY = primary.y
            continue:(candidateX<0)||(candidateX>=battle.BoardWidth)
            continue:occupied.%IsDefined(candidateX _ "," _ candidateY)
            do occupied.%Set(candidateX _ "," _ candidateY, 1)
            do options.%Push({"x":(candidateX),"y":(candidateY),"priority":(options.%Size()+1),"recommended":false,"reason":"Alternative on the same doctrinal line"})
            quit:(options.%Size()>=3)
        }
    }

    set role = ..DeploymentRole(requestedUnit.UnitType.Code, commanderType, primary.y)
    set result = {
        "battleId":(battleId),
        "unitId":(+(unitId)),
        "unitType":(requestedUnit.UnitType.Code),
        "commanderType":(commanderType),
        "role":(role),
        "enemyFront":{"minX":(humanMinX),"maxX":(humanMaxX),"length":(humanFrontage)},
        "alliedDeployment":(alliedDeployment),
        "recommendedOptions":(options)
    }
    return result
}

ClassMethod DeploymentRole(code As %String, commanderType As %String, row As %Integer) As %String
{
    if ##class(BronzeWars.AI.DeploymentCommander).IsForwardLineCode(code) return "FORWARD_LINE"
    if ##class(BronzeWars.AI.DeterministicDeploymentGenerator).IsCavalryCode(code) return "FLANK"
    if row = 0 return "RESERVE"
    if ((commanderType = "FLANKER") || (commanderType = "AGGRESSIVE")), row = 1 return "EXTENDED_WING"
    return "SECOND_LINE"
}

ClassMethod PositionReason(code As %String, commanderType As %String, row As %Integer) As %String
{
    set role = ..DeploymentRole(code, commanderType, row)
    if role = "FORWARD_LINE" return "Forward screen closest to the enemy"
    if role = "FLANK" return "Cavalry protects a flank of the second line"
    if role = "RESERVE" return "Defensive or balanced reserve on the third line"
    if role = "EXTENDED_WING" return "Aggressive or flanking extension of the second line"
    return "Cohesive heavy infantry and spearmen second line"
}

}
