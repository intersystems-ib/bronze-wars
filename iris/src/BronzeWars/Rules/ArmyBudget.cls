Class BronzeWars.Rules.ArmyBudget Extends %RegisteredObject
{

Parameter TOTAL = 100;
Parameter AIMaxUnits = 14;

ClassMethod GrainCost(code As %String, faction As %String = "") As %Integer
{
    set faction = $zconvert(faction, "U")
    if code = "LIGHT_INFANTRY" {
        if faction = "EGYPTIAN" return 6
        if faction = "ASSYRIAN" return 4
        return 5
    }
    if code = "SPEARMEN" return 6
    if code = "ARCHERS" return 7
    if code = "MERCENARIES" return ((..GrainCost("LIGHT_INFANTRY", faction) + ..GrainCost("HEAVY_INFANTRY", faction)) \ 2) + 1
    if code = "HEAVY_INFANTRY" {
        if faction = "EGYPTIAN" return 8
        if faction = "ASSYRIAN" return 10
        return 9
    }
    if code = "LIGHT_CAVALRY" return 20
    if code = "HEAVY_CAVALRY" {
        if faction = "EGYPTIAN" return 23
        if faction = "ASSYRIAN" return 26
        return 25
    }
    if code = "CHARIOTS" {
        if faction = "EGYPTIAN" return 22
        return 25
    }
    return 0
}

ClassMethod DefaultComposition(faction As %String = "") As %DynamicArray
{
    return [{"code":"SPEARMEN","quantity":4},{"code":"HEAVY_INFANTRY","quantity":2},{"code":"LIGHT_INFANTRY","quantity":2},{"code":"LIGHT_CAVALRY","quantity":2}]
}

ClassMethod StrategicFallback(capacity As %Integer, faction As %String = "", commanderType As %String = "") As %DynamicArray
{
    if capacity >= 9 return ..DefaultComposition(faction)
    return [{"code":"CHARIOTS","quantity":2},{"code":"HEAVY_CAVALRY","quantity":2}]
}

ClassMethod FormationFallback(capacity As %Integer, targetFrontage As %Integer, faction As %String = "", commanderType As %String = "") As %DynamicArray
{
    if capacity > ..#AIMaxUnits set capacity = ..#AIMaxUnits
    if commanderType = "SKIRMISHER" return ..SkirmisherFallback(capacity, targetFrontage, faction)
    set bestScore = -999999, bestSpearmen = 0, bestHeavy = 0, bestMercenaries = 0, bestLight = 0, bestChariots = 0
    for chariots = 0:1:4 {
        for spearmen = 0:1:16 {
            for heavy = 0:1:11 {
                for mercenaries = 0:1:12 {
                    set spent = (chariots * ..GrainCost("CHARIOTS", faction)) + (spearmen * ..GrainCost("SPEARMEN", faction)) + (heavy * ..GrainCost("HEAVY_INFANTRY", faction)) + (mercenaries * ..GrainCost("MERCENARIES", faction))
                    continue:(spent>..#TOTAL)
                    set remainder = ..#TOTAL - spent
                    set lightCost = ..GrainCost("LIGHT_INFANTRY", faction)
                    continue:((remainder#lightCost)'=0)
                    set light = remainder \ lightCost
                    set totalUnits = chariots + spearmen + heavy + mercenaries + light
                    continue:(totalUnits>capacity)
                    set lineUnits = spearmen + heavy + mercenaries
                    continue:(lineUnits<targetFrontage)
                    set distinct = (chariots>0) + (spearmen>0) + (heavy>0) + (mercenaries>0) + (light>0)
                    continue:(distinct<3)
                    set largest = chariots
                    if spearmen > largest set largest = spearmen
                    if heavy > largest set largest = heavy
                    if mercenaries > largest set largest = mercenaries
                    if light > largest set largest = light
                    continue:((largest*2)>(totalUnits+1))
                    if commanderType = "DEFENSIVE" set preferred = spearmen + heavy
                    if commanderType = "AGGRESSIVE" set preferred = light + chariots
                    if (commanderType = "DEFENSIVE") ! (commanderType = "AGGRESSIVE") continue:((preferred*2)<totalUnits)
                    if commanderType = "DEFENSIVE" continue:((spearmen=0)!(heavy=0))
                    if commanderType = "AGGRESSIVE" continue:((light=0)!(chariots=0))
                    if commanderType = "FLANKER" {
                        set mobile = chariots + light
                        continue:(distinct<3)!(mobile<2)
                    }
                    set coverage = $select(lineUnits<targetFrontage:lineUnits, 1:targetFrontage)
                    set difference = lineUnits - targetFrontage if difference < 0 set difference = -difference
                    set score = (coverage * 10000) - (difference * 100) + (distinct * 20) + totalUnits - largest
                    if score > bestScore {
                        set bestScore = score, bestSpearmen = spearmen, bestHeavy = heavy, bestMercenaries = mercenaries, bestLight = light, bestChariots = chariots
                    }
                }
            }
        }
    }
    if bestScore = -999999 return ..StrategicFallback(capacity, faction, commanderType)
    set composition = ##class(%DynamicArray).%New()
    if bestSpearmen > 0 do composition.%Push({"code":"SPEARMEN","quantity":(bestSpearmen)})
    if bestHeavy > 0 do composition.%Push({"code":"HEAVY_INFANTRY","quantity":(bestHeavy)})
    if bestMercenaries > 0 do composition.%Push({"code":"MERCENARIES","quantity":(bestMercenaries)})
    if bestLight > 0 do composition.%Push({"code":"LIGHT_INFANTRY","quantity":(bestLight)})
    if bestChariots > 0 do composition.%Push({"code":"CHARIOTS","quantity":(bestChariots)})
    return composition
}

ClassMethod SkirmisherFallback(capacity As %Integer, targetFrontage As %Integer, faction As %String) As %DynamicArray [ Private ]
{
    set bestScore = -999999
    set bestSpearmen = 0, bestHeavy = 0, bestMercenaries = 0
    set bestLight = 0, bestArchers = 0, bestLightCavalry = 0
    set spearmenCost = ..GrainCost("SPEARMEN", faction)
    set heavyCost = ..GrainCost("HEAVY_INFANTRY", faction)
    set mercenaryCost = ..GrainCost("MERCENARIES", faction)
    set lightCost = ..GrainCost("LIGHT_INFANTRY", faction)
    set archerCost = ..GrainCost("ARCHERS", faction)
    set cavalryCost = ..GrainCost("LIGHT_CAVALRY", faction)
    for lightCavalry = 1:1:5 {
        for spearmen = 0:1:14 {
            for heavy = 0:1:12 {
                for mercenaries = 0:1:12 {
                    set lineUnits = spearmen + heavy + mercenaries
                    continue:(lineUnits<targetFrontage)
                    set baseUnits = lineUnits + lightCavalry
                    continue:(baseUnits>=capacity)
                    set baseSpent = (spearmen*spearmenCost) + (heavy*heavyCost) + (mercenaries*mercenaryCost) + (lightCavalry*cavalryCost)
                    continue:(baseSpent>=..#TOTAL)
                    for light = 1:1:(capacity-baseUnits-1) {
                        set remainder = ..#TOTAL - baseSpent - (light*lightCost)
                        continue:(remainder<archerCost)
                        continue:((remainder#archerCost)'=0)
                        set archers = remainder \ archerCost
                        set totalUnits = baseUnits + light + archers
                        continue:(totalUnits>capacity)
                        set preferred = light + archers + lightCavalry
                        continue:((preferred*2)<totalUnits)
                        set largest = light
                        if archers > largest set largest = archers
                        if lightCavalry > largest set largest = lightCavalry
                        if spearmen > largest set largest = spearmen
                        if heavy > largest set largest = heavy
                        if mercenaries > largest set largest = mercenaries
                        continue:((largest*2)>(totalUnits+1))
                        set distinct = 3 + (spearmen>0) + (heavy>0) + (mercenaries>0)
                        set difference = lineUnits - targetFrontage
                        set score = (lineUnits*1000) - (difference*100) + (distinct*20) + totalUnits - largest
                        if score > bestScore {
                            set bestScore = score
                            set bestSpearmen = spearmen, bestHeavy = heavy, bestMercenaries = mercenaries
                            set bestLight = light, bestArchers = archers, bestLightCavalry = lightCavalry
                        }
                    }
                }
            }
        }
    }
    if bestScore = -999999 return ..StrategicFallback(capacity, faction, "SKIRMISHER")
    set composition = ##class(%DynamicArray).%New()
    if bestSpearmen > 0 do composition.%Push({"code":"SPEARMEN","quantity":(bestSpearmen)})
    if bestHeavy > 0 do composition.%Push({"code":"HEAVY_INFANTRY","quantity":(bestHeavy)})
    if bestMercenaries > 0 do composition.%Push({"code":"MERCENARIES","quantity":(bestMercenaries)})
    do composition.%Push({"code":"LIGHT_INFANTRY","quantity":(bestLight)})
    do composition.%Push({"code":"ARCHERS","quantity":(bestArchers)})
    do composition.%Push({"code":"LIGHT_CAVALRY","quantity":(bestLightCavalry)})
    return composition
}

ClassMethod ValidateComposition(composition As %DynamicArray, capacity As %Integer, Output totalGrain As %Integer, Output totalUnits As %Integer, faction As %String = "") As %Status
{
    set totalGrain = 0, totalUnits = 0
    if '$isobject(composition) return $$$ERROR($$$GeneralError, "Army composition is required")
    if composition.%Size() = 0 return $$$ERROR($$$GeneralError, "Army composition cannot be empty")
    kill seen
    for index = 0:1:(composition.%Size() - 1) {
        set selection = composition.%Get(index)
        if '$isobject(selection) return $$$ERROR($$$GeneralError, "Invalid army selection")
        if 'selection.%IsDefined("code") ! 'selection.%IsDefined("quantity") return $$$ERROR($$$GeneralError, "Incomplete army selection")
        set code = selection.code, quantity = selection.quantity, cost = ..GrainCost(code, faction)
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
