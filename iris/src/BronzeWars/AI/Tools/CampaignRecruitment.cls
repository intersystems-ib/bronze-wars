Class BronzeWars.AI.Tools.CampaignRecruitment Extends %RegisteredObject
{

/// Description: Returns the acting nation's recruitment capacity for the supplied temporary campaign context.
ClassMethod GetRecruitmentCapacity(contextId As %String) As %DynamicObject
{
    if '$data(^BronzeWarsCampaignContext(contextId, "capacity")) return {"error":"Unknown or expired campaign context"}
    set ^BronzeWarsCampaignContext(contextId, "used") = 1
    return ##class(%DynamicObject).%FromJSON(^BronzeWarsCampaignContext(contextId, "capacity"))
}

}
