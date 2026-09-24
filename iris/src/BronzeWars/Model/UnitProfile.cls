Class BronzeWars.Model.UnitProfile Extends (%Persistent, %JSON.Adaptor)
{
Relationship UnitType As BronzeWars.Model.UnitType [ Cardinality = one, Inverse = Profiles, Required ];
Property Faction As %String(VALUELIST = ",EGYPTIAN,ASSYRIAN") [ Required ];
Property InitialStrength As %Integer(MINVAL = 1) [ Required ];
Property Speed As %Integer(MINVAL = 1) [ Required ];
Property Attack As %Integer(MAXVAL = 10, MINVAL = 1) [ Required ];
Property Defense As %Integer(MAXVAL = 10, MINVAL = 1) [ Required ];
Property AttackRange As %Integer(MINVAL = 1) [ Required ];
Property Damage As %Integer(MINVAL = 1) [ Required ];
Property AttackDescription As %String(MAXLEN = 120) [ Required ];
Property GrainCost As %Integer(MINVAL = 1) [ Required ];
Property Active As %Boolean [ InitialExpression = 1, Required ];
Relationship BattleUnits As BronzeWars.Model.BattleUnit [ Cardinality = many, Inverse = UnitProfile ];

Index UnitFactionIndex On (UnitType, Faction) [ Unique ];
}
