Class BronzeWars.Tests.CampaignStrategyTest Extends %UnitTest.TestCase
{
Method TestOrders()
{
    set situation={"priority":"DEFEND","armies":[{"id":1},{"id":2}],"options":[{"id":"defend","armyId":1,"intent":"DEFEND"},{"id":"hold1","armyId":1,"intent":"HOLD"},{"id":"hold2","armyId":2,"intent":"HOLD"}]}
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"defend"},{"optionId":"hold2"}],"reason":"Defender"}.%ToJSON(),situation,.answer),"Legal orders prioritize defence")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"hold1"},{"optionId":"hold2"}],"reason":"Esperar"}.%ToJSON(),situation,.answer),"Ignoring invaders is rejected")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"defend"},{"optionId":"hold1"}],"reason":"Duplicado"}.%ToJSON(),situation,.answer),"Duplicated army orders are rejected")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"unknown"},{"optionId":"hold2"}],"reason":"Inventado"}.%ToJSON(),situation,.answer),"Unknown options are rejected")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse("invalid",situation,.answer),"Malformed JSON is rejected")
    set contextId=$system.Util.CreateGUID()
    set ^BronzeWarsCampaignStrategy(contextId,"situation")=situation.%ToJSON()
    set agent=##class(BronzeWars.AI.Agent.CampaignStrategy).%New(##class(BronzeWars.AI.Agent.CampaignStrategy).CreateProvider())
    do $$$AssertStatusOK(agent.UseToolSet("BronzeWars.AI.ToolSets.CampaignSituation"),"Strategic tool registers")
    do $$$AssertStatusOK(agent.%Init(),"Strategic agent initializes")
    set result=agent.ToolManager.ExecuteTool("GetCampaignSituation",{"contextId":(contextId)})
    do $$$AssertTrue($get(^BronzeWarsCampaignStrategy(contextId,"used")),"Strategic context is consulted before the model")
    do $$$AssertEquals(result.value.priority,"DEFEND","Tool returns actual priorities")
    kill ^BronzeWarsCampaignStrategy(contextId)
}

Method TestReconquestPriority()
{
    set situation={"priority":"RECLAIM","armies":[{"id":1}],"options":[{"id":"reclaim","armyId":1,"intent":"RECLAIM"},{"id":"hold","armyId":1,"intent":"HOLD"}]}
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"reclaim"}],"reason":"Recuperar nuestra capital"}.%ToJSON(),situation,.answer),"An occupied original region can be reclaimed")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"hold"}],"reason":"Esperar"}.%ToJSON(),situation,.answer),"Ignoring reachable occupied territory is rejected")
    set situation.options=[{"id":"hold","armyId":1,"intent":"HOLD"}]
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"hold"}],"reason":"No hay ruta disponible"}.%ToJSON(),situation,.answer),"Unreachable cities do not force impossible orders")
    set situation.priority="DEFEND", situation.options=[{"id":"defend","armyId":1,"intent":"DEFEND"},{"id":"reclaim","armyId":1,"intent":"RECLAIM"}]
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"reclaim"}],"reason":"Recuperar territorio"}.%ToJSON(),situation,.answer),"National invaders remain the first priority")
}

Method TestMissingFinalBrace()
{
    set situation={"priority":"DEFEND","armies":[{"id":1}],"options":[{"id":"1:DEFEND:3","armyId":1,"intent":"DEFEND"},{"id":"1:HOLD:8,10","armyId":1,"intent":"HOLD"}]}
    set value={"orders":[{"optionId":"1:DEFEND:3"}],"reason":"Prioridad DEFEND: el ejercito 1 debe defender contra el invasor 3 en el hex 7,33."}
    set json=value.%ToJSON(), missing=$extract(json,1,$length(json)-1)
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse(missing,situation,.answer),"Reported Qwen response missing only the last root brace is accepted")
    do $$$AssertEquals(answer.orders.%Get(0).optionId,"1:DEFEND:3","Recovery preserves the exact model order")
    do $$$AssertEquals(answer.reason,value.reason,"Recovery preserves the full model explanation")
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse("```json"_$char(10)_missing_$char(10)_"```",situation,.answer),"Markdown fences do not affect root-brace recovery")
    set value.reason="Texto con {llaves}, [corchetes], "_$char(34)_"comillas"_$char(34)_" y "_$char(92)_"barra"
    set json=value.%ToJSON(), missing=$extract(json,1,$length(json)-1)
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse(missing,situation,.answer),"Quoted delimiters and escaped characters are scanned correctly")
    do $$$AssertEquals(answer.reason,value.reason,"Escaped text survives unchanged")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse($extract(json,1,$length(json)-2),situation,.answer),"An unfinished string cannot be completed")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse("{""orders"":[{""optionId"":""1:DEFEND:3""}",situation,.answer),"Unfinished arrays and missing fields cannot be inferred")
    set value.orders=[{"optionId":"invented"}], json=value.%ToJSON()
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse($extract(json,1,$length(json)-1),situation,.answer),"Recovery never permits an unknown order")
    set value.orders=[{"optionId":"1:HOLD:8,10"}], json=value.%ToJSON()
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse($extract(json,1,$length(json)-1),situation,.answer),"Recovery never bypasses mandatory defence")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse("{""orders"":[null],""reason"":""test""}",situation,.answer),"Null orders are rejected explicitly")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse("{""orders"":[""1:DEFEND:3""],""reason"":""test""}",situation,.answer),"Non-object orders are rejected explicitly")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse("{""orders"":[{}],""reason"":""test""}",situation,.answer),"Missing option identifiers are rejected explicitly")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse("{""orders"":null,""reason"":""test""}",situation,.answer),"Non-array orders cannot cause an object exception")
}

Method TestTacticalCampaignArmies()
{
    set input={"gameId":($system.Util.CreateGUID()),"playerNation":"egypt","encounter":{"id":"0:1:2:1","attackerId":1,"defenderId":2},"attacker":{"id":1,"designId":"egypt","name":"Test human","morale":80,"units":[{"code":"LIGHT_INFANTRY","quantity":2,"strengths":[42,0]}]},"defender":{"id":2,"designId":"hatti","name":"Test AI","morale":70,"units":[{"code":"LIGHT_INFANTRY","quantity":2,"strengths":[33,31]}]},"terrain":"PLAINS"}
    set result=##class(BronzeWars.Service.CampaignBattle).Create(input)
    do $$$AssertTrue(result.ok,"Campaign battle is created")
    quit:'result.ok
    set battle=result.data.battle, human=battle.armies.%Get(0), ai=battle.armies.%Get(1)
    set repeated=##class(BronzeWars.Service.CampaignBattle).Create(input)
    do $$$AssertEquals(repeated.data.battle.id,battle.id,"Retry resumes the same encounter")
    do $$$AssertEquals(human.units.%Size(),1,"Already destroyed formations stay absent")
    do $$$AssertEquals(human.units.%Get(0).currentStrength,42,"Campaign wounds are retained")
    do $$$AssertEquals(human.units.%Get(0).type.initialStrength,42,"Battle baseline uses arriving strength")
    do $$$AssertEquals(human.units.%Get(0).morale,80,"Campaign morale is retained")
    do $$$AssertEquals(ai.units.%Size(),2,"Opponent composition is retained")
    do $$$AssertEquals(ai.campaignArmyId,2,"Campaign army identity is retained")
    set placed=##class(BronzeWars.Interop.Client).PlaceUnit(battle.id,human.units.%Get(0).id,5,10)
    do $$$AssertTrue(placed.ok,"Player deploys normally")
    set started=##class(BronzeWars.Interop.Client).StartBattle(battle.id)
    do $$$AssertTrue(started.ok,"Tactical campaign battle starts")
    quit:'started.ok
    do $$$AssertEquals(started.data.battle.armies.%Get(1).units.%Size(),2,"Starting does not replace the AI army")
    do $$$AssertEquals(started.data.battle.armies.%Get(1).units.%Get(0).currentStrength,33,"Starting does not heal the AI army")
    set finished=##class(BronzeWars.Interop.Client).SurrenderBattle(battle.id)
    do $$$AssertTrue(finished.ok,"Battle returns a normal tactical outcome")
    do $$$AssertEquals(finished.data.battle.campaign.gameId,input.gameId,"Result links back to the saved campaign")
    do $$$AssertEquals(finished.data.battle.outcome.armies.%Get(1).initialForces,64,"Pre-existing campaign casualties are excluded from battle losses")
    set input.gameId=$system.Util.CreateGUID(), input.attacker.units.%Get(0).strengths=[1000,0]
    set invalid=##class(BronzeWars.Service.CampaignBattle).Create(input)
    do $$$AssertTrue('invalid.ok,"Invalid arriving force cannot create a battle")
}
}
