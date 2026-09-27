Class BronzeWars.Rules.Retreat Extends %RegisteredObject
{

/// Finds a shortest cardinal path towards the unit's own board edge. The path
/// is limited to the distance that the unit can cover in one turn.
ClassMethod ShortestPath(unit As BronzeWars.Model.BattleUnit, battle As BronzeWars.Model.Battle, Output path As %DynamicArray) As %Status
{
    set path = []
    if '$isobject(unit) ! '$isobject(battle) return $$$ERROR($$$GeneralError, "Unit and battle are required to calculate a retreat.")

    set startX = +unit.PositionX, startY = +unit.PositionY
    set width = +battle.BoardWidth, height = +battle.BoardHeight
    set targetY = $select(unit.Army.Side = "AI":0, 1:height - 1)
    set speed = +unit.UnitProfile.Speed
    if (speed'>0) ! (startY=targetY) return $$$OK

    set battleId = battle.%Id(), unitId = unit.%Id()
    &sql(DECLARE RetreatOccupiedCursor CURSOR FOR
        SELECT PositionX, PositionY
        FROM BronzeWars_Model.BattleUnit
        WHERE Battle = :battleId AND Active = 1 AND IsDeployed = 1 AND %ID <> :unitId)
    &sql(OPEN RetreatOccupiedCursor)
    if SQLCODE < 0 return $$$ERROR($$$GeneralError, "Unable to load occupied cells for the retreat.")
    for {
        &sql(FETCH RetreatOccupiedCursor INTO :occupiedX, :occupiedY)
        quit:(SQLCODE'=0)
        set occupied(occupiedX_","_occupiedY) = 1
    }
    &sql(CLOSE RetreatOccupiedCursor)

    set startKey = startX_","_startY
    set visited(startKey) = 1
    set queueX(1) = startX, queueY(1) = startY
    set head = 1, tail = 1, found = 0, targetKey = ""
    set homeStep = $select(unit.Army.Side = "AI":-1, 1:1)
    set directions = $listbuild($listbuild(0, homeStep), $listbuild(-1, 0), $listbuild(1, 0), $listbuild(0, -homeStep))

    for {
        quit:(head>tail)!found
        set currentX = queueX(head), currentY = queueY(head)
        set currentKey = currentX_","_currentY, head = head + 1
        if currentY=targetY {
            set found = 1, targetKey = currentKey
            quit
        }

        for directionIndex=1:1:4 {
            set direction = $listget(directions, directionIndex)
            set nextX = currentX + $listget(direction, 1), nextY = currentY + $listget(direction, 2)
            continue:(nextX<0)!(nextX'<width)!(nextY<0)!(nextY'<height)
            set nextKey = nextX_","_nextY
            continue:$data(visited(nextKey))
            continue:$data(occupied(nextKey))
            set visited(nextKey) = 1, previous(nextKey) = currentKey
            set tail = tail + 1, queueX(tail) = nextX, queueY(tail) = nextY
        }
    }

    if 'found return $$$OK

    set reverseCount = 0, currentKey = targetKey
    for {
        quit:currentKey=startKey
        set reverseCount = reverseCount + 1
        set reverseX(reverseCount) = +$piece(currentKey, ",", 1)
        set reverseY(reverseCount) = +$piece(currentKey, ",", 2)
        set currentKey = previous(currentKey)
    }
    for reverseIndex=reverseCount:-1:1 {
        quit:path.%Size()>=speed
        do path.%Push({"x":(reverseX(reverseIndex)),"y":(reverseY(reverseIndex))})
    }
    return $$$OK
}

}
