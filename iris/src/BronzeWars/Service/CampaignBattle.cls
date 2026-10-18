Class BronzeWars.Service.CampaignBattle Extends %RegisteredObject
{

ClassMethod Create(input As %DynamicObject) As %DynamicObject
{
    set locked = 0, transaction = 0
    try {
        if (input.%GetTypeOf("gameId") '= "string") ! (input.%GetTypeOf("encounter") '= "object") throw ##class(%Exception.General).%New("Invalid campaign encounter")
        set gameId = input.gameId, encounterId = input.encounter.id
        if (gameId = "") ! ($length(gameId)>80) ! (encounterId="") ! ($length(encounterId)>120) throw ##class(%Exception.General).%New("Invalid campaign identifiers")
        lock +^BronzeWarsCampaignBattle(gameId,encounterId):10
        if '$test return ##class(BronzeWars.Service.Result).Error(409,"CAMPAIGN_BATTLE_BUSY","El combate se esta creando.")
        set locked = 1
        set battle = ##class(BronzeWars.Model.Battle).CampaignEncounterIndexOpen(gameId,encounterId)
        if '$isobject(battle) {
            if (input.%GetTypeOf("attacker") '= "object") ! (input.%GetTypeOf("defender") '= "object") throw ##class(%Exception.General).%New("Missing armies")
            if (input.attacker.id '= input.encounter.attackerId) ! (input.defender.id '= input.encounter.defenderId) ! (input.attacker.id=input.defender.id) throw ##class(%Exception.General).%New("Invalid army identities")
            if (input.attacker.designId = input.defender.designId) ! ((input.attacker.designId '= input.playerNation) && (input.defender.designId '= input.playerNation)) throw ##class(%Exception.General).%New("This battle requires the player and a rival")
            set countA = ..ValidateArmy(input.attacker), countB = ..ValidateArmy(input.defender)
            tstart
            set transaction = 1
            set battle = ##class(BronzeWars.Model.Battle).%New()
            set battle.Name = "Combate de campana", battle.CampaignGameId = gameId, battle.CampaignEncounterId = encounterId
            set largest = $select(countA>countB:countA,1:countB)
            set battle.BoardWidth = $select(largest>45:((largest+2)\3),1:15), battle.BoardHeight = 12
            set battle.Terrain = $select(input.%Get("terrain")="DESERT":"DESERT",1:"PLAINS")
            do ..Save(battle)
            do ..CreateArmy(battle,input.attacker,input.playerNation)
            do ..CreateArmy(battle,input.defender,input.playerNation)
            tcommit
            set transaction = 0
        }
        set result = ##class(BronzeWars.Service.Result).Success(200,{"battle":(##class(BronzeWars.API.Serializer).Battle(battle,1))})
    } catch error {
        if transaction trollback 1
        set result = ##class(BronzeWars.Service.Result).Error(422,"INVALID_CAMPAIGN_ENCOUNTER","No se ha podido crear el combate de campana.",[{"field":"encounter","message":(error.DisplayString())}])
    }
    if locked lock -^BronzeWarsCampaignBattle(gameId,encounterId)
    return result
}

ClassMethod Faction(nation As %String) As %String
{
    return $case(nation,"egypt":"EGYPTIAN","hatti":"HITTITE","nubia":"NUBIAN","seapeople":"SEA_PEOPLES",:"")
}

ClassMethod ValidateArmy(army As %DynamicObject) As %Integer
{
    set faction = ..Faction(army.%Get("designId")), count = 0
    if (faction="") ! (army.%GetTypeOf("units")'="array") ! (army.%GetTypeOf("id")'="number") ! (army.id<1) ! (army.id'=(army.id\1)) throw ##class(%Exception.General).%New("Invalid army")
    if (army.%GetTypeOf("morale")'="number") ! (army.morale<0) ! (army.morale>100) ! (army.morale'=(army.morale\1)) throw ##class(%Exception.General).%New("Invalid morale")
    kill seen
    for i=0:1:(army.units.%Size()-1) {
        set item = army.units.%Get(i)
        if '$isobject(item) throw ##class(%Exception.General).%New("Invalid unit")
        set type = ##class(BronzeWars.Model.UnitType).CodeIndexOpen(item.%Get("code"))
        if '$isobject(type) throw ##class(%Exception.General).%New("Unknown unit")
        set profile = ##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(type.%Id(),faction)
        if '$isobject(profile) throw ##class(%Exception.General).%New("Unavailable unit")
        if 'profile.Active ! (type.Code="MERCENARIES") ! $data(seen(type.Code)) throw ##class(%Exception.General).%New("Unavailable or duplicate unit")
        set seen(type.Code)=1
        if (item.%GetTypeOf("quantity")'="number") ! (item.quantity<1) ! (item.quantity>99) ! (item.quantity'=(item.quantity\1)) ! (item.%GetTypeOf("strengths")'="array") throw ##class(%Exception.General).%New("Invalid quantity")
        if item.strengths.%Size()'=item.quantity throw ##class(%Exception.General).%New("Invalid strengths")
        for slot=0:1:(item.quantity-1) {
            set strength = item.strengths.%Get(slot)
            if (item.strengths.%GetTypeOf(slot)'="number") ! (strength<0) ! (strength>profile.InitialStrength) ! (strength'=(strength\1)) throw ##class(%Exception.General).%New("Invalid strength")
            if strength>0 set count=count+1
        }
    }
    if count<1 throw ##class(%Exception.General).%New("Empty army")
    return count
}

ClassMethod Save(object As %Persistent)
{
    set sc=object.%Save()
    if $SYSTEM.Status.IsError(sc) throw ##class(%Exception.StatusException).CreateFromStatus(sc)
}

ClassMethod CreateArmy(battle As BronzeWars.Model.Battle, source As %DynamicObject, playerNation As %String)
{
    set army=##class(BronzeWars.Model.Army).%New()
    set army.Battle=battle, army.Name=$extract(source.%Get("name","Ejercito "_source.id),1,100), army.CampaignArmyId=source.id
    if army.Name="" set army.Name="Ejercito "_source.id
    set army.Side=$select(source.designId=playerNation:"HUMAN",1:"AI"), army.Faction=..Faction(source.designId)
    if army.Side="AI" set army.CommanderType="BALANCED"
    do ..Save(army)
    set deployed=0
    for i=0:1:(source.units.%Size()-1) {
        set item=source.units.%Get(i), type=##class(BronzeWars.Model.UnitType).CodeIndexOpen(item.code)
        set profile=##class(BronzeWars.Model.UnitProfile).UnitFactionIndexOpen(type.%Id(),army.Faction)
        for slot=0:1:(item.quantity-1) {
            set strength=item.strengths.%Get(slot)
            continue:strength=0
            set unit=##class(BronzeWars.Model.BattleUnit).%New(type,profile)
            set unit.Battle=battle, unit.Army=army, unit.Name=type.Name
            set unit.CampaignSlot=item.code_":"_slot, unit.CampaignInitialStrength=strength, unit.CurrentStrength=strength, unit.Morale=source.morale
            if army.Side="AI" {
                set unit.IsDeployed=1, unit.PositionX=deployed#battle.BoardWidth, unit.PositionY=deployed\battle.BoardWidth
                set deployed=deployed+1
            }
            do ..Save(unit)
        }
    }
}
}
