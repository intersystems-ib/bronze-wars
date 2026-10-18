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

Method TestCompactStrategyContext()
{
    set situation={"priority":"DEFEND","armies":[{"id":7,"nearbyEnemies":[{"id":3,"unitCount":null,"distance":2}],"mergeCandidates":[{"id":2}],"units":[{"code":"LIGHT_INFANTRY","troops":30}]}],"options":[{"id":"7:DEFEND:3","armyId":7,"intent":"DEFEND","targetArmyId":3,"targetHexId":"21,2"}],"reinforcementAdvice":[{"armyId":7,"recommendMerge":false,"mergeCandidates":[{"id":2}]}]}
    set original=situation.%ToJSON(), compact=##class(BronzeWars.AI.CampaignStrategy).ModelSituation(situation)
    do $$$AssertEquals(situation.%ToJSON(),original,"Prompt compaction never mutates the audited validation context")
    do $$$AssertEquals(compact.armies.%Get(0).%GetTypeOf("mergeCandidates"),"unassigned","Repeated friendly candidate data is removed")
    do $$$AssertEquals(compact.reinforcementAdvice.%Get(0).mergeCandidates.%Get(0).id,2,"Actual reinforcement advice is retained")
    do $$$AssertEquals(compact.armies.%Get(0).nearbyEnemies.%Get(0).%GetTypeOf("unitCount"),"null","Unknown enemy contacts remain unknown and visible to the model")
    do $$$AssertEquals(compact.armies.%Get(0).units.%Get(0).troops,30,"Own combat strength is retained")
    do $$$AssertEquals(compact.options.%ToJSON(),situation.options.%ToJSON(),"All canonical options and their destinations are retained")
    do $$$AssertTrue($length(compact.%ToJSON())<$length(original),"The model receives less duplicate context")
    set truncated="{""orders"":[{""optionId"":""7:DEFEND:3""},{"""
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse(truncated,situation,.answer),"Reported response ending in the next order's key cannot invent missing orders")
}

Method TestCoordinateOptionAliases()
{
    set situation={"priority":"DEFEND","armies":[{"id":6},{"id":7},{"id":14},{"id":16}],"options":[{"id":"6:RECOVER:17,2","armyId":6,"intent":"RECOVER","targetHexId":"17,2"},{"id":"7:MERGE:2","armyId":7,"intent":"MERGE","targetArmyId":2,"targetHexId":"18,2"},{"id":"14:RECOVER:20,1","armyId":14,"intent":"RECOVER","targetHexId":"20,1"},{"id":"16:DEFEND:23","armyId":16,"intent":"DEFEND","targetArmyId":23,"targetHexId":"21,2"}]}
    set value={"orders":[{"optionId":"6:RECOVER:17,2"},{"optionId":"7:MERGE:2"},{"optionId":"14:RECOVER:20,1"},{"optionId":"16:DEFEND:21,2"}],"reason":"Ejercito 16 defender en hex 21,2."}
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"Reported coordinate-based DEFEND maps to the one existing option")
    do $$$AssertEquals(answer.orders.%Get(3).optionId,"16:DEFEND:23","Client receives the canonical enemy-army ID")
    do $$$AssertEquals(answer.reason,value.reason,"The model decision and explanation are retained")
    set menu=##class(BronzeWars.AI.CampaignStrategy).OptionMenu(situation)
    do $$$AssertEquals(menu.%Size(),4,"Correction menu covers every army")
    do $$$AssertEquals(menu.%Get(3).optionIds.%Get(0),"16:DEFEND:23","Correction menu uses canonical IDs")
    set value.orders.%Get(1).optionId="7:MERGE:18,2"
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"Unique friendly coordinate aliases preserve a legal merge")
    do $$$AssertEquals(answer.orders.%Get(1).optionId,"7:MERGE:2","Merge retains the actual friendly target")
    set value.orders.%Get(3).optionId="16:DEFEND:22,2"
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"Unavailable destinations stay invalid")
    set value.orders.%Get(3).optionId="16:RAID:21,2"
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"An alias cannot change the strategic intent")
    set value.orders.%Get(3).optionId="99:DEFEND:21,2"
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"An alias cannot change the acting army")
    set value.orders.%Get(3).optionId="16:DEFEND:21,2"
    do situation.options.%Push({"id":"16:DEFEND:24","armyId":16,"intent":"DEFEND","targetArmyId":24,"targetHexId":"21,2"})
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"Ambiguous coordinate aliases cannot guess a target")
    set value.orders.%Get(3).optionId="16:DEFEND:23"
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"Exact IDs take precedence over any coordinate ambiguity")
    set situation.options.%Get(1).intent="HOLD", situation.options.%Get(1).id="7:HOLD:18,2", value.orders.%Get(1).optionId="7:HOLD:18,2"
    set situation.options.%Get(0).intent="DEFEND", situation.options.%Get(0).id="6:DEFEND:23", value.orders.%Get(0).optionId="6:DEFEND:21,2"
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse(value.%ToJSON(),situation,.answer),"Matching another army's destination never creates an order")
}

Method TestReinforcementAdvice()
{
    set situation={"priority":"DEFEND","armies":[{"id":1,"unitCount":1,"nearbyEnemies":[{"id":9,"unitCount":2,"distance":1},{"id":10,"unitCount":null,"distance":2},{"id":11,"unitCount":8,"distance":3}],"mergeCandidates":[{"id":2}]}],"options":[{"id":"merge","armyId":1,"intent":"MERGE"},{"id":"defend","armyId":1,"intent":"DEFEND"}]}
    set contextId=$system.Util.CreateGUID(), ^BronzeWarsCampaignStrategy(contextId,"situation")=situation.%ToJSON()
    set agent=##class(BronzeWars.AI.Agent.CampaignStrategy).%New(##class(BronzeWars.AI.Agent.CampaignStrategy).CreateProvider())
    do $$$AssertStatusOK(agent.UseToolSet("BronzeWars.AI.ToolSets.CampaignSituation"),"Reinforcement tool registers")
    do $$$AssertStatusOK(agent.%Init(),"Reinforcement agent initializes")
    set result=agent.ToolManager.ExecuteTool("GetArmyReinforcementAdvice",{"contextId":(contextId)})
    do $$$AssertTrue($get(^BronzeWarsCampaignStrategy(contextId,"reinforcementUsed")),"Reinforcement consultation is audited")
    set advice=result.value.advice.%Get(0)
    do $$$AssertEquals(advice.strongerEnemies.%Size(),1,"Unknown counts and distant enemies are excluded")
    do $$$AssertEquals(advice.strongerEnemies.%Get(0).id,9,"Visible formation counts drive advice")
    do $$$AssertTrue(advice.recommendMerge,"Reachable allies allow reinforcement recommendation")
    set situation.reinforcementAdvice=result.value.advice
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"merge"}],"reason":"Unir fuerzas ante el invasor"}.%ToJSON(),situation,.answer),"Recommended merge prepares national defence")
    set situation.priority="RECLAIM", situation.options.%Get(1).intent="RECLAIM"
    do $$$AssertStatusOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"merge"}],"reason":"Preparar reconquista"}.%ToJSON(),situation,.answer),"Recommended merge prepares reconquest")
    do advice.%Set("recommendMerge",0,"boolean")
    do $$$AssertStatusNotOK(##class(BronzeWars.AI.CampaignStrategy).Parse({"orders":[{"optionId":"merge"}],"reason":"Evitar la prioridad"}.%ToJSON(),situation,.answer),"Unrecommended merge cannot bypass a reachable priority")
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
    set strengths=[]
    for slot=1:1:100 do strengths.%Push(1)
    set merged={"id":1,"designId":"egypt","morale":75,"units":[{"code":"LIGHT_INFANTRY","quantity":100,"strengths":(strengths)}]}
    do $$$AssertEquals(##class(BronzeWars.Service.CampaignBattle).ValidateArmy(merged),100,"Merged campaign rosters may exceed recruitment quantity limits")
    set input={"gameId":($system.Util.CreateGUID()),"playerNation":"egypt","encounter":{"id":"0:1:2:1","attackerId":1,"defenderId":2},"attacker":{"id":1,"designId":"egypt","name":"Test human","morale":80,"units":[{"code":"LIGHT_INFANTRY","quantity":2,"strengths":[42,0]}]},"defender":{"id":2,"designId":"hatti","name":"Test AI","morale":70,"units":[{"code":"LIGHT_INFANTRY","quantity":2,"strengths":[33,31]}]},"terrain":"PLAINS"}
    set result=##class(BronzeWars.Service.CampaignBattle).Create(input)
    do $$$AssertTrue(result.ok,"Campaign battle is created")
    quit:'result.ok
    set battle=result.data.battle, human=battle.armies.%Get(0), ai=battle.armies.%Get(1)
    set repeated=##class(BronzeWars.Service.CampaignBattle).Create(input)
    do $$$AssertEquals(repeated.data.battle.id,battle.id,"Retry resumes the same encounter")
    do $$$AssertEquals(human.units.%Size(),1,"Already destroyed formations stay absent")
    do $$$AssertEquals(human.units.%Get(0).currentStrength,42,"Campaign wounds are retained")
    do $$$AssertEquals(human.units.%Get(0).type.initialStrength,60,"Unit display uses its theoretical national maximum despite arriving wounds")
    set metrics=##class(BronzeWars.Rules.Surrender).ArmyMetrics(##class(BronzeWars.Model.Army).%OpenId(human.id))
    do $$$AssertEquals(metrics.initialSoldiers,60,"Automatic defeat uses the same theoretical maximum as the displayed percentage")
    do $$$AssertEquals(metrics.troopPercentage,70,"Forty-two of sixty troops is seventy percent, not one hundred")
    do $$$AssertEquals(metrics.moralePercentage,56,"Total morale uses theoretical force as its denominator")
    set situation=##class(BronzeWars.AI.Tools.BattleSituation).GetBattleSituation(battle.id)
    do $$$AssertEquals(situation.casualtiesPercentage,46.7,"AI assessment includes campaign attrition against its theoretical force")
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
    do $$$AssertStatusOK(##class(BronzeWars.AI.MovementContext).Build(battle.id,.movement),"Movement context can inspect wounded campaign troops")
    do $$$AssertEquals(movement.aiUnits.%Get(0).initialStrength,60,"AI movement also receives the theoretical maximum")
    set finished=##class(BronzeWars.Interop.Client).SurrenderBattle(battle.id)
    do $$$AssertTrue(finished.ok,"Battle returns a normal tactical outcome")
    do $$$AssertEquals(finished.data.battle.campaign.gameId,input.gameId,"Result links back to the saved campaign")
    do $$$AssertEquals(finished.data.battle.outcome.armies.%Get(1).initialForces,64,"Pre-existing campaign casualties are excluded from battle losses")
    do $$$AssertEquals(finished.data.battle.outcome.armies.%Get(1).casualties,0,"Percentage denominators never turn prior attrition into new tactical deaths")
    set input.gameId=$system.Util.CreateGUID(), input.attacker.units.%Get(0).strengths=[1000,0]
    set invalid=##class(BronzeWars.Service.CampaignBattle).Create(input)
    do $$$AssertTrue('invalid.ok,"Invalid arriving force cannot create a battle")
}
}
