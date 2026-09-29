Class BronzeWars.AI.ToolSets.DeploymentPositions Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="BronzeWarsDeploymentPositions">
  <Description>Herramientas para recomendar posiciones de despliegue a partir del estado persistido de una batalla.</Description>
  <Policies>
    <Audit Class="BronzeWars.AI.Policies.ToolAudit"/>
  </Policies>
  <Tool Name="RecommendDeploymentPositions" Class="BronzeWars.AI.Tools.DeploymentPositions" Method="RecommendDeploymentPositions">
    <Description>Consulta la batalla y recomienda posiciones libres para una unidad segun el comandante, la linea enemiga y el despliegue aliado. Solo necesita los identificadores de batalla y unidad.</Description>
  </Tool>
</ToolSet>
}

}
