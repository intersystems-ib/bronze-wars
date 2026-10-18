Class BronzeWars.AI.Tools.CampaignSituation Extends %RegisteredObject
{
/// Description: Returns the acting nation's fog-filtered armies, detected invaders and validated strategic options for this turn.
ClassMethod GetCampaignSituation(contextId As %String) As %DynamicObject
{
    if '$data(^BronzeWarsCampaignStrategy(contextId, "situation")) return {"error":"Unknown or expired strategic context"}
    set ^BronzeWarsCampaignStrategy(contextId, "used") = 1
    return ##class(%DynamicObject).%FromJSON(^BronzeWarsCampaignStrategy(contextId, "situation"))
}
}
