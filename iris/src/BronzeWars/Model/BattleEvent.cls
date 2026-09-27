Class BronzeWars.Model.BattleEvent Extends (%Persistent, %JSON.Adaptor)
{
Parameter EVENTBATTLECREATED = "BATTLE_CREATED";
Parameter EVENTUNITDEPLOYED = "UNIT_DEPLOYED";
Parameter EVENTBATTLESTARTED = "BATTLE_STARTED";
Parameter EVENTUNITMOVED = "UNIT_MOVED";
Parameter EVENTATTACKRESOLVED = "ATTACK_RESOLVED";
Parameter EVENTAICOMBATPHASE = "AI_COMBAT_PHASE";
Parameter EVENTUNITRETREATED = "UNIT_RETREATED";
Parameter EVENTUNITRETREATBLOCKED = "UNIT_RETREAT_BLOCKED";
Parameter EVENTPHASECHANGED = "PHASE_CHANGED";
Parameter EVENTBATTLEFINISHED = "BATTLE_FINISHED";
Parameter EVENTAIARMYSELECTED = "AI_ARMY_SELECTED";

Relationship Battle As BronzeWars.Model.Battle [ Cardinality = one, Inverse = Events, Required ];
Property Round As %Integer(MINVAL = 0) [ Required ];
Property Phase As %String(VALUELIST = ",DEPLOYMENT,MOVEMENT,COMBAT,FINISHED") [ Required ];
Property EventType As %String(MAXLEN = 40) [ Required ];
Property ActorUnit As BronzeWars.Model.BattleUnit;
Property TargetUnit As BronzeWars.Model.BattleUnit;
Property Payload As %Stream.GlobalCharacter;
Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)}, Required ];

Index BattleIndex On Battle;
Index BattleRoundIndex On (Battle, Round);
Index EventTypeIndex On EventType;
}
