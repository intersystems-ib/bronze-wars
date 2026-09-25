Class BronzeWars.Model.Army Extends (%Persistent, %JSON.Adaptor)
{
Parameter SIDEHUMAN = "HUMAN";
Parameter SIDEAI = "AI";

Relationship Battle As BronzeWars.Model.Battle [ Cardinality = one, Inverse = Armies, Required ];
Property Name As %String(MAXLEN = 100) [ Required ];
Property Side As %String(VALUELIST = ",HUMAN,AI") [ Required ];
Property Faction As %String(VALUELIST = ",EGYPTIAN,ASSYRIAN") [ Required ];
Property CommanderType As %String(VALUELIST = ",DEFENSIVE,AGGRESSIVE,SKIRMISHER,FLANKER,BALANCED");
Property Active As %Boolean [ InitialExpression = 1, Required ];
Relationship Units As BronzeWars.Model.BattleUnit [ Cardinality = many, Inverse = Army ];

Index BattleSideIndex On (Battle, Side) [ Unique ];
}
