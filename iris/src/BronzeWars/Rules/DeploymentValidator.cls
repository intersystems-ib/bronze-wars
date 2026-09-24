Class BronzeWars.Rules.DeploymentValidator Extends %RegisteredObject
{

ClassMethod ValidatePosition(battle As BronzeWars.Model.Battle, unit As BronzeWars.Model.BattleUnit, x As %Integer, y As %Integer, side As %String, Output code As %String, Output message As %String, Output details As %DynamicArray) As %Boolean
{
    set code = "", message = "", details = ##class(%DynamicArray).%New()
    if (x < 0) ! (x >= battle.BoardWidth) ! (y < 0) ! (y >= battle.BoardHeight) {
        set code = "POSITION_OUT_OF_BOUNDS", message = "La posicion indicada esta fuera del tablero."
        do details.%Push({"field":"position","message":"Las coordenadas deben estar dentro de los limites del tablero."})
        return 0
    }

    if side = "HUMAN", (y < (battle.BoardHeight - 3)) {
        set code = "POSITION_OUTSIDE_DEPLOYMENT_ZONE", message = "La posicion no pertenece a la zona de despliegue humana."
        do details.%Push({"field":"y","message":"La unidad humana debe estar en las tres ultimas filas."})
        return 0
    }
    if side = "AI", (y > 2) {
        set code = "POSITION_OUTSIDE_DEPLOYMENT_ZONE", message = "La posicion no pertenece a la zona de despliegue de la IA."
        do details.%Push({"field":"y","message":"La unidad de la IA debe estar en las tres primeras filas."})
        return 0
    }

    set battleId = battle.%Id(), unitId = unit.%Id()
    &sql(SELECT COUNT(*) INTO :occupied FROM BronzeWars_Model.BattleUnit WHERE Battle = :battleId AND IsDeployed = 1 AND PositionX = :x AND PositionY = :y AND %ID <> :unitId)
    if occupied > 0 {
        set code = "CELL_OCCUPIED", message = "La casilla indicada ya esta ocupada."
        return 0
    }
    return 1
}

ClassMethod IsArmyReady(army As BronzeWars.Model.Army) As %Boolean
{
    set armyId = army.%Id(), total = 0, valid = 0
    &sql(DECLARE ReadyUnitCursor CURSOR FOR SELECT %ID FROM BronzeWars_Model.BattleUnit WHERE Army = :armyId AND Active = 1)
    &sql(OPEN ReadyUnitCursor)
    for {
        &sql(FETCH ReadyUnitCursor INTO :unitId)
        quit:(SQLCODE'=0)
        set total = total + 1
        set unit = ##class(BronzeWars.Model.BattleUnit).%OpenId(unitId)
        continue:'unit.IsDeployed
        continue:((unit.PositionX="")!(unit.PositionY=""))
        set battle = unit.Battle
        if army.Side = "HUMAN" {
            continue:(unit.PositionY < (battle.BoardHeight - 3))
        } else {
            continue:(unit.PositionY > 2)
        }
        continue:((unit.PositionX<0)!(unit.PositionX>=battle.BoardWidth))
        set valid = valid + 1
    }
    &sql(CLOSE ReadyUnitCursor)
    return (total > 0) & (valid = total) & '..HasDuplicatePositions(army)
}

ClassMethod HasDuplicatePositions(army As BronzeWars.Model.Army) As %Boolean
{
    set armyId = army.%Id()
    &sql(SELECT COUNT(*) INTO :duplicates FROM (SELECT PositionX, PositionY FROM BronzeWars_Model.BattleUnit WHERE Army = :armyId AND Active = 1 AND IsDeployed = 1 GROUP BY PositionX, PositionY HAVING COUNT(*) > 1) AS DuplicatePositions)
    return (duplicates > 0)
}

}
