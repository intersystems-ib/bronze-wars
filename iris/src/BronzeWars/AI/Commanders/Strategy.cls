Class BronzeWars.AI.Commanders.Strategy Extends %RegisteredObject
{

Parameter DEFENSIVE = "DEFENSIVE";
Parameter AGGRESSIVE = "AGGRESSIVE";
Parameter SKIRMISHER = "SKIRMISHER";
Parameter FLANKER = "FLANKER";
Parameter BALANCED = "BALANCED";

ClassMethod RandomType() As %String
{
    set types = $listbuild(..#DEFENSIVE, ..#AGGRESSIVE, ..#SKIRMISHER, ..#FLANKER, ..#BALANCED)
    return $listget(types, $random(5) + 1)
}

ClassMethod IsValid(type As %String) As %Boolean
{
    return (type = ..#DEFENSIVE) ! (type = ..#AGGRESSIVE) ! (type = ..#SKIRMISHER) ! (type = ..#FLANKER) ! (type = ..#BALANCED)
}

ClassMethod Label(type As %String) As %String
{
    if type = ..#DEFENSIVE return "Defensivo"
    if type = ..#AGGRESSIVE return "Agresivo"
    if type = ..#SKIRMISHER return "Escaramuceador"
    if type = ..#FLANKER return "Flanqueador"
    if type = ..#BALANCED return "Equilibrado"
    return ""
}

ClassMethod Doctrine(type As %String) As %String
{
    if type = ..#DEFENSIVE return "Prioriza lanceros e infanteria pesada. Conserva una linea cohesionada y avanza lentamente, sin romper la formacion."
    if type = ..#AGGRESSIVE return "Prioriza caballeria e infanteria ligera. Busca movimientos ofensivos y reduce rapidamente la distancia con el enemigo."
    if type = ..#SKIRMISHER return "Prioriza arqueros, infanteria ligera y caballeria ligera. Mantiene distancia de ataque y evita el choque directo."
    if type = ..#FLANKER return "Extiende el frente mas alla de la linea rival y emplea unidades variadas para atacar los flancos y la retaguardia."
    return "Mantiene una composicion equilibrada y avanza de forma constante, sin cargas precipitadas ni una espera pasiva."
}

ClassMethod MovementInstruction(type As %String) As %String
{
    if type = ..#DEFENSIVE return "Elige O para toda la linea principal solo cuando pueda avanzar unida; alterna avances lentos con N. Usa D unicamente para evitar que unidades de apoyo queden expuestas."
    if type = ..#AGGRESSIVE return "Prima O en caballeria, carros e infanteria ligera y avanza hacia el enemigo. La linea principal debe conservar una unica eleccion para no fragmentarse."
    if type = ..#SKIRMISHER return "Usa O hasta alcanzar distancia de proyectiles, N mientras exista una distancia segura y D si el enemigo amenaza con entrar en contacto directo. Protege siempre a los arqueros."
    if type = ..#FLANKER return "Prima O para caballeria, carros y unidades situadas en los extremos; manten la linea central cohesionada con una misma eleccion y busca superar ambos flancos."
    return "Combina O y N para avanzar de forma constante. No uses D salvo para impedir una exposicion evidente y evita tanto las cargas generales como permanecer inmovil."
}

ClassMethod MainLineTarget(type As %String, humanFrontage As %Integer, boardWidth As %Integer) As %Integer
{
    if type = ..#DEFENSIVE set target = humanFrontage if target > 14 set target = 14
    if type = ..#AGGRESSIVE set target = humanFrontage if target > 5 set target = 5
    if type = ..#SKIRMISHER set target = humanFrontage if target > 3 set target = 3
    if type = ..#FLANKER set target = humanFrontage - 2 if target < 3 set target = 3
    if type = ..#BALANCED set target = humanFrontage if target > 8 set target = 8
    if '$data(target) set target = humanFrontage
    if target < 1 set target = 1
    if target > boardWidth set target = boardWidth
    return target
}

ClassMethod FrontageTarget(type As %String, humanFrontage As %Integer, boardWidth As %Integer) As %Integer
{
    set target = humanFrontage
    if type = ..#FLANKER set target = humanFrontage + 1
    if target < 1 set target = 1
    if target > boardWidth set target = boardWidth
    return target
}

ClassMethod FallbackComposition(type As %String, capacity As %Integer, targetFrontage As %Integer) As %DynamicArray
{
    if type = ..#DEFENSIVE, capacity >= 14 return [{"code":"SPEARMEN","quantity":8},{"code":"HEAVY_INFANTRY","quantity":4},{"code":"MERCENARIES","quantity":2}]
    if type = ..#AGGRESSIVE, capacity >= 13 return [{"code":"SPEARMEN","quantity":5},{"code":"LIGHT_INFANTRY","quantity":6},{"code":"LIGHT_CAVALRY","quantity":2}]
    if type = ..#SKIRMISHER, capacity >= 14 return [{"code":"SPEARMEN","quantity":3},{"code":"ARCHERS","quantity":6},{"code":"LIGHT_INFANTRY","quantity":4},{"code":"LIGHT_CAVALRY","quantity":1}]
    if type = ..#FLANKER, capacity >= 11 return [{"code":"SPEARMEN","quantity":8},{"code":"ARCHERS","quantity":1},{"code":"LIGHT_CAVALRY","quantity":1},{"code":"CHARIOTS","quantity":1}]
    if type = ..#BALANCED, capacity >= 10 return ##class(BronzeWars.Rules.ArmyBudget).DefaultComposition()
    return ##class(BronzeWars.Rules.ArmyBudget).FormationFallback(capacity, targetFrontage)
}

ClassMethod ValidateComposition(type As %String, composition As %DynamicArray) As %Status
{
    set total = 0, preferred = 0, distinct = composition.%Size(), mobile = 0
    for index = 0:1:(composition.%Size() - 1) {
        set selection = composition.%Get(index), code = selection.code, quantity = selection.quantity
        set total = total + quantity
        if type = ..#DEFENSIVE, ((code = "SPEARMEN") ! (code = "HEAVY_INFANTRY")) set preferred = preferred + quantity
        if type = ..#AGGRESSIVE, ((code = "LIGHT_INFANTRY") ! (code = "LIGHT_CAVALRY") ! (code = "HEAVY_CAVALRY") ! (code = "CHARIOTS")) set preferred = preferred + quantity
        if type = ..#SKIRMISHER, ((code = "ARCHERS") ! (code = "LIGHT_INFANTRY") ! (code = "LIGHT_CAVALRY")) set preferred = preferred + quantity
        if type = ..#FLANKER, ((code = "LIGHT_INFANTRY") ! (code = "LIGHT_CAVALRY") ! (code = "HEAVY_CAVALRY") ! (code = "CHARIOTS")) set mobile = mobile + quantity
    }
    if (type = ..#DEFENSIVE) ! (type = ..#AGGRESSIVE) ! (type = ..#SKIRMISHER) {
        if (preferred * 2) < total return $$$ERROR($$$GeneralError, "AI composition does not reflect commander priorities")
    }
    if type = ..#FLANKER, ((distinct < 3) ! (mobile < 2)) return $$$ERROR($$$GeneralError, "Flanking commander requires a varied army with at least two mobile flank units")
    return $$$OK
}

}
