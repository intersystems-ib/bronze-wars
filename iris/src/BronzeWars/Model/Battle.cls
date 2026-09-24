Class BronzeWars.Model.Battle Extends (%Persistent, %JSON.Adaptor)
{
Parameter STATUSCREATED = "CREATED";
Parameter STATUSINPROGRESS = "IN_PROGRESS";
Parameter STATUSFINISHED = "FINISHED";
Parameter STATUSCANCELLED = "CANCELLED";
Parameter PHASEDEPLOYMENT = "DEPLOYMENT";
Parameter PHASEMOVEMENT = "MOVEMENT";
Parameter PHASECOMBAT = "COMBAT";
Parameter PHASEFINISHED = "FINISHED";

Property Name As %String(MAXLEN = 120) [ Required ];
Property Status As %String(VALUELIST = ",CREATED,IN_PROGRESS,FINISHED,CANCELLED") [ InitialExpression = "CREATED", Required ];
Property Phase As %String(VALUELIST = ",DEPLOYMENT,MOVEMENT,COMBAT,FINISHED") [ InitialExpression = "DEPLOYMENT", Required ];
Property BoardWidth As %Integer(MINVAL = 1) [ InitialExpression = 16, Required ];
Property BoardHeight As %Integer(MINVAL = 1) [ InitialExpression = 12, Required ];
Property CurrentRound As %Integer(MINVAL = 0) [ InitialExpression = 0, Required ];
Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3, 1)}, Required ];
Property StartedAt As %TimeStamp;
Property FinishedAt As %TimeStamp;

Relationship Armies As BronzeWars.Model.Army [ Cardinality = many, Inverse = Battle ];
Relationship Units As BronzeWars.Model.BattleUnit [ Cardinality = many, Inverse = Battle ];
Relationship Events As BronzeWars.Model.BattleEvent [ Cardinality = many, Inverse = Battle ];

Index StatusIndex On Status;
}
