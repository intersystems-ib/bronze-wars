Class BronzeWars.AI.Tools.CampaignSituation Extends %RegisteredObject
{
/// Description: Returns the acting nation's fog-filtered armies, detected invaders and validated strategic options for this turn.
ClassMethod GetCampaignSituation(contextId As %String) As %DynamicObject
{
    if '$data(^BronzeWarsCampaignStrategy(contextId, "situation")) return {"error":"Unknown or expired strategic context"}
    set ^BronzeWarsCampaignStrategy(contextId, "used") = 1
    return ##class(%DynamicObject).%FromJSON(^BronzeWarsCampaignStrategy(contextId, "situation"))
}

/// Description: Compares detected nearby enemy formation counts with each moving army and recommends merging with available friendly armies when outnumbered. Unknown enemy counts stay unknown.
ClassMethod GetArmyReinforcementAdvice(contextId As %String) As %DynamicObject
{
    if '$data(^BronzeWarsCampaignStrategy(contextId,"situation")) return {"error":"Unknown or expired strategic context"}
    set context=##class(%DynamicObject).%FromJSON(^BronzeWarsCampaignStrategy(contextId,"situation")), advice=[]
    for index=0:1:(context.armies.%Size()-1) {
        set army=context.armies.%Get(index), stronger=[], candidates=[]
        if army.%GetTypeOf("mergeCandidates")="array" set candidates=army.mergeCandidates
        if army.%GetTypeOf("nearbyEnemies")="array" {
            for enemyIndex=0:1:(army.nearbyEnemies.%Size()-1) {
                set enemy=army.nearbyEnemies.%Get(enemyIndex)
                if (enemy.%GetTypeOf("unitCount")="number"), (army.%GetTypeOf("unitCount")="number"), (enemy.distance<=2), (enemy.unitCount>army.unitCount) do stronger.%Push(enemy)
            }
        }
        set entry={"armyId":(army.id),"unitCount":(army.%Get("unitCount",0)),"strongerEnemies":(stronger),"mergeCandidates":(candidates)}
        do entry.%Set("recommendMerge",(stronger.%Size()>0)&&(candidates.%Size()>0),"boolean")
        do advice.%Push(entry)
    }
    set ^BronzeWarsCampaignStrategy(contextId,"reinforcementUsed")=1
    return {"advice":(advice)}
}
}
