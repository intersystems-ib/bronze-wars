Class BronzeWars.AI.ToolSets.Movement Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BronzeWarsMovement">
  <Description>Herramientas tácticas de BronzeWars para obtener alternativas de movimiento validadas y registrar la decisión del comandante rival.</Description>

  <Policies>
    <Audit Class="BronzeWars.AI.Policies.ToolAudit"/>
  </Policies>

  <Tool Name="RecommendMovementOptions" Class="BronzeWars.AI.Tools.Movement" Method="RecommendMovementOptions">
    <Description>Obtiene una única vez tres movimientos válidos —ofensivo, neutral y defensivo— para cada unidad de la IA en la batalla indicada.</Description>
  </Tool>

  <Tool Name="SubmitMovementChoices" Class="BronzeWars.AI.Tools.Movement" Method="SubmitMovementChoices">
    <Description>Registra la opción O, N o D elegida para todas las unidades. choices debe usar el formato compacto unitId:stance separado por comas, por ejemplo 41:O,52:N.</Description>
  </Tool>
</ToolSet>
}

}
