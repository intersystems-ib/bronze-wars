Class BronzeWars.Model.UnitType Extends (%Persistent, %JSON.Adaptor)
{
Property Code As %String(MAXLEN = 32) [ Required ];
Property Name As %String(MAXLEN = 80) [ Required ];
Property Description As %String(MAXLEN = 500) [ Required ];
Property InitialStrength As %Integer(MINVAL = 1) [ Required ];
Property Speed As %Integer(MINVAL = 1) [ Required ];
Property Attack As %Integer(MAXVAL = 10, MINVAL = 1) [ Required ];
Property Defense As %Integer(MAXVAL = 10, MINVAL = 1) [ Required ];
Property AttackRange As %Integer(MINVAL = 1) [ Required ];
Property Damage As %Integer(MINVAL = 1) [ Required ];
Property AttackDescription As %String(MAXLEN = 120) [ Required ];
Property GrainCost As %Integer(MINVAL = 1) [ Required ];
Property Active As %Boolean [ InitialExpression = 1, Required ];

Relationship OutgoingModifiers As BronzeWars.Model.UnitModifier [ Cardinality = many, Inverse = AttackerType ];
Relationship IncomingModifiers As BronzeWars.Model.UnitModifier [ Cardinality = many, Inverse = DefenderType ];
Relationship BattleUnits As BronzeWars.Model.BattleUnit [ Cardinality = many, Inverse = UnitType ];
Relationship Profiles As BronzeWars.Model.UnitProfile [ Cardinality = many, Inverse = UnitType ];

Index CodeIndex On Code [ IdKey ];
}
