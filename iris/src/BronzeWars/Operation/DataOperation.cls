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
        } elseif pRequest.Action = "PREPARE_COMBAT" {
            set result = ..PrepareCombat(payload.battleId, payload.unitId, payload.targetUnitId)
        } elseif pRequest.Action = "APPLY_COMBAT" {
            set result = ..ApplyCombat(payload.battleId, payload.unitId, payload.targetUnitId, payload.resolution)
        } elseif pRequest.Action = "NEXT_TURN" {
            set result = ..NextTurn(payload.battleId, payload.confirmIncomplete, payload.aiMovements, payload.movementSource, payload.movementReasoning)
        } elseif pRequest.Action = "PREPARE_HUMAN_TURN" {
            set result = ..PrepareHumanTurnRequest(payload.battleId)
        } elseif pRequest.Action = "SURRENDER_BATTLE" {
            set result = ..SurrenderBattle(payload.battleId, payload.side)
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
        set battle.Terrain = $select($random(2)=0:##class(BronzeWars.Model.Battle).#TERRAINDESERT, 1:##class(BronzeWars.Model.Battle).#TERRAINPLAINS)
        set sc = battle.%Save()
        $$$ThrowOnError(sc)

        set humanArmy = ..CreateArmy(battle, "HUMAN", humanFaction, "Ejército humano", .sc)
        $$$ThrowOnError(sc)
        set aiArmy = ..CreateArmy(battle, "AI", aiFaction, "Ejército de la IA", .sc)
        $$$ThrowOnError(sc)

        set sc = ..CreateUnits(battle, humanArmy, input.units)
        $$$ThrowOnError(sc)

        set sc = ..RecordEvent(battle, "BATTLE_CREATED", {"board":{"width":(width),"height":(height)},"terrain":(battle.Terrain)})
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
    if unit.Morale <= ##class(BronzeWars.Rules.Morale).#ATTACKMINIMUM return ##class(BronzeWars.Service.Result).Error(409, "LOW_MORALE_MUST_RETREAT", "Una unidad con moral 20 o inferior debe retirarse y no admite movimiento manual.")

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

Method PrepareCombat(battleId As %String, unitId As %String, targetUnitId As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, , .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if (battle.Status '= "IN_PROGRESS") ! ((battle.Phase '= "MOVEMENT") && (battle.Phase '= "COMBAT")) return ##class(BronzeWars.Service.Result).Error(409, "INVALID_BATTLE_PHASE", "La batalla no admite ataques en esta fase.")

    set attacker = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, , .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    set defender = ##class(BronzeWars.Model.BattleUnit).%OpenId(targetUnitId, , .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(attacker) ! '$isobject(defender) return ##class(BronzeWars.Service.Result).Error(404, "UNIT_NOT_FOUND", "Una de las unidades no existe.")
    if (attacker.Battle.%Id() '= battleId) ! (defender.Battle.%Id() '= battleId) return ##class(BronzeWars.Service.Result).Error(422, "UNIT_NOT_IN_BATTLE", "Las unidades no pertenecen a la batalla indicada.")
    if attacker.Army.Side '= "HUMAN" return ##class(BronzeWars.Service.Result).Error(422, "NOT_HUMAN_UNIT", "Solo una unidad humana puede iniciar este ataque.")
    if attacker.Army.%Id() = defender.Army.%Id() return ##class(BronzeWars.Service.Result).Error(422, "FRIENDLY_FIRE", "No se puede atacar a una unidad del mismo ejercito.")
    if ('attacker.Active) ! ('defender.Active) ! ('attacker.IsDeployed) ! ('defender.IsDeployed) return ##class(BronzeWars.Service.Result).Error(422, "UNIT_CANNOT_ATTACK", "Ambas unidades deben estar activas y desplegadas.")
    if attacker.HasAttacked return ##class(BronzeWars.Service.Result).Error(409, "UNIT_ALREADY_ATTACKED", "La unidad ya ha atacado en este turno.")
    if '##class(BronzeWars.Rules.Morale).CanAttack(attacker) return ##class(BronzeWars.Service.Result).Error(409, "LOW_MORALE_CANNOT_ATTACK", "Una unidad con moral 20 o inferior no puede atacar.")

    set distanceX = attacker.PositionX - defender.PositionX, distanceY = attacker.PositionY - defender.PositionY
    if distanceX < 0 set distanceX = -distanceX
    if distanceY < 0 set distanceY = -distanceY
    set distance = distanceX + distanceY
    if distance = 0 return ##class(BronzeWars.Service.Result).Error(422, "INVALID_ATTACK_TARGET", "La unidad no puede atacarse a si misma.")

    set attackerStats = attacker.UnitType
    if $isobject(attacker.UnitProfile) set attackerStats = attacker.UnitProfile
    if distance = 1 {
        set combatType = "MELEE"
    } else {
        if distance > attackerStats.AttackRange return ##class(BronzeWars.Service.Result).Error(422, "TARGET_OUT_OF_RANGE", "El objetivo esta fuera del alcance de la unidad.")
        if (attacker.UnitType.InitialProjectiles <= 0) ! (attacker.CurrentProjectiles <= 0) return ##class(BronzeWars.Service.Result).Error(409, "NO_PROJECTILES", "La unidad no dispone de proyectiles para atacar a distancia.")
        set combatType = "RANGED"
    }

    set context = ..CombatContext(attacker, defender, combatType, distance)
    do context.%Set("battleId", battleId)
    return ##class(BronzeWars.Service.Result).Success(200, context)
}

Method ApplyCombat(battleId As %String, unitId As %String, targetUnitId As %String, resolution As %DynamicObject) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    set attacker = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    set defender = ##class(BronzeWars.Model.BattleUnit).%OpenId(targetUnitId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) ! '$isobject(attacker) ! '$isobject(defender) return ##class(BronzeWars.Service.Result).Error(404, "COMBAT_ENTITY_NOT_FOUND", "No se puede aplicar el resultado del combate.")

    set attackerBefore = attacker.CurrentStrength, defenderBefore = defender.CurrentStrength, projectilesBefore = attacker.CurrentProjectiles
    set attackerMoraleBefore = attacker.Morale, defenderMoraleBefore = defender.Morale
    set attackerCasualties = resolution.attackerCasualties, defenderCasualties = resolution.defenderCasualties
    if (attackerCasualties < 0) ! (defenderCasualties < 0) ! (attackerCasualties > attackerBefore) ! (defenderCasualties > defenderBefore) return ##class(BronzeWars.Service.Result).Error(500, "INVALID_COMBAT_RESULT", "El resultado calculado para el combate no es valido.")

    tstart
    set result = ""
    try {
        set attacker.CurrentStrength = attackerBefore - attackerCasualties
        set defender.CurrentStrength = defenderBefore - defenderCasualties
        set attacker.Morale = ##class(BronzeWars.Rules.Morale).AfterCasualties(attacker, attackerMoraleBefore, attackerCasualties)
        set defender.Morale = ##class(BronzeWars.Rules.Morale).AfterCasualties(defender, defenderMoraleBefore, defenderCasualties)
        set positionMoralePenalty = resolution.%Get("defenderPositionMoralePenalty", 0)
        set defender.Morale = defender.Morale - positionMoralePenalty
        if defender.Morale < 0 set defender.Morale = 0
        set attackerMoraleLoss = attackerMoraleBefore - attacker.Morale
        set defenderMoraleLoss = defenderMoraleBefore - defender.Morale
        set attacker.HasAttacked = 1
        if resolution.type = "RANGED" set attacker.CurrentProjectiles = projectilesBefore - 1
        if attacker.CurrentStrength = 0 set attacker.Active = 0, attacker.IsDeployed = 0
        if defender.CurrentStrength = 0 set defender.Active = 0, defender.IsDeployed = 0
        set sc = attacker.%Save()
        $$$ThrowOnError(sc)
        set sc = defender.%Save()
        $$$ThrowOnError(sc)
        set attackerRetreat = {"attempted":false,"moved":false,"path":[]}
        if (attackerCasualties>0) && (attacker.Morale<=20) && attacker.Active {
            set sc = ..RetreatUnitIfRequired(battle, attacker, .attackerRetreat)
            $$$ThrowOnError(sc)
        }
        set defenderRetreat = {"attempted":false,"moved":false,"path":[]}
        if (defenderMoraleLoss>0) && (defender.Morale<=20) && defender.Active {
            set sc = ..RetreatUnitIfRequired(battle, defender, .defenderRetreat)
            $$$ThrowOnError(sc)
        }
        set combat = {
            "type":(resolution.type),
            "attackerUnitId":(unitId),
            "defenderUnitId":(targetUnitId),
            "attackerCasualties":(attackerCasualties),
            "defenderCasualties":(defenderCasualties),
            "attackerStrengthBefore":(attackerBefore),
            "attackerStrengthAfter":(attacker.CurrentStrength),
            "defenderStrengthBefore":(defenderBefore),
            "defenderStrengthAfter":(defender.CurrentStrength),
            "attackerMoraleBefore":(attackerMoraleBefore),
            "attackerMoraleAfter":(attacker.Morale),
            "attackerMoraleLoss":(attackerMoraleLoss),
            "defenderMoraleBefore":(defenderMoraleBefore),
            "defenderMoraleAfter":(defender.Morale),
            "defenderMoraleLoss":(defenderMoraleLoss),
            "attackDirection":(resolution.%Get("attackDirection", "FRONT")),
            "defenderPositionMoralePenalty":(positionMoralePenalty),
            "attackerDestroyed":('attacker.Active),
            "defenderDestroyed":('defender.Active),
            "attackerRetreat":(attackerRetreat),
            "defenderRetreat":(defenderRetreat),
            "projectilesBefore":(projectilesBefore),
            "projectilesAfter":(attacker.CurrentProjectiles)
        }
        if resolution.type = "MELEE" {
            do combat.%Set("attackerMoraleFactor", resolution.attackerMoraleFactor)
            do combat.%Set("defenderMoraleFactor", resolution.defenderMoraleFactor)
            do combat.%Set("attackerAttackModifier", resolution.attackerAttackModifier)
            do combat.%Set("defenderAttackModifier", resolution.defenderAttackModifier)
            do combat.%Set("attackerEffectiveAttack", resolution.attackerEffectiveAttack)
            do combat.%Set("defenderEffectiveAttack", resolution.defenderEffectiveAttack)
            do combat.%Set("attackerDefenseModifier", resolution.attackerDefenseModifier)
            do combat.%Set("defenderDefenseModifier", resolution.defenderDefenseModifier)
            do combat.%Set("attackerEffectiveDefense", resolution.attackerEffectiveDefense)
            do combat.%Set("defenderEffectiveDefense", resolution.defenderEffectiveDefense)
        } else {
            do combat.%Set("distance", resolution.distance)
            do combat.%Set("distanceFactor", resolution.distanceFactor)
            do combat.%Set("defenseFactor", resolution.defenseFactor)
            do combat.%Set("defenderDefenseModifier", resolution.defenderDefenseModifier)
            do combat.%Set("defenderEffectiveDefense", resolution.defenderEffectiveDefense)
        }
        set sc = ..RecordEvent(battle, "ATTACK_RESOLVED", combat, attacker, defender)
        $$$ThrowOnError(sc)
        set sc = ..EvaluateBattleConclusion(battle, .surrenderEvaluation)
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle)),"combat":(combat),"surrenderEvaluation":(surrenderEvaluation)})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method RetreatUnitIfRequired(battle As BronzeWars.Model.Battle, unit As BronzeWars.Model.BattleUnit, Output retreat As %DynamicObject) As %Status [ Private ]
{
    set fromX = +unit.PositionX, fromY = +unit.PositionY
    set retreat = {"attempted":true,"moved":false,"withdrawn":false,"from":{"x":(fromX),"y":(fromY)},"to":{"x":(fromX),"y":(fromY)},"path":[]}
    set sc = ##class(BronzeWars.Rules.Retreat).ShortestPath(unit, battle, .path)
    if $SYSTEM.Status.IsError(sc) return sc
    set retreat.path = path

    if path.%Size()=0 {
        if (unit.Army.Side="AI") && (unit.PositionY=0) && ##class(BronzeWars.Rules.Morale).IsCriticallyDepleted(unit) {
            set retreat.withdrawn = 1
            return ..WithdrawAIUnit(battle, unit, "LOW_MORALE_AND_CRITICAL_STRENGTH")
        }
        set speed = unit.UnitType.Speed
        if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed
        set unit.HasMoved = 1, unit.MovementSpent = speed
        set sc = unit.%Save()
        if $SYSTEM.Status.IsError(sc) return sc
        return ..RecordEvent(battle, "UNIT_RETREAT_BLOCKED", retreat, unit)
    }

    set destination = path.%Get(path.%Size() - 1)
    set unit.PositionX = destination.x, unit.PositionY = destination.y
    set speed = unit.UnitType.Speed
    if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed
    set unit.HasMoved = 1, unit.MovementSpent = speed
    set sc = unit.%Save()
    if $SYSTEM.Status.IsError(sc) return sc

    set retreat.moved = 1
    set retreat.to = {"x":(unit.PositionX),"y":(unit.PositionY)}
    set retreat.morale = +unit.Morale
    if (unit.Army.Side="AI") && (unit.PositionY=0) && ##class(BronzeWars.Rules.Morale).IsCriticallyDepleted(unit) set retreat.withdrawn = 1
    set sc = ..RecordEvent(battle, "UNIT_RETREATED", retreat, unit)
    if $SYSTEM.Status.IsError(sc) return sc
    if retreat.withdrawn return ..WithdrawAIUnit(battle, unit, "LOW_MORALE_AND_CRITICAL_STRENGTH")
    return sc
}

Method WithdrawAIUnit(battle As BronzeWars.Model.Battle, unit As BronzeWars.Model.BattleUnit, reason As %String) As %Status [ Private ]
{
    set unit.Active = 0, unit.IsDeployed = 0, unit.HasMoved = 1
    set sc = unit.%Save()
    if $SYSTEM.Status.IsError(sc) return sc
    return ..RecordEvent(battle, "UNIT_WITHDREW", {"reason":(reason),"position":{"x":(unit.PositionX),"y":(unit.PositionY)},"morale":(unit.Morale),"strength":(unit.CurrentStrength)}, unit)
}

Method CombatUnitContext(unit As BronzeWars.Model.BattleUnit) As %DynamicObject [ Private ]
{
    set stats = unit.UnitType
    if $isobject(unit.UnitProfile) set stats = unit.UnitProfile
    return {
        "id":(unit.%Id()),
        "code":(unit.UnitType.Code),
        "side":(unit.Army.Side),
        "x":(unit.PositionX),
        "y":(unit.PositionY),
        "strength":(unit.CurrentStrength),
        "morale":(unit.Morale),
        "attack":(stats.Attack),
        "defense":(stats.Defense),
        "damage":(stats.Damage),
        "range":(stats.AttackRange),
        "projectiles":(unit.CurrentProjectiles)
    }
}

Method CombatContext(attacker As BronzeWars.Model.BattleUnit, defender As BronzeWars.Model.BattleUnit, combatType As %String, distance As %Integer) As %DynamicObject [ Private ]
{
    set attackerContext = ..CombatUnitContext(attacker)
    set defenderContext = ..CombatUnitContext(defender)
    do attackerContext.%Set("attackModifier", ##class(BronzeWars.Model.UnitModifier).GetAttackModifier(attacker.UnitType, defender.UnitType))
    do defenderContext.%Set("attackModifier", ##class(BronzeWars.Model.UnitModifier).GetAttackModifier(defender.UnitType, attacker.UnitType))
    return {"type":(combatType),"distance":(distance),"attacker":(attackerContext),"defender":(defenderContext)}
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
    set combatTrace = ##class(%DynamicArray).%New()
    tstart
    set result = ""
    try {
        set sc = ..RecordEvent(battle, "AI_MOVEMENT_PLANNED", {"source":(movementSource),"reasoning":(movementReasoning),"movements":(aiMovements)})
        $$$ThrowOnError(sc)
        set aiArmy = ..FindArmy(battleId, "AI"), aiArmyId = aiArmy.%Id()
        &sql(SELECT COUNT(*) INTO :expectedAIMovements FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId AND Active = 1 AND IsDeployed = 1)
        if aiMovements.%Size() '= expectedAIMovements throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Incomplete AI movement plan"))
        kill movedUnits
        for index = 0:1:(aiMovements.%Size() - 1) {
            set movement = aiMovements.%Get(index), unitId = movement.unitId _ ""
            if $data(movedUnits(unitId)) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Duplicated AI movement"))
            set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId, 4, .sc)
            $$$ThrowOnError(sc)
            if ('$isobject(unit)) ! (unit.Battle.%Id() '= battleId) ! (unit.Army.Side '= "AI") ! ('unit.Active) ! ('unit.IsDeployed) throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError, "Invalid AI movement unit"))
            set speed = unit.UnitType.Speed
            if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed
            set forcedMoraleRetreat = (unit.Morale<=20)
            if forcedMoraleRetreat {
                set sc = ##class(BronzeWars.Rules.Retreat).ShortestPath(unit, battle, .path)
                $$$ThrowOnError(sc)
                set x = unit.PositionX, y = unit.PositionY, distance = path.%Size()
                if distance>0 set destination = path.%Get(distance-1), x = destination.x, y = destination.y
            } else {
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
            }
            set previous = {"x":(unit.PositionX),"y":(unit.PositionY)}
            if distance > 0 {
                set unit.PositionX = x, unit.PositionY = y, unit.MovementSpent = distance, unit.HasMoved = 1
                set sc = unit.%Save()
                $$$ThrowOnError(sc)
                set sc = ..RecordEvent(battle, "UNIT_MOVED", {"previous":(previous),"current":{"x":(x),"y":(y)},"movementSpent":(distance),"remainingMovement":(speed-distance),"controlledBy":"AI"}, unit)
                $$$ThrowOnError(sc)
                set movementPhase = $select(forcedMoraleRetreat:"MORALE_RETREAT", 1:"APPROACH")
                do movementTrace.%Push({"unitId":(unitId),"phase":(movementPhase),"from":(previous),"to":{"x":(x),"y":(y)},"path":(path)})
            }
            if forcedMoraleRetreat, (unit.PositionY=0), ##class(BronzeWars.Rules.Morale).IsCriticallyDepleted(unit) {
                set sc = ..WithdrawAIUnit(battle, unit, "LOW_MORALE_AND_CRITICAL_STRENGTH")
                $$$ThrowOnError(sc)
                if distance=0 do movementTrace.%Push({"unitId":(unitId),"phase":"MORALE_WITHDRAWAL","from":(previous),"to":(previous),"path":(path),"withdrawn":true})
                if distance>0 {
                    set withdrawalTrace = movementTrace.%Get(movementTrace.%Size()-1)
                    do withdrawalTrace.%Set("withdrawn", 1)
                }
            }
            set movedUnits(unitId) = 1
        }
        set sc = ..ExecuteAICombatPhase(battle, aiArmy, .combatTrace, movementTrace)
        $$$ThrowOnError(sc)
        set sc = ..RecordEvent(battle, "AI_COMBAT_PHASE", {"attacks":(combatTrace)})
        $$$ThrowOnError(sc)
        set sc = ..EvaluateBattleConclusion(battle, .surrenderEvaluation)
        $$$ThrowOnError(sc)
        if battle.Status = ##class(BronzeWars.Model.Battle).#STATUSFINISHED {
            tcommit
            return ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle)),"aiMovementTrace":(movementTrace),"aiCombatTrace":(combatTrace),"humanRetreatTrace":[],"moraleRecoveryTrace":[],"surrenderEvaluation":(surrenderEvaluation)})
        }
        set sc = ..PrepareHumanTurn(battle, .moraleRecoveryTrace, .humanRetreatTrace)
        $$$ThrowOnError(sc)
        set battle.CurrentRound = previousRound + 1
        set sc = battle.%Save()
        $$$ThrowOnError(sc)
        set sc = ..RecordEvent(battle, "TURN_ADVANCED", {"previousRound":(previousRound),"currentRound":(battle.CurrentRound),"forced":(pendingUnits>0),"pendingUnits":(pendingUnits),"moraleRecoveries":(moraleRecoveryTrace.%Size()),"humanRetreats":(humanRetreatTrace.%Size())})
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle)),"aiMovementTrace":(movementTrace),"aiCombatTrace":(combatTrace),"humanRetreatTrace":(humanRetreatTrace),"moraleRecoveryTrace":(moraleRecoveryTrace),"surrenderEvaluation":(surrenderEvaluation)})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method PrepareHumanTurnRequest(battleId As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    tstart
    set result = ""
    try {
        set sc = ..PrepareHumanTurn(battle, .recoveryTrace, .retreatTrace)
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle)),"moraleRecoveryTrace":(recoveryTrace),"humanRetreatTrace":(retreatTrace)})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method PrepareHumanTurn(battle As BronzeWars.Model.Battle, Output recoveryTrace As %DynamicArray, Output retreatTrace As %DynamicArray) As %Status [ Private ]
{
    set sc = ..ApplyHomeMoraleRecovery(battle, .recoveryTrace)
    if $SYSTEM.Status.IsError(sc) return sc
    set sc = ..ResetUnitActions(battle)
    if $SYSTEM.Status.IsError(sc) return sc
    return ..ApplyHumanMoraleRetreats(battle, .retreatTrace)
}

Method ResetUnitActions(battle As BronzeWars.Model.Battle) As %Status [ Private ]
{
    set battleId = battle.%Id(), sc = $$$OK
    // Persist through each object instead of a bulk SQL update. Units opened
    // during movement or combat can remain in the object cache; changing their
    // rows directly would leave stale action flags in the response serializer.
    &sql(DECLARE TurnStateResetCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Battle = :battleId AND Active = 1)
    &sql(OPEN TurnStateResetCursor)
    if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to load units for turn reset: " _ SQLCODE _ " " _ $get(%msg))
    for {
        &sql(FETCH TurnStateResetCursor INTO :resetUnitId)
        quit:(SQLCODE'=0)
        set resetUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(resetUnitId, 4, .sc)
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE TurnStateResetCursor)
            return sc
        }
        set resetUnit.HasMoved = 0
        set resetUnit.HasAttacked = 0
        set resetUnit.MovementSpent = 0
        set sc = resetUnit.%Save()
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE TurnStateResetCursor)
            return sc
        }
    }
    &sql(CLOSE TurnStateResetCursor)
    return sc
}

Method ApplyHomeMoraleRecovery(battle As BronzeWars.Model.Battle, Output recoveryTrace As %DynamicArray) As %Status [ Private ]
{
    set recoveryTrace = ##class(%DynamicArray).%New(), sc = $$$OK, battleId = battle.%Id()
    &sql(DECLARE MoraleRecoveryCursor CURSOR FOR
        SELECT %ID FROM BronzeWars_Model.BattleUnit
        WHERE Battle = :battleId AND Active = 1 AND IsDeployed = 1 AND Morale < 100
        ORDER BY %ID)
    &sql(OPEN MoraleRecoveryCursor)
    if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to load units for morale recovery")

    for {
        &sql(FETCH MoraleRecoveryCursor INTO :recoveryUnitId)
        quit:(SQLCODE'=0)
        set recoveryUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(recoveryUnitId, 4, .sc)
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE MoraleRecoveryCursor)
            return sc
        }
        if '$isobject(recoveryUnit) continue
        set inHomeZone = $select(recoveryUnit.Army.Side="AI":(recoveryUnit.PositionY<=2), 1:(recoveryUnit.PositionY>=(battle.BoardHeight-3)))
        continue:'inHomeZone
        set moraleBefore = recoveryUnit.Morale
        set availableRecovery = ##class(BronzeWars.Rules.Morale).RecoveryForStrength(recoveryUnit)
        set moraleAfter = moraleBefore + availableRecovery
        if moraleAfter > 100 set moraleAfter = 100
        set recovered = moraleAfter - moraleBefore
        continue:(recovered<=0)
        set recoveryUnit.Morale = moraleAfter
        set sc = recoveryUnit.%Save()
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE MoraleRecoveryCursor)
            return sc
        }
        set recovery = {"unitId":(recoveryUnitId),"side":(recoveryUnit.Army.Side),"strength":(recoveryUnit.CurrentStrength),"moraleBefore":(moraleBefore),"recovered":(recovered),"moraleAfter":(moraleAfter)}
        do recoveryTrace.%Push(recovery)
        set sc = ..RecordEvent(battle, "MORALE_RECOVERED", recovery, recoveryUnit)
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE MoraleRecoveryCursor)
            return sc
        }
    }
    &sql(CLOSE MoraleRecoveryCursor)
    return sc
}

Method ApplyHumanMoraleRetreats(battle As BronzeWars.Model.Battle, Output retreatTrace As %DynamicArray) As %Status [ Private ]
{
    set retreatTrace = ##class(%DynamicArray).%New(), sc = $$$OK, battleId = battle.%Id()
    &sql(DECLARE HumanMoraleRetreatCursor CURSOR FOR
        SELECT u.%ID
        FROM BronzeWars_Model.BattleUnit u
        JOIN BronzeWars_Model.Army a ON u.Army = a.%ID
        WHERE u.Battle = :battleId AND a.Side = 'HUMAN'
          AND u.Active = 1 AND u.IsDeployed = 1 AND u.Morale <= 20
        ORDER BY u.%ID)
    &sql(OPEN HumanMoraleRetreatCursor)
    if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to load low-morale human units")

    for {
        &sql(FETCH HumanMoraleRetreatCursor INTO :retreatUnitId)
        quit:(SQLCODE'=0)
        set retreatUnit = ##class(BronzeWars.Model.BattleUnit).%OpenId(retreatUnitId, 4, .sc)
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE HumanMoraleRetreatCursor)
            return sc
        }
        if '$isobject(retreatUnit) continue
        set sc = ..RetreatUnitIfRequired(battle, retreatUnit, .retreat)
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE HumanMoraleRetreatCursor)
            return sc
        }
        do retreat.%Set("unitId", retreatUnitId)
        do retreat.%Set("phase", "HUMAN_MORALE_RETREAT")
        do retreatTrace.%Push(retreat)
    }
    &sql(CLOSE HumanMoraleRetreatCursor)
    return sc
}

Method ExecuteAICombatPhase(battle As BronzeWars.Model.Battle, aiArmy As BronzeWars.Model.Army, Output combatTrace As %DynamicArray, movementTrace As %DynamicArray) As %Status [ Private ]
{
    set combatTrace = ##class(%DynamicArray).%New(), sc = $$$OK
    set battleId = battle.%Id(), aiArmyId = aiArmy.%Id()
    &sql(DECLARE AICombatUnitCursor CURSOR FOR
        SELECT %ID FROM BronzeWars_Model.BattleUnit
        WHERE Army = :aiArmyId AND Active = 1 AND IsDeployed = 1 AND HasAttacked = 0
        ORDER BY %ID)
    &sql(OPEN AICombatUnitCursor)
    if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to load AI combat units")
    for {
        &sql(FETCH AICombatUnitCursor INTO :attackerId)
        quit:(SQLCODE'=0)
        set attacker = ##class(BronzeWars.Model.BattleUnit).%OpenId(attackerId, 4, .sc)
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE AICombatUnitCursor)
            return sc
        }
        if '$isobject(attacker) continue
        if '##class(BronzeWars.Rules.Morale).CanAttack(attacker) continue
        set range = 1
        if (attacker.UnitType.InitialProjectiles>0) && (attacker.CurrentProjectiles>0) {
            set range = attacker.UnitType.AttackRange
            if $isobject(attacker.UnitProfile) set range = attacker.UnitProfile.AttackRange
        }
        set defender = ..FindNearestAttackTarget(battleId, attacker, range, .distance)
        if '$isobject(defender) continue
        set combatType = $select(distance=1:"MELEE", 1:"RANGED")

        set attackerMoraleBefore = attacker.Morale, defenderMoraleBefore = defender.Morale
        set attackerStrengthBefore = attacker.CurrentStrength, defenderStrengthBefore = defender.CurrentStrength
        set projectilesBefore = attacker.CurrentProjectiles
        set attackFrom = {"x":(attacker.PositionX),"y":(attacker.PositionY)}
        set defenderPosition = {"x":(defender.PositionX),"y":(defender.PositionY)}
        set context = ..CombatContext(attacker, defender, combatType, distance)
        set resolution = ##class(BronzeWars.Rules.Combat).Resolve(context)

        set attacker.CurrentStrength = attackerStrengthBefore - resolution.attackerCasualties
        set defender.CurrentStrength = defenderStrengthBefore - resolution.defenderCasualties
        set attacker.Morale = ##class(BronzeWars.Rules.Morale).AfterCasualties(attacker, attackerMoraleBefore, resolution.attackerCasualties)
        set defender.Morale = ##class(BronzeWars.Rules.Morale).AfterCasualties(defender, defenderMoraleBefore, resolution.defenderCasualties)
        set positionMoralePenalty = resolution.%Get("defenderPositionMoralePenalty", 0)
        set defender.Morale = defender.Morale - positionMoralePenalty
        if defender.Morale < 0 set defender.Morale = 0
        set attackerMoraleLoss = attackerMoraleBefore - attacker.Morale
        set defenderMoraleLoss = defenderMoraleBefore - defender.Morale
        if combatType="RANGED" set attacker.CurrentProjectiles = projectilesBefore - 1
        set attacker.HasAttacked = 1
        if attacker.CurrentStrength=0 set attacker.Active = 0, attacker.IsDeployed = 0
        if defender.CurrentStrength=0 set defender.Active = 0, defender.IsDeployed = 0
        set sc = attacker.%Save()
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE AICombatUnitCursor)
            return sc
        }
        set sc = defender.%Save()
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE AICombatUnitCursor)
            return sc
        }

        set attackerRetreat = {"attempted":false,"moved":false,"path":[]}
        if (resolution.attackerCasualties>0) && (attacker.Morale<=20) && attacker.Active {
            set sc = ..RetreatUnitIfRequired(battle, attacker, .attackerRetreat)
            if $SYSTEM.Status.IsError(sc) {
                &sql(CLOSE AICombatUnitCursor)
                return sc
            }
        }
        set defenderRetreat = {"attempted":false,"moved":false,"path":[]}
        if (defenderMoraleLoss>0) && (defender.Morale<=20) && defender.Active {
            set sc = ..RetreatUnitIfRequired(battle, defender, .defenderRetreat)
            if $SYSTEM.Status.IsError(sc) {
                &sql(CLOSE AICombatUnitCursor)
                return sc
            }
        }
        set postAttackRetreat = {"attempted":false,"moved":false,"path":[]}
        if (combatType="RANGED") && attacker.Active {
            set sc = ..RetreatProjectileAfterAttack(battle, attacker, defenderPosition.x, defenderPosition.y, .postAttackRetreat, movementTrace)
            if $SYSTEM.Status.IsError(sc) {
                &sql(CLOSE AICombatUnitCursor)
                return sc
            }
        }

        set combat = {
            "type":(combatType),
            "controlledBy":"AI",
            "attackerUnitId":(attackerId),
            "defenderUnitId":(defender.%Id()),
            "distance":(distance),
            "attackFrom":(attackFrom),
            "defenderPosition":(defenderPosition),
            "attackerCasualties":(resolution.attackerCasualties),
            "defenderCasualties":(resolution.defenderCasualties),
            "attackerStrengthBefore":(attackerStrengthBefore),
            "attackerStrengthAfter":(attacker.CurrentStrength),
            "defenderStrengthBefore":(defenderStrengthBefore),
            "defenderStrengthAfter":(defender.CurrentStrength),
            "attackerMoraleBefore":(attackerMoraleBefore),
            "attackerMoraleAfter":(attacker.Morale),
            "attackerMoraleLoss":(attackerMoraleLoss),
            "defenderMoraleBefore":(defenderMoraleBefore),
            "defenderMoraleAfter":(defender.Morale),
            "defenderMoraleLoss":(defenderMoraleLoss),
            "attackDirection":(resolution.%Get("attackDirection", "FRONT")),
            "defenderPositionMoralePenalty":(positionMoralePenalty),
            "attackerDestroyed":('attacker.Active),
            "defenderDestroyed":('defender.Active),
            "attackerRetreat":(attackerRetreat),
            "defenderRetreat":(defenderRetreat),
            "postAttackRetreat":(postAttackRetreat),
            "projectilesBefore":(projectilesBefore),
            "projectilesAfter":(attacker.CurrentProjectiles)
        }
        if combatType="MELEE" {
            do combat.%Set("attackerMoraleFactor", resolution.attackerMoraleFactor)
            do combat.%Set("defenderMoraleFactor", resolution.defenderMoraleFactor)
            do combat.%Set("attackerAttackModifier", resolution.attackerAttackModifier)
            do combat.%Set("defenderAttackModifier", resolution.defenderAttackModifier)
            do combat.%Set("attackerEffectiveAttack", resolution.attackerEffectiveAttack)
            do combat.%Set("defenderEffectiveAttack", resolution.defenderEffectiveAttack)
            do combat.%Set("attackerDefenseModifier", resolution.attackerDefenseModifier)
            do combat.%Set("defenderDefenseModifier", resolution.defenderDefenseModifier)
            do combat.%Set("attackerEffectiveDefense", resolution.attackerEffectiveDefense)
            do combat.%Set("defenderEffectiveDefense", resolution.defenderEffectiveDefense)
        } else {
            do combat.%Set("distanceFactor", resolution.distanceFactor)
            do combat.%Set("defenseFactor", resolution.defenseFactor)
            do combat.%Set("defenderDefenseModifier", resolution.defenderDefenseModifier)
            do combat.%Set("defenderEffectiveDefense", resolution.defenderEffectiveDefense)
        }
        set sc = ..RecordEvent(battle, "ATTACK_RESOLVED", combat, attacker, defender)
        if $SYSTEM.Status.IsError(sc) {
            &sql(CLOSE AICombatUnitCursor)
            return sc
        }
        do combatTrace.%Push(combat)
    }
    &sql(CLOSE AICombatUnitCursor)
    return sc
}

Method FindNearestAttackTarget(battleId As %String, attacker As BronzeWars.Model.BattleUnit, range As %Integer, Output nearestDistance As %Integer) As BronzeWars.Model.BattleUnit [ Private ]
{
    set target = "", nearestDistance = range + 1
    &sql(DECLARE AIRangedTargetCursor CURSOR FOR
        SELECT u.%ID FROM BronzeWars_Model.BattleUnit u
        JOIN BronzeWars_Model.Army a ON u.Army = a.%ID
        WHERE u.Battle = :battleId AND a.Side = 'HUMAN' AND u.Active = 1 AND u.IsDeployed = 1
        ORDER BY u.%ID)
    &sql(OPEN AIRangedTargetCursor)
    for {
        &sql(FETCH AIRangedTargetCursor INTO :targetId)
        quit:(SQLCODE'=0)
        set candidate = ##class(BronzeWars.Model.BattleUnit).%OpenId(targetId)
        set dx = candidate.PositionX - attacker.PositionX, dy = candidate.PositionY - attacker.PositionY
        if dx<0 set dx = -dx
        if dy<0 set dy = -dy
        set candidateDistance = dx + dy
        if (candidateDistance>0) && (candidateDistance<=range) && (candidateDistance<nearestDistance) {
            set target = candidate, nearestDistance = candidateDistance
        }
    }
    &sql(CLOSE AIRangedTargetCursor)
    return target
}

Method RetreatProjectileAfterAttack(battle As BronzeWars.Model.Battle, unit As BronzeWars.Model.BattleUnit, enemyX As %Integer, enemyY As %Integer, Output retreat As %DynamicObject, movementTrace As %DynamicArray) As %Status [ Private ]
{
    set speed = unit.UnitType.Speed
    if $isobject(unit.UnitProfile) set speed = unit.UnitProfile.Speed
    set remaining = speed - unit.MovementSpent
    set from = {"x":(unit.PositionX),"y":(unit.PositionY)}
    set path = ##class(%DynamicArray).%New()
    set retreat = {"attempted":(remaining>0),"moved":false,"from":(from),"to":(from),"path":(path)}
    if remaining<=0 return $$$OK

    set battleId = battle.%Id(), unitId = unit.%Id(), x = unit.PositionX, y = unit.PositionY
    set currentSafety = ..CardinalDistance(x, y, enemyX, enemyY)
    set directions = $listbuild($listbuild(0, -1), $listbuild(-1, 0), $listbuild(1, 0), $listbuild(0, 1))
    for step=1:1:remaining {
        set bestX = x, bestY = y, bestSafety = currentSafety
        for directionIndex=1:1:4 {
            set direction = $listget(directions, directionIndex)
            set candidateX = x + $listget(direction, 1), candidateY = y + $listget(direction, 2)
            continue:(candidateX<0)!(candidateX'<battle.BoardWidth)!(candidateY<0)!(candidateY'<battle.BoardHeight)
            &sql(SELECT COUNT(*) INTO :occupied FROM BronzeWars_Model.BattleUnit WHERE Battle = :battleId AND Active = 1 AND IsDeployed = 1 AND PositionX = :candidateX AND PositionY = :candidateY AND %ID <> :unitId)
            continue:occupied>0
            set safety = ..CardinalDistance(candidateX, candidateY, enemyX, enemyY)
            if safety>bestSafety set bestX = candidateX, bestY = candidateY, bestSafety = safety
        }
        quit:(bestX=x)&&(bestY=y)
        set x = bestX, y = bestY, currentSafety = bestSafety
        do path.%Push({"x":(x),"y":(y)})
    }
    if path.%Size()=0 return $$$OK

    set unit.PositionX = x, unit.PositionY = y
    set unit.MovementSpent = unit.MovementSpent + path.%Size(), unit.HasMoved = 1
    set sc = unit.%Save()
    if $SYSTEM.Status.IsError(sc) return sc
    set retreat.moved = 1, retreat.to = {"x":(x),"y":(y)}
    set sc = ..RecordEvent(battle, "UNIT_MOVED", {"previous":(from),"current":{"x":(x),"y":(y)},"movementSpent":(unit.MovementSpent),"remainingMovement":(speed-unit.MovementSpent),"controlledBy":"AI","phase":"POST_ATTACK_RETREAT"}, unit)
    if $SYSTEM.Status.IsError(sc) return sc
    do movementTrace.%Push({"unitId":(unitId),"phase":"POST_ATTACK_RETREAT","from":(from),"to":{"x":(x),"y":(y)},"path":(path)})
    return $$$OK
}

Method CardinalDistance(x1 As %Integer, y1 As %Integer, x2 As %Integer, y2 As %Integer) As %Integer [ Private ]
{
    set dx = x2 - x1, dy = y2 - y1
    if dx<0 set dx = -dx
    if dy<0 set dy = -dy
    return dx + dy
}

Method EvaluateBattleConclusion(battle As BronzeWars.Model.Battle, Output surrenderEvaluation As %DynamicObject) As %Status [ Private ]
{
    set humanArmy = ..FindArmy(battle.%Id(), "HUMAN")
    set aiArmy = ..FindArmy(battle.%Id(), "AI")
    if '$isobject(humanArmy) ! '$isobject(aiArmy) return $$$ERROR($$$GeneralError, "Both armies are required to evaluate battle completion")

    set humanMetrics = ##class(BronzeWars.Rules.Surrender).ArmyMetrics(humanArmy)
    set aiMetrics = ##class(BronzeWars.Rules.Surrender).ArmyMetrics(aiArmy)
    if aiMetrics.survivingSoldiers <= 0 {
        set surrenderEvaluation = {"surrendered":false,"reason":null,"armyMorale":(aiMetrics.armyMorale),"relativeStrength":0,"surrenderPressureTurns":0}
        set aiArmy.SurrenderPressureTurns = 0, aiArmy.SurrenderPressureRound = ""
        set sc = aiArmy.%Save()
        if $SYSTEM.Status.IsError(sc) return sc
        return ..FinalizeBattle(battle, humanArmy, aiArmy, "ANNIHILATION", "")
    }
    set surrenderEvaluation = ##class(BronzeWars.Rules.Surrender).Evaluate(aiMetrics.armyMorale, aiMetrics.survivingSoldiers, humanMetrics.survivingSoldiers, aiArmy.SurrenderPressureTurns)
    if (surrenderEvaluation.surrenderPressureTurns>aiArmy.SurrenderPressureTurns) && (aiArmy.SurrenderPressureRound=battle.CurrentRound) {
        set surrenderEvaluation.surrenderPressureTurns = aiArmy.SurrenderPressureTurns
        set surrenderEvaluation.surrendered = 0
        do surrenderEvaluation.%Set("reason", "", "null")
    } elseif surrenderEvaluation.surrenderPressureTurns>aiArmy.SurrenderPressureTurns {
        set aiArmy.SurrenderPressureRound = battle.CurrentRound
    } elseif surrenderEvaluation.surrenderPressureTurns=0 {
        set aiArmy.SurrenderPressureRound = ""
    }
    set aiArmy.SurrenderPressureTurns = surrenderEvaluation.surrenderPressureTurns
    set sc = aiArmy.%Save()
    if $SYSTEM.Status.IsError(sc) return sc

    if humanMetrics.survivingSoldiers <= 0 return ..FinalizeBattle(battle, aiArmy, humanArmy, "ANNIHILATION", "")
    if surrenderEvaluation.surrendered return ..FinalizeBattle(battle, humanArmy, aiArmy, "SURRENDER", surrenderEvaluation.reason)
    return $$$OK
}

Method SurrenderBattle(battleId As %String, side As %String) As %DynamicObject [ Private ]
{
    set battle = ##class(BronzeWars.Model.Battle).%OpenId(battleId, 4, .sc)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).InternalError(sc)
    if '$isobject(battle) return ##class(BronzeWars.Service.Result).Error(404, "BATTLE_NOT_FOUND", "La batalla no existe.")
    if battle.Status '= "IN_PROGRESS" return ##class(BronzeWars.Service.Result).Error(409, "BATTLE_NOT_IN_PROGRESS", "Solo puede rendirse un ejercito durante una batalla en curso.")

    set defeatedArmy = ..FindArmy(battleId, side)
    set winnerSide = $select(side="HUMAN":"AI", 1:"HUMAN")
    set winnerArmy = ..FindArmy(battleId, winnerSide)
    if '$isobject(defeatedArmy) ! '$isobject(winnerArmy) return ##class(BronzeWars.Service.Result).Error(404, "ARMY_NOT_FOUND", "No se encuentra uno de los ejercitos de la batalla.")

    set metrics = ##class(BronzeWars.Rules.Surrender).ArmyMetrics(defeatedArmy)
    set surrenderEvaluation = {"surrendered":true,"reason":"PLAYER_SURRENDER","armyMorale":(metrics.armyMorale),"relativeStrength":null,"surrenderPressureTurns":(defeatedArmy.SurrenderPressureTurns)}
    tstart
    set result = ""
    try {
        set sc = ..FinalizeBattle(battle, winnerArmy, defeatedArmy, "SURRENDER", "PLAYER_SURRENDER")
        $$$ThrowOnError(sc)
        tcommit
        set result = ##class(BronzeWars.Service.Result).Success(200, {"battle":(##class(BronzeWars.API.Serializer).Battle(battle)),"surrenderEvaluation":(surrenderEvaluation)})
    } catch exception {
        trollback 1
        set result = ##class(BronzeWars.Service.Result).InternalError(exception.AsStatus())
    }
    return result
}

Method FinalizeBattle(battle As BronzeWars.Model.Battle, winnerArmy As BronzeWars.Model.Army, defeatedArmy As BronzeWars.Model.Army, finishReason As %String, surrenderReason As %String) As %Status [ Private ]
{
    set winnerArmy.Winner = 1, defeatedArmy.Winner = 0
    set sc = winnerArmy.%Save()
    if $SYSTEM.Status.IsError(sc) return sc
    set sc = defeatedArmy.%Save()
    if $SYSTEM.Status.IsError(sc) return sc

    set battle.Status = ##class(BronzeWars.Model.Battle).#STATUSFINISHED
    set battle.Phase = ##class(BronzeWars.Model.Battle).#PHASEFINISHED
    set battle.FinishReason = finishReason
    set battle.WinnerArmy = winnerArmy
    set battle.DefeatedArmy = defeatedArmy
    set battle.FinishedAt = $zdatetime($ztimestamp, 3, 1)
    set sc = battle.%Save()
    if $SYSTEM.Status.IsError(sc) return sc
    return ..RecordEvent(battle, "BATTLE_FINISHED", {"reason":(finishReason),"surrenderReason":(surrenderReason),"winnerArmyId":(winnerArmy.%Id()),"defeatedArmyId":(defeatedArmy.%Id())})
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
    set context = {"battleId":(battleId),"commanderType":(aiArmy.CommanderType),"commanderName":(##class(BronzeWars.AI.Commanders.Strategy).Label(aiArmy.CommanderType)),"commanderDoctrine":(##class(BronzeWars.AI.Commanders.Strategy).Doctrine(aiArmy.CommanderType)),"aiFaction":(aiArmy.Faction),"board":{"width":(battle.BoardWidth),"height":(battle.BoardHeight),"aiRows":[0,1,2],"enemyDirection":"INCREASING_Y"},"grainBudget":(##class(BronzeWars.Rules.ArmyBudget).#TOTAL),"humanFormation":{"minX":(humanMinX),"maxX":(humanMaxX),"frontage":(humanFrontage),"positions":(humanPositions)},"formationDoctrine":{"forwardRow":2,"secondRow":1,"reserveRow":0,"mainLineTarget":(mainLineTarget),"frontageTarget":(frontageTarget),"mainLineRow":1},"unitTypes":(##class(%DynamicArray).%New()),"units":(##class(%DynamicArray).%New()),"doctrineVersion":"COMMANDER_DEPLOYMENT_V3"}
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

    set aiCapacity = battle.BoardWidth * 3
    if aiCapacity > ##class(BronzeWars.Rules.ArmyBudget).#AIMaxUnits set aiCapacity = ##class(BronzeWars.Rules.ArmyBudget).#AIMaxUnits
    set sc = ##class(BronzeWars.Rules.ArmyBudget).ValidateComposition(composition, aiCapacity, .totalGrain, .totalUnits, aiArmy.Faction)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).Error(422, "INVALID_AI_COMPOSITION", "La composicion propuesta para la IA no es valida.")
    set sc = ##class(BronzeWars.AI.Commanders.Strategy).ValidateComposition(aiArmy.CommanderType, composition)
    if $SYSTEM.Status.IsError(sc) return ##class(BronzeWars.Service.Result).Error(422, "INVALID_AI_COMPOSITION", "La composicion propuesta no esta equilibrada para el tipo de comandante de la IA.")

    tstart
    set result = ""
    try {
        // A previous start attempt may have committed an army whose deployment
        // was later rejected. Rebuild it from the current validated plan so that
        // retrying START_BATTLE repairs that intermediate state.
        if existingUnits > 0 {
            &sql(DECLARE ExistingAIUnitCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :aiArmyId)
            &sql(OPEN ExistingAIUnitCursor)
            for {
                &sql(FETCH ExistingAIUnitCursor INTO :existingUnitId)
                quit:(SQLCODE'=0)
                set sc = ##class(BronzeWars.Model.BattleUnit).%DeleteId(existingUnitId)
                $$$ThrowOnError(sc)
            }
            &sql(CLOSE ExistingAIUnitCursor)
            &sql(DELETE FROM BronzeWars_Model.BattleEvent WHERE Battle = :battleId AND EventType = 'AI_ARMY_SELECTED')
            if SQLCODE < 0 {
                set sc = $$$ERROR($$$GeneralError, "Unable to replace the previous AI army selection event: " _ SQLCODE _ " " _ $get(%msg))
                $$$ThrowOnError(sc)
            }
        }
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
