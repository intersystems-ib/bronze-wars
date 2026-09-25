Class BronzeWars.Operation.DataOperation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "";
Parameter INVOCATION = "Queue";

Method Handle(pRequest As BronzeWars.Message.Request, Output pResponse As BronzeWars.Message.Response) As %Status
{
    set result = ""
    try {
        set payload = pRequest.Payload()
        if pRequest.Action = "LIST_UNIT_TYPES" {
            set result = ..ListUnitTypes()
        } elseif pRequest.Action = "CREATE_BATTLE" {
            set result = ..CreateBattle(payload)
        } elseif pRequest.Action = "GET_BATTLE" {
            set result = ..GetBattle(payload.battleId)
        } elseif pRequest.Action = "GET_DEPLOYMENT" {
            set result = ..GetDeployment(payload.battleId)
        } elseif pRequest.Action = "PLACE_UNIT" {
            set result = ..PlaceUnit(payload.battleId, payload.unitId, payload.x, payload.y)
        } elseif pRequest.Action = "START_BATTLE" {
            set result = ..StartBattle(payload.battleId, pRequest.SimulateFailure, payload.placements, payload.deploymentSource, payload.deploymentReasoning)
        } elseif pRequest.Action = "MOVE_UNIT" {
            set result = ..MoveUnit(payload.battleId, payload.unitId, payload.x, payload.y)
        } elseif pRequest.Action = "NEXT_TURN" {
            set result = ..NextTurn(payload.battleId, payload.confirmIncomplete, payload.aiMovements, payload.movementSource, payload.movementReasoning)
        } elseif pRequest.Action = "PREPARE_AI_MOVEMENT" {
            set result = ..PrepareAIMovement(payload.battleId, payload.confirmIncomplete)
        } elseif pRequest.Action = "PREPARE_AI_DEPLOYMENT" {
            set result = ..PrepareAIDeployment(payload.battleId)
        } elseif pRequest.Action = "CREATE_AI_UNITS" {
            set result = ..CreateAIUnits(payload.battleId, payload.composition, payload.compositionSource, payload.compositionReasoning)
        } else {
            set result = ##class(BronzeWars.Service.Result).Error(500, "UNSUPPORTED_ACTION", "La operacion solicitada no esta configurada.")
        }
    } catch exception {
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    set pResponse = ##class(BronzeWars.Message.Response).FromResult(result)
    return $$$OK
}

Method ListUnitTypes() As %DynamicObject [ Private ]
{
    set data = {"items":(##class(%DynamicArray).%New())}
    &sql(DECLARE ActiveTypeCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.UnitType WHERE Active = 1 ORDER BY Code)
    &sql(OPEN ActiveTypeCursor)
    for {
        &sql(FETCH ActiveTypeCursor INTO :unitTypeId)
        quit:(SQLCODE'=0)
        set unitType = ##class(BronzeWars.Model.UnitType).%OpenId(unitTypeId)
        do data.items.%Push(##class(BronzeWars.API.Serializer).UnitType(unitType))
    }
    &sql(CLOSE ActiveTypeCursor)
    return ##class(BronzeWars.Service.Result).Success(200, data)
}

Method CreateBattle(input As %DynamicObject) As %DynamicObject [ Private ]
{
    set width = input.boardWidth, height = input.boardHeight, name = input.name, humanFaction = input.faction
    set aiFaction = $select(humanFaction="EGYPTIAN":"ASSYRIAN", 1:"EGYPTIAN")

    tstart
    set result = ""
    try {
        set battle = ##class(BronzeWars.Model.Battle).%New()
        set battle.Name = name
        set battle.BoardWidth = width
        set battle.BoardHeight = height
        set sc = battle.%Save()
        $$$ThrowOnError(sc)

        set humanArmy = ..CreateArmy(battle, "HUMAN", humanFaction, "Ejército humano", .sc)
        $$$ThrowOnError(sc)
        set aiArmy = ..CreateArmy(battle, "AI", aiFaction, "Ejército de la IA", .sc)
        $$$ThrowOnError(sc)

        set sc = ..CreateUnits(battle, humanArmy, input.units)
        $$$ThrowOnError(sc)

        set sc = ..RecordEvent(battle, "BATTLE_CREATED", {"board":{"width":(width),"height":(height)}})
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(201, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle))})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method MoveUnit(battleId As %String, unitId As %String, x As %Integer, y As %Integer) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if (battle.Status '= "IN_PROGRESS") ! (battle.Phase '= "MOVEMENT") return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no esta en fase de movimiento.")

    set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(unit) return ##class(BronzeWars.Service.Result).Error(404, "UNIT_NOT_FOUND", "La unidad no existe.")
    if unit.Battle.%Id() '= battle.%Id() return ##class(BronzeWars.Service.Result).Error(422, "UNIT_NOT_IN_BATTLE", "La unidad no pertenece a la batalla indicada.")
    if unit.Army.Side '= "HUMAN" return ##class(BronzeWars.Service.Result).Error(422, "NOT_HUMAN_UNIT", "Solo se pueden mover unidades humanas.")
    if ('unit.Active) ! ('unit.IsDeployed) return ##class(BronzeWars.Service.Result).Error(422, "UNIT_CANNOT_MOVE", "La unidad no esta activa y desplegada.")

    set speed = unit.UnitType.Speed
    if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed
    set movementSpent = $select(unit.MovementSpent="":0, 1:unit.MovementSpent)
    if movementSpent >= speed return ##class(BronzeWars.Service.Result).Error(409, "MOVEMENT_EXHAUSTED", "La unidad ha agotado su movimiento en este turno.")
    if (x < 0) ! (x >= battle.BoardWidth) ! (y < 0) ! (y >= battle.BoardHeight) return ##class(BronzeWars.Service.Result).Error(422, "POSITION_OUT_OF_BOUNDS", "La posicion esta fuera del tablero.")

    set deltaX = x - unit.PositionX, deltaY = y - unit.PositionY
    set distanceX = deltaX if distanceX < 0 set distanceX = -distanceX
    set distanceY = deltaY if distanceY < 0 set distanceY = -distanceY
    set distance = distanceX + distanceY
    if (distance = 0) ! ((distanceX > 0) && (distanceY > 0)) return ##class(BronzeWars.Service.Result).Error(422, "INVALID_MOVEMENT_STEP", "El movimiento debe ser en linea recta horizontal o vertical.")
    if (movementSpent + distance) > speed return ##class(BronzeWars.Service.Result).Error(409, "MOVEMENT_EXHAUSTED", "La unidad no dispone de movimiento suficiente para llegar a esa casilla.")

    set stepX = $select(deltaX<0:-1, deltaX>0:1, 1:0)
    set stepY = $select(deltaY<0:-1, deltaY>0:1, 1:0)
    for step = 1:1:distance {
        set pathX = unit.PositionX + (step * stepX), pathY = unit.PositionY + (step * stepY)
        &sql(SELECT COUNT(*) INTO :occupied FROM BronzeWars_Model.BattleUnit WHERE Battle = :battleId AND Active = 1 AND IsDeployed = 1 AND PositionX = :pathX AND PositionY = :pathY AND %ID <> :unitId)
        if occupied > 0 return ##class(BronzeWars.Service.Result).Error(409, "CELL_OCCUPIED", "Hay una unidad bloqueando el recorrido.")
    }

    set previous = {"x":(unit.PositionX),"y":(unit.PositionY)}
    tstart
    set result = ""
    try {
        set unit.PositionX = x, unit.PositionY = y
        set unit.MovementSpent = movementSpent + distance, unit.HasMoved = 1
        set sc = unit.%Save()
        $$$ThrowOnError(sc)
        set remaining = speed - unit.MovementSpent
        set sc = ..RecordEvent(battle, "UNIT_MOVED", {"previous":(previous),"current":{"x":(x),"y":(y)},"movementSpent":(unit.MovementSpent),"remainingMovement":(remaining)}, unit)
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(200, {"unit":(##class(BronzeWars.API.Serializer).BattleUnit(unit))})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method PrepareAIMovement(battleId As %String, confirmIncomplete As %Boolean) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if (battle.Status '= "IN_PROGRESS") ! (battle.Phase '= "MOVEMENT") return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no esta en fase de movimiento.")

    &sql(SELECT COUNT(*) INTO :pendingUnits FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.Army a ON u.Army = a.%ID WHERE u.Battle = :battleId AND u.Active = 1 AND u.IsDeployed = 1 AND u.HasMoved = 0 AND a.Side = 'HUMAN')
    if (pendingUnits > 0), ('confirmIncomplete) {
        set details = {"pendingUnits":(pendingUnits)}
        return ##class(BronzeWars.Service.Result).Error(409, "UNITS_PENDING_MOVEMENT", "Quedan unidades sin mover.", details)
    }

    set sc = ##class(BronzeWars.AI.MovementContext).Build(battleId, .context)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    return ##class(BronzeWars.Service.Result).Success(200, context)
}

Method NextTurn(battleId As %String, confirmIncomplete As %Boolean, aiMovements As %DynamicArray, movementSource As %String, movementReasoning As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if (battle.Status '= "IN_PROGRESS") ! (battle.Phase '= "MOVEMENT") return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no esta en fase de movimiento.")
    if '$isobject(aiMovements) return ##class(BronzeWars.Service.Result).Error(500, "AI_MOVEMENT_FAILED", "No se ha recibido el movimiento de la IA.")

    &sql(SELECT COUNT(*) INTO :pendingUnits FROM BronzeWars_Model.BattleUnit u JOIN BronzeWars_Model.Army a ON u.Army = a.%ID WHERE u.Battle = :battleId AND u.Active = 1 AND u.IsDeployed = 1 AND u.HasMoved = 0 AND a.Side = 'HUMAN')
    if (pendingUnits > 0), ('confirmIncomplete) return ##class(BronzeWars.Service.Result).Error(409, "UNITS_PENDING_MOVEMENT", "Quedan unidades sin mover.", {"pendingUnits":(pendingUnits)})

    set previousRound = battle.CurrentRound
    set movementTrace = ##class(%DynamicArray).%New()
    tstart
    set result = ""
    try {
        set sc = ..RecordEvent(battle, "AI_MOVEMENT_PLANNED", {"source":(movementSource),"reasoning":(movementReasoning),"movements":(aiMovements)})
        $$$ThrowOnError(sc)
        kill movedUnits
        for index = 0:1:(aiMovements.%Size() - 1) {
            set movement = aiMovements.%Get(index), unitId = movement.unitId _ ""
            if $data(movedUnits(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated AI movement"))
            set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, 4, .sc)
            $$$ThrowOnError(sc)
            if ('$isobject(unit)) ! (unit.Battle.%Id() '= battleId) ! (unit.Army.Side '= "AI") ! ('unit.Active) ! ('unit.IsDeployed) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid AI movement unit"))
            set speed = unit.UnitType.Speed
            if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed
            set x = movement.x, y = movement.y, deltaX = x - unit.PositionX, deltaY = y - unit.PositionY, distanceX = deltaX, distanceY = deltaY
            if distanceX < 0 set distanceX = -distanceX
            if distanceY < 0 set distanceY = -distanceY
            set distance = distanceX + distanceY
            if (x<0) ! (x>=battle.BoardWidth) ! (y<0) ! (y>=battle.BoardHeight) ! ((distanceX>0)&&(distanceY>0)) ! (distance>speed) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid AI movement destination"))
            set stepX = $select(deltaX<0:-1, deltaX>0:1, 1:0), stepY = $select(deltaY<0:-1, deltaY>0:1, 1:0)
            set path = ##class(%DynamicArray).%New()
            for step = 1:1:distance {
                set pathX = unit.PositionX + (step * stepX), pathY = unit.PositionY + (step * stepY)
                &sql(SELECT COUNT(*) INTO :occupied FROM BronzeWars_Model.BattleUnit WHERE Battle = :battleId AND Active = 1 AND IsDeployed = 1 AND PositionX = :pathX AND PositionY = :pathY AND %ID <> :unitId)
                if occupied > 0 throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI movement path is occupied"))
                do path.%Push({"x":(pathX),"y":(pathY)})
            }
            set previous = {"x":(unit.PositionX),"y":(unit.PositionY)}
            if distance > 0 {
                set unit.PositionX = x, unit.PositionY = y, unit.MovementSpent = distance, unit.HasMoved = 1
                set sc = unit.%Save()
                $$$ThrowOnError(sc)
                set sc = ..RecordEvent(battle, "UNIT_MOVED", {"previous":(previous),"current":{"x":(x),"y":(y)},"movementSpent":(distance),"remainingMovement":(speed-distance),"controlledBy":"AI"}, unit)
                $$$ThrowOnError(sc)
                do movementTrace.%Push({"unitId":(unitId),"from":(previous),"to":{"x":(x),"y":(y)},"path":(path)})
            }
            set movedUnits(unitId) = 1
        }
        set aiArmy = ..FindArmy(battleId, "AI"), aiArmyId = aiArmy.%Id()
        &sql(SELECT COUNT(*) INTO :expectedAIMovements FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1 AND IsDeployed = 1)
        if aiMovements.%Size() '= expectedAIMovements throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete AI movement plan"))
        &sql(UPDATE BronzeWars_Model.BattleUnit SET HasMoved = 0, MovementSpent = 0 WHERE Battle = :battleId AND Active = 1)
        if SQLCODE < 0 {
            set sc = $$$ERROR($$$GeneralError, "Unable to reset unit movement: " _ SQLCODE _ " " _ $get(%msg))
            $$$ThrowOnError(sc)
        }
        set battle.CurrentRound = previousRound + 1
        set sc = battle.%Save()
        $$$ThrowOnError(sc)
        set sc = ..RecordEvent(battle, "TURN_ADVANCED", {"previousRound":(previousRound),"currentRound":(battle.CurrentRound),"forced":(pendingUnits>0),"pendingUnits":(pendingUnits)})
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle)),"aiMovementTrace":(movementTrace)})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method GetBattle(battleId As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    set hideAI = (battle.Phase = "DEPLOYMENT")
    return ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle, hideAI))})
}

Method GetDeployment(battleId As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if battle.Phase '= "DEPLOYMENT" return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La fase de despliegue ha terminado.")
    return ##class(BronzeWars.Service.Result).Success(200, ##class(BronzeWars.API.Serializer).Deployment(battle))
}

Method PlaceUnit(battleId As %String, unitId As %String, x As %Integer, y As %Integer) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")

    set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(unit) return ##class(BronzeWars.Service.Result).Error(404, "UNIT_NOT_FOUND", "La unidad no existe.")
    if unit.Battle.%Id() '= battle.%Id() return ##class(BronzeWars.Service.Result).Error(422, "UNIT_NOT_IN_BATTLE", "La unidad no pertenece a la batalla indicada.")
    if unit.Army.Side '= "HUMAN" return ##class(BronzeWars.Service.Result).Error(422, "NOT_HUMAN_UNIT", "Solo se pueden colocar unidades humanas.")
    if (battle.Status '= "CREATED") ! (battle.Phase '= "DEPLOYMENT") return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no admite cambios de despliegue.")

    if '##class(BronzeWars.Rules.DeploymentValidator).ValidatePosition(battle, unit, x, y, "HUMAN", .code, .message, .details) {
        set status = $select(code="CELL_OCCUPIED":409, 1:422)
        return ##class(BronzeWars.Service.Result).Error(status, code, message, details)
    }

    set unchanged = unit.IsDeployed & (unit.PositionX = x) & (unit.PositionY = y)
    if unchanged {
        set ready = ##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(unit.Army)
        return ##class(BronzeWars.Service.Result).Success(200, {"unit":(##class(BronzeWars.API.Serializer).BattleUnit(unit)),"deploymentReady":(ready)})
    }

    if unit.IsDeployed {
        set previous = {"x":(unit.PositionX),"y":(unit.PositionY)}
    } else {
        set previous = ""
    }

    tstart
    set result = ""
    try {
        set unit.PositionX = x
        set unit.PositionY = y
        set unit.IsDeployed = 1
        set sc = unit.%Save()
        $$$ThrowOnError(sc)
        set payload = {"current":{"x":(x),"y":(y)}}
        if $isobject(previous) do payload.%Set("previous", previous)
        if '$isobject(previous) do payload.%Set("previous", "", "null")
        set sc = ..RecordEvent(battle, "UNIT_DEPLOYED", payload, unit)
        $$$ThrowOnError(sc)
        tcommit
        set ready = ##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(unit.Army)
        set result = ##class(BronzeWars.Service.Result).Success(200, {"unit":(##class(BronzeWars.API.Serializer).BattleUnit(unit)),"deploymentReady":(ready)})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method PrepareAIDeployment(battleId As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if battle.Status '= "CREATED" return ##class(BronzeWars.Service.Result).Error(409, "BATTLE_ALREADY_STARTED", "La batalla ya ha comenzado o ha finalizado.")
    if battle.Phase '= "DEPLOYMENT" return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no esta en fase de despliegue.")

    set humanArmy = ..FindArmy(battleId, "HUMAN"), aiArmy = ..FindArmy(battleId, "AI")
    if ('$isobject(humanArmy)) ! ('$isobject(aiArmy)) return ##class(BronzeWars.Service.Result).InternalError()
    if '##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(humanArmy) return ##class(BronzeWars.Service.Result).Error(422, "HUMAN_DEPLOYMENT_INCOMPLETE", "El despliegue humano no esta completo.")

    if aiArmy.CommanderType = "" {
        tstart
        try {
            set aiArmy.CommanderType = ##class(BronzeWars.AI.Commanders.Strategy).RandomType()
            set sc = aiArmy.%Save()
            $$$ThrowOnError(sc)
            set sc = ..RecordEvent(battle, "AI_COMMANDER_SELECTED", {"type":(aiArmy.CommanderType),"name":(##class(BronzeWars.AI.Commanders.Strategy).Label(aiArmy.CommanderType))})
            $$$ThrowOnError(sc)
            tcommit
        } catch exception {
            trollback 1
            return ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
        }
    }

    set humanArmyId = humanArmy.%Id(), humanPositions = ##class(%DynamicArray).%New()
    &sql(SELECT MIN(PositionX), MAX(PositionX) INTO :humanMinX, :humanMaxX FROM BronzeWars_Model.BattleUnit WHERE Army = :humanArmyId AND Active = 1 AND IsDeployed = 1)
    set humanFrontage = humanMaxX - humanMinX + 1
    &sql(DECLARE HumanFormationCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :humanArmyId AND Active = 1 AND IsDeployed = 1 ORDER BY PositionX, PositionY)
    &sql(OPEN HumanFormationCursor)
    for {
        &sql(FETCH HumanFormationCursor INTO :humanUnitId)
        quit:(SQLCODE'=0)
        set humanUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(humanUnitId)
        do humanPositions.%Push({"unitId":(humanUnitId),"code":(humanUnit.UnitType.Code),"x":(humanUnit.PositionX),"y":(humanUnit.PositionY)})
    }
    &sql(CLOSE HumanFormationCursor)

    set mainLineTarget = ##class(BronzeWars.AI.Commanders.Strategy).MainLineTarget(aiArmy.CommanderType, humanFrontage, battle.BoardWidth)
    set frontageTarget = ##class(BronzeWars.AI.Commanders.Strategy).FrontageTarget(aiArmy.CommanderType, humanFrontage, battle.BoardWidth)
    set context = {"battleId":(battleId),"commanderType":(aiArmy.CommanderType),"commanderName":(##class(BronzeWars.AI.Commanders.Strategy).Label(aiArmy.CommanderType)),"commanderDoctrine":(##class(BronzeWars.AI.Commanders.Strategy).Doctrine(aiArmy.CommanderType)),"board":{"width":(battle.BoardWidth),"height":(battle.BoardHeight),"aiRows":[0,1,2],"enemyDirection":"INCREASING_Y"},"grainBudget":(##class(BronzeWars.Rules.ArmyBudget).#TOTAL),"humanFormation":{"minX":(humanMinX),"maxX":(humanMaxX),"frontage":(humanFrontage),"positions":(humanPositions)},"formationDoctrine":{"mainLineTarget":(mainLineTarget),"frontageTarget":(frontageTarget),"mainLineRow":1},"unitTypes":(##class(%DynamicArray).%New()),"units":(##class(%DynamicArray).%New()),"doctrineVersion":"COMMANDER_ARCHETYPES_V2"}
    &sql(DECLARE AIUnitTypeCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.UnitType WHERE Active = 1 ORDER BY Code)
    &sql(OPEN AIUnitTypeCursor)
    for {
        &sql(FETCH AIUnitTypeCursor INTO :unitTypeId)
        quit:(SQLCODE'=0)
        set unitType = ##class(BronzeWars.Model.UnitType).%OpenId(unitTypeId)
        do context.unitTypes.%Push(##class(BronzeWars.API.Serializer).UnitType(unitType, 1, aiArmy.Faction))
    }
    &sql(CLOSE AIUnitTypeCursor)
    set aiArmyId = aiArmy.%Id()
    &sql(DECLARE AIContextCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1 ORDER BY UnitType, %ID)
    &sql(OPEN AIContextCursor)
    for {
        &sql(FETCH AIContextCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId)
        do context.units.%Push({"unitId":(unitId),"code":(unit.UnitType.Code),"name":(unit.Name)})
    }
    &sql(CLOSE AIContextCursor)
    return ##class(BronzeWars.Service.Result).Success(200, context)
}

Method CreateAIUnits(battleId As %String, composition As %DynamicArray, source As %String, reasoning As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if (battle.Status '= "CREATED") ! (battle.Phase '= "DEPLOYMENT") return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no admite la creacion del ejercito de la IA.")
    set humanArmy = ..FindArmy(battleId, "HUMAN"), aiArmy = ..FindArmy(battleId, "AI")
    if ('$isobject(humanArmy)) ! ('$isobject(aiArmy)) return ##class(BronzeWars.Service.Result).InternalError()
    if '##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(humanArmy) return ##class(BronzeWars.Service.Result).Error(422, "HUMAN_DEPLOYMENT_INCOMPLETE", "El despliegue humano no esta completo.")

    set aiArmyId = aiArmy.%Id()
    &sql(SELECT COUNT(*) INTO :existingUnits FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1)
    if existingUnits > 0 return ..PrepareAIDeployment(battleId)

    set sc = ##class(BronzeWars.Rules.ArmyBudget).ValidateComposition(composition, battle.BoardWidth * 3, .totalGrain, .totalUnits)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).Error(422, "INVALID_AI_COMPOSITION", "La composicion propuesta para la IA no es valida.")

    tstart
    set result = ""
    try {
        set sc = ..CreateUnits(battle, aiArmy, composition)
        $$$ThrowOnError(sc)
        set sc = ..RecordEvent(battle, "AI_ARMY_SELECTED", {"commanderType":(aiArmy.CommanderType),"source":(source),"reasoning":(reasoning),"grainSpent":(totalGrain),"unitCount":(totalUnits),"composition":(composition)})
        $$$ThrowOnError(sc)
        tcommit
        set result = ..PrepareAIDeployment(battleId)
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method StartBattle(battleId As %String, simulateFailure As %Boolean = 0, placements As %DynamicArray = "", deploymentSource As %String = "", deploymentReasoning As %String = "") As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if battle.Status '= "CREATED" return ##class(BronzeWars.Service.Result).Error(409, "BATTLE_ALREADY_STARTED", "La batalla ya ha comenzado o ha finalizado.")
    if battle.Phase '= "DEPLOYMENT" return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no esta en fase de despliegue.")

    set humanArmy = ..FindArmy(battleId, "HUMAN")
    set aiArmy = ..FindArmy(battleId, "AI")
    if ('$isobject(humanArmy)) ! ('$isobject(aiArmy)) return ##class(BronzeWars.Service.Result).InternalError()
    if '##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(humanArmy) return ##class(BronzeWars.Service.Result).Error(422, "HUMAN_DEPLOYMENT_INCOMPLETE", "El despliegue humano no esta completo.")

    if '$isobject(placements) return ##class(BronzeWars.Service.Result).Error(500, "AI_DEPLOYMENT_FAILED", "No se ha recibido un plan de despliegue para la IA.")
    set proposal = placements

    tstart
    set result = ""
    try {
        set sc = ..RecordEvent(battle, "AI_DEPLOYMENT_PLANNED", {"source":(deploymentSource),"reasoning":(deploymentReasoning)})
        $$$ThrowOnError(sc)
        for i = 0:1:(proposal.%Size() - 1) {
            set placement = proposal.%Get(i)
            set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(placement.unitId, 4, .sc)
            $$$ThrowOnError(sc)
            if '##class(BronzeWars.Rules.DeploymentValidator).ValidatePosition(battle, unit, placement.x, placement.y, "AI", .code, .message, .details) {
                throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI deployment validation failed"))
            }
            set unit.PositionX = placement.x
            set unit.PositionY = placement.y
            set unit.IsDeployed = 1
            set sc = unit.%Save()
            $$$ThrowOnError(sc)
            set sc = ..RecordEvent(battle, "UNIT_DEPLOYED", {"previous":null,"current":{"x":(placement.x),"y":(placement.y)}}, unit)
            $$$ThrowOnError(sc)
        }

        if '##class(BronzeWars.Rules.DeploymentValidator).IsArmyReady(aiArmy) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "AI deployment is incomplete"))

        if simulateFailure throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Simulated start failure"))

        set sc = ##class(BronzeWars.Rules.FormationMorale).Apply(battle, .moraleChanges)
        $$$ThrowOnError(sc)
        set sc = ..RecordEvent(battle, "FORMATION_MORALE_CALCULATED", {"changedUnits":(moraleChanges)})
        $$$ThrowOnError(sc)

        set previousPhase = battle.Phase
        set battle.Status = "IN_PROGRESS"
        set battle.Phase = "MOVEMENT"
        set battle.CurrentRound = 1
        set battle.StartedAt = $zdatetime($ztimestamp, 3, 1)
        set sc = battle.%Save()
        $$$ThrowOnError(sc)
        set sc = ..RecordEvent(battle, "BATTLE_STARTED")
        $$$ThrowOnError(sc)
        set sc = ..RecordEvent(battle, "PHASE_CHANGED", {"previous":(previousPhase),"current":"MOVEMENT"})
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle))})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method CreateArmy(battle As BronzeWars.Model.Battle, side As %String, faction As %String, name As %String, Output sc As %Status) As BronzeWars.Model.Army [ Private ]
{
    set army = ##class(BronzeWars.Model.Army).%New()
    set army.Battle = battle
    set army.Side = side
    set army.Faction = faction
    set army.Name = name
    set sc = army.%Save()
    return army
}

Method CreateUnits(battle As BronzeWars.Model.Battle, army As BronzeWars.Model.Army, composition As %DynamicArray) As %Status [ Private ]
{
    set sc = $$$OK
    for index = 0:1:(composition.%Size() - 1) {
        set selection = composition.%Get(index)
        set unitType = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(selection.code, .sc)
        quit:$SYSTEM.Status.IsError(sc)
        if '$isobject(unitType) return $$$ERROR($$$GeneralError, "Unknown unit type: " _ selection.code)
        set unitProfile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(unitType.%Id(), army.Faction, .sc)
        quit:$SYSTEM.Status.IsError(sc)
        if '$isobject(unitProfile) return $$$ERROR($$$GeneralError, "Unknown unit profile: " _ selection.code _ "/" _ army.Faction)
        for number = 1:1:selection.quantity {
            set unit = ##class(BronzeWars.Model.BattleUnit).%New(unitType, unitProfile)
            set unit.Battle = battle
            set unit.Army = army
            set unit.Name = unitType.Name
            if selection.quantity > 1 set unit.Name = unitType.Name _ " " _ number
            set sc = unit.%Save()
            quit:$SYSTEM.Status.IsError(sc)
        }
        quit:$SYSTEM.Status.IsError(sc)
    }
    return sc
}

Method FindArmy(battleId As %String, side As %String) As BronzeWars.Model.Army [ Private ]
{
    &sql(SELECT TOP 1 %ID INTO :armyId FROM BronzeWars_Model.Army WHERE Battle = :battleId AND Side = :side)
    if SQLCODE '= 0 return ""
    return ##class(BronzeWars.Model.Army).%OpenId(armyId)
}

Method RecordEvent(battle As BronzeWars.Model.Battle, eventType As %String, payload As %DynamicObject = "", actorUnit As BronzeWars.Model.BattleUnit = "", targetUnit As BronzeWars.Model.BattleUnit = "") As %Status [ Private ]
{
    set event = ##class(BronzeWars.Model.BattleEvent).%New()
    set event.Battle = battle
    set event.Round = battle.CurrentRound
    set event.Phase = battle.Phase
    set event.EventType = eventType
    if $isobject(actorUnit) set event.ActorUnit = actorUnit
    if $isobject(targetUnit) set event.TargetUnit = targetUnit
    if $isobject(payload) {
        set stream = ##class(%Stream.GlobalCharacter).%New()
        set sc = stream.Write(payload.%ToJSON())
        return:$SYSTEM.Status.IsError(sc) sc
        set event.Payload = stream
    }
    return event.%Save()
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="BronzeWars.Message.Request">
    <Method>Handle</Method>
  </MapItem>
</MapItems>
}

}
