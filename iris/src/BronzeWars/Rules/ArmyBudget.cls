Class BronzeWars.Rules.ArmyBudget Extends %RegisteredObject
{

Parameter TOTAL = 100;

ClassMethod GrainCost(code As %String) As %Integer
{
    if code = "LIGHT_INFANTRY" return 5
    if code = "SPEARMEN" return 6
    if code = "ARCHERS" return 7
    if code = "MERCENARIES" return ((..GrainCost("LIGHT_INFANTRY") + ..GrainCost("HEAVY_INFANTRY")) \ 2) + 1
    if code = "HEAVY_INFANTRY" return 9
    if code = "LIGHT_CAVALRY" return 20
    if code = "HEAVY_CAVALRY" return 25
    if code = "CHARIOTS" return 25
    return 0
}

ClassMethod DefaultComposition() As %DynamicArray
{
    return [{"code":"SPEARMEN","quantity":4},{"code":"HEAVY_INFANTRY","quantity":4},{"code":"LIGHT_CAVALRY","quantity":2}]
}

ClassMethod StrategicFallback(capacity As %Integer) As %DynamicArray
{
    if capacity >= 10 return ..DefaultComposition()
    return [{"code":"CHARIOTS","quantity":2},{"code":"HEAVY_CAVALRY","quantity":2}]
}

ClassMethod FormationFallback(capacity As %Integer, targetFrontage As %Integer) As %DynamicArray
{
    set bestScore = -999999, bestSpearmen = 0, bestHeavy = 0, bestMercenaries = 0, bestLight = 0, bestChariots = 0
    for chariots = 0:1:4 {
        for spearmen = 0:1:16 {
            for heavy = 0:1:11 {
                for mercenaries = 0:1:12 {
                    set spent = (chariots * 25) + (spearmen * 6) + (heavy * 9) + (mercenaries * 8)
                    continue:(spent>..#TOTAL)
                    set remainder = ..#TOTAL - spent
                    continue:((remainder#5)'=0)
                    set light = remainder \ 5
                    set totalUnits = chariots + spearmen + heavy + mercenaries + light
                    continue:(totalUnits>capacity)
                    set lineUnits = spearmen + heavy + mercenaries
                    set coverage = $select(lineUnits<targetFrontage:lineUnits, 1:targetFrontage)
                    set difference = lineUnits - targetFrontage if difference < 0 set difference = -difference
                    set score = (coverage * 10000) - (difference * 100) + totalUnits
                    if score > bestScore {
                        set bestScore = score, bestSpearmen = spearmen, bestHeavy = heavy, bestMercenaries = mercenaries, bestLight = light, bestChariots = chariots
                    }
                }
            }
        }
    }
    if bestScore = -999999 return ..StrategicFallback(capacity)
    set composition = ##class(%DynamicArray).%New()
    if bestSpearmen > 0 do composition.%Push({"code":"SPEARMEN","quantity":(bestSpearmen)})
    if bestHeavy > 0 do composition.%Push({"code":"HEAVY_INFANTRY","quantity":(bestHeavy)})
    if bestMercenaries > 0 do composition.%Push({"code":"MERCENARIES","quantity":(bestMercenaries)})
    if bestLight > 0 do composition.%Push({"code":"LIGHT_INFANTRY","quantity":(bestLight)})
    if bestChariots > 0 do composition.%Push({"code":"CHARIOTS","quantity":(bestChariots)})
    return composition
}

ClassMethod ValidateComposition(composition As %DynamicArray, capacity As %Integer, Output totalGrain As %Integer, Output totalUnits As %Integer) As %Status
{
    set totalGrain = 0, totalUnits = 0
    if '$isobject(composition) return $$$ERROR($$$GeneralError, "Army composition is required")
    if composition.%Size() = 0 return $$$ERROR($$$GeneralError, "Army composition cannot be empty")
    kill seen
    for index = 0:1:(composition.%Size() - 1) {
        set selection = composition.%Get(index)
        if '$isobject(selection) return $$$ERROR($$$GeneralError, "Invalid army selection")
        if 'selection.%IsDefined("code") ! 'selection.%IsDefined("quantity") return $$$ERROR($$$GeneralError, "Incomplete army selection")
        set code = selection.code, quantity = selection.quantity, cost = ..GrainCost(code)
        if cost = 0 return $$$ERROR($$$GeneralError, "Unknown unit type: " _ code)
        if $data(seen(code)) return $$$ERROR($$$GeneralError, "Duplicated unit type: " _ code)
        if (selection.%GetTypeOf("quantity") '= "number") ! (quantity < 1) ! (quantity '= (quantity \ 1)) return $$$ERROR($$$GeneralError, "Invalid unit quantity")
        set seen(code) = 1
        set totalGrain = totalGrain + (cost * quantity), totalUnits = totalUnits + quantity
    }
    if totalGrain '= ..#TOTAL return $$$ERROR($$$GeneralError, "Army composition must spend exactly " _ ..#TOTAL _ " grain measures")
    if totalUnits > capacity return $$$ERROR($$$GeneralError, "Army composition exceeds deployment capacity")
    return $$$OK
}

}
