Class BronzeWars.Tests.CampaignAITest Extends %UnitTest.TestCase
{

Method TestDeploymentContextVersion()
{
    set legacy = {"capitalAvailable":false}
    set validation = ##class(BronzeWars.AI.CampaignRecruitment).ValidateDeploymentContext(legacy)
    do $$$AssertEquals(validation.status, 409, "Old city-only capacity is rejected before a model can mistake it for a full region")
    do $$$AssertEquals(validation.code, "CAMPAIGN_CLIENT_OUTDATED", "Old browser is asked to reload")
    set current = {"capitalAvailable":true,"deploymentArea":"capital_region","freeDeploymentHexes":12}
    set validation = ##class(BronzeWars.AI.CampaignRecruitment).ValidateDeploymentContext(current)
    do $$$AssertTrue(validation.ok, "Available regional capacity is accepted")
    set current.capitalAvailable = 0
    do current.%Set("capitalAvailable", 0, "boolean")
    set validation = ##class(BronzeWars.AI.CampaignRecruitment).ValidateDeploymentContext(current)
    do $$$AssertEquals(validation.status, 400, "Positive free hex count cannot be reported as unavailable")
    set current.freeDeploymentHexes = 0
    set validation = ##class(BronzeWars.AI.CampaignRecruitment).ValidateDeploymentContext(current)
    do $$$AssertTrue(validation.ok, "A genuinely full region remains blocked")
}

Method TestAutomaticRecruitmentGate()
{
    set capacity={"nation":"nubia","reserve":100,"annualProduction":20,"consumptionPerTurn":7,"annualConsumption":21,"troops":400,"maxAffordableTroops":1000,"maxSustainableTroops":0,"turn":1,"turnsToHarvest":2,"capitalAvailable":true,"deploymentArea":"capital_region","freeDeploymentHexes":10,"units":[{"code":"LIGHT_INFANTRY","cost":5,"maxAffordable":20}],"options":[]}
    &sql(SELECT COUNT(*) INTO :beforeTools FROM BronzeWars_AI_Audit.ToolExecution)
    set result=##class(BronzeWars.AI.CampaignRecruitment).Decide(capacity)
    do $$$AssertTrue(result.ok,"Production deficit returns a normal wait result")
    do $$$AssertEquals(result.data.source,"RULES","Blocked recruitment bypasses the model")
    do $$$AssertEquals(result.data.blockReason,"PRODUCTION_DEFICIT","Production is compared with three turns of upkeep")
    set capacity.consumptionPerTurn=1, capacity.annualConsumption=3, capacity.reserve=19
    set result=##class(BronzeWars.AI.CampaignRecruitment).Decide(capacity)
    do $$$AssertEquals(result.data.blockReason,"INSUFFICIENT_GRAIN","Reserves below the cheapest four formations bypass the model")
    &sql(SELECT COUNT(*) INTO :afterTools FROM BronzeWars_AI_Audit.ToolExecution)
    do $$$AssertEquals(afterTools,beforeTools,"No recruitment tools or model sessions execute for either blocked case")
    set capacity.reserve=20, capacity.consumptionPerTurn=6.666666666666667, capacity.annualConsumption=20
    do $$$AssertEquals(##class(BronzeWars.AI.CampaignRecruitment).RecruitmentBlock(capacity),"","Exact minimum reserves and equal annual balance allow the decision")
    set capacity.reserve=100, capacity.consumptionPerTurn=1, capacity.annualConsumption=3
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","quantities":{"LIGHT_INFANTRY":3},"reason":"test"},capacity),"Three formations cannot be recruited")
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","quantities":{"LIGHT_INFANTRY":4},"reason":"test"},capacity),"Four formations of one type can be recruited")
    set capacity.consumptionPerTurn=7
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","quantities":{"LIGHT_INFANTRY":4},"reason":"test"},capacity),"A model response cannot bypass a production deficit")
}

Method TestRecruitmentValidation()
{
    set capacity = {"reserve":30,"capitalAvailable":true,"maxSustainableTroops":0,"units":[{"code":"SPEARMEN","cost":6,"maxAffordable":5}],"options":[{"id":"small","quantities":{"SPEARMEN":4}}]}
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","quantities":{"SPEARMEN":4},"reason":"Reservas"}, capacity), "Scarcity does not forbid affordable recruitment")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","quantities":{"SPEARMEN":6},"reason":""}, capacity), "Reserve limits are enforced")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","quantities":{"SPEARMEN":0.5},"reason":""}, capacity), "Fractional formations are rejected")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","quantities":{"UNKNOWN":1},"reason":""}, capacity), "Unknown units are rejected")
    set answer = {"action":"recruit","optionId":"small","reason":"Defensa"}
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision(answer, capacity), "Calculated options are accepted")
    do $$$AssertEquals(answer.quantities.SPEARMEN, 4, "Option expands to validated quantities")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"recruit","optionId":"unknown","reason":""}, capacity), "Unknown options are rejected")
    set capacity.capitalAvailable = 0
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision(answer, capacity), "Occupied capitals prevent recruitment")
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignRecruitment).ValidateDecision({"action":"wait","reason":"Capital ocupada"}, capacity), "Waiting remains possible")
    set expired = ##class(BronzeWars.AI.Tools.CampaignRecruitment).GetRecruitmentCapacity("expired-test-context")
    do $$$AssertTrue(expired.%IsDefined("error"), "Expired capacity contexts cannot be consulted")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignRecruitment).ParseDecision("not JSON", capacity, .parsed), "Malformed JSON enters the correction path")
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignRecruitment).ParseDecision("{""action"":""wait"",""reason"":""Ahorrar""}", capacity, .parsed), "A corrected wait decision parses successfully")
}

Method TestCapacityBeforeModelDecision()
{
    set agent = ##class(BronzeWars.AI.Agent.Campaign).%New(##class(BronzeWars.AI.Agent.Campaign).CreateProvider())
    set sc = agent.UseToolSet("BronzeWars.AI.ToolSets.CampaignRecruitment")
    do $$$AssertStatusOK(sc, "Capacity toolset registers")
    set sc = agent.%Init()
    do $$$AssertStatusOK(sc, "Campaign agent initializes without model inference")
    set contextId = $system.Util.CreateGUID()
    set original = {"nation":"nubia","reserve":30,"capitalAvailable":false,"units":[{"code":"SPEARMEN","cost":6,"maxAffordable":0}],"options":[]}
    set ^BronzeWarsCampaignContext(contextId, "capacity") = original.%ToJSON()
    try {
        set capacity = ##class(BronzeWars.AI.CampaignRecruitment).ConsultCapacity(agent, contextId)
        do $$$AssertTrue($get(^BronzeWarsCampaignContext(contextId, "used")), "Tool really executes before any model response")
        do $$$AssertEquals(capacity.nation, "nubia", "Decision uses the requested nation's tool result")
        do $$$AssertEquals(capacity.reserve, 30, "Decision receives actual reserve data")
        set response = "{""action"":""wait"",""reason"":""La capital esta ocupada o perdida, impidiendo reclutar""}"
        do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignRecruitment).ParseDecision(response, capacity, .answer), "Reported Nubian wait response is valid after the mandatory tool step")
        do $$$AssertEquals(answer.action, "wait", "No extra model tool call or synthetic order is needed")
    } catch exception {
        do $$$AssertStatusOK(exception.AsStatus(), "Mandatory capacity consultation completes")
    }
    kill ^BronzeWarsCampaignContext(contextId)
    set rejected = 0
    try {
        set ignored = ##class(BronzeWars.AI.CampaignRecruitment).ConsultCapacity(agent, contextId)
    } catch exception {
        set rejected = 1
    }
    do $$$AssertTrue(rejected, "Expired tool context still prevents a decision")
}

}
