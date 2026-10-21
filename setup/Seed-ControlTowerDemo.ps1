<#
.SYNOPSIS
  Load the complete Northwind and PPCC Control Tower demo dataset.
.DESCRIPTION
  Loads the Northwind snapshot into an empty target, then creates up to 20 simulated
  disruption cases, their source-linked impacted order lines, and pending decisions.
  A matching Northwind baseline is preserved; partial or different data blocks the load.
  Never creates execution outcomes. No separate Northwind loader script is required.
  Re-running reconciles missing seed children without resetting or overwriting business data.
.EXAMPLE
  .\Seed-ControlTowerDemo.ps1 -OrgUrl https://org2e54c789.crm3.dynamics.com -User DebraB@M365x78603228.OnMicrosoft.com -ValidateOnly
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$OrgUrl,
  [Parameter(Mandatory)][string]$User,
  [string]$TenantId,
  [string]$DataPath = (Join-Path $PSScriptRoot 'control-tower-demo.json'),
  [switch]$NorthwindOnly,
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$OrgUrl = $OrgUrl.TrimEnd('/')
$origin = [uri]$OrgUrl
if ($origin.Scheme -ne 'https' -or $origin.AbsolutePath -ne '/' -or
    $origin.Query -or $origin.Fragment -or $origin.UserInfo) {
  throw '-OrgUrl must be an HTTPS environment origin, without a path or credentials.'
}
if (-not $TenantId) { $TenantId = ($User -split '@')[-1] }
$api = "$OrgUrl/api/data/v9.2"
$dataset = Get-Content -LiteralPath $DataPath -Raw | ConvertFrom-Json -AsHashtable
if ($dataset.formatVersion -ne 2 -or $dataset.northwind -isnot [Collections.IDictionary]) {
  throw 'Expected a version 2 Control Tower dataset with a northwind snapshot section.'
}
$data = $dataset.northwind
if ($data.formatVersion -ne 1 -or $data.tables.Count -ne 12 -or $data.relationships.Count -ne 2) {
  throw 'Expected a version 1 Northwind snapshot with 12 tables and two relationships.'
}
if (-not $NorthwindOnly) {
  $config = $dataset.controlTower
  if ($config -isnot [Collections.IDictionary] -or $config.featured -isnot [Collections.IDictionary] -or
    $config.maxCases -lt 1 -or $null -eq $config.delayDays -or $config.delayDays -lt 0 -or
    -not $config.featured.supplier -or -not $config.featured.product -or
    $config.featured.orders -isnot [array] -or -not $config.featured.orders.Count -or
    $null -eq $config.featured.exposure) {
    throw 'Invalid controlTower scenario settings in the demo dataset.'
  }
}

function Get-Token {
  $value = az account get-access-token --tenant $TenantId --resource $OrgUrl --query accessToken -o tsv
  if ($LASTEXITCODE -eq 0 -and $value -match '^ey') { return $value }
  return $null
}

$token = Get-Token
if (-not $token) {
  throw "No Azure CLI token for $OrgUrl. Sign in to tenant $TenantId with 'az login --tenant $TenantId --allow-no-subscriptions' and retry."
}
$payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
$upn = @($claims.upn, $claims.unique_name, $claims.preferred_username, $claims.email) |
  Where-Object { $_ } | Select-Object -First 1
if (-not $upn -or ($upn -ine $User -and $upn -inotlike "$( $User -replace '@','_' )#EXT#*")) {
  throw "Token identity '$upn' does not match -User '$User'. Select the correct Azure CLI account and retry."
}
$headers = @{
  Authorization = "Bearer $token"
  Accept = 'application/json'
  'OData-Version' = '4.0'
  'OData-MaxVersion' = '4.0'
  Prefer = 'odata.maxpagesize=5000'
}

function Invoke-Dv([string]$path, [string]$method = 'GET', $body = $null) {
  $uri = if ($path.StartsWith('https://')) { $path } else { "$api/$path" }
  if (-not $uri.StartsWith("$api/", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to send credentials outside the target API: $uri"
  }
  $parameters = @{ Uri = $uri; Headers = $headers; Method = $method; ErrorAction = 'Stop' }
  if ($null -ne $body) {
    $parameters.Body = $body | ConvertTo-Json -Depth 8 -Compress
    $parameters.ContentType = 'application/json; charset=utf-8'
  }
  try { return Invoke-RestMethod @parameters }
  catch { throw "$method $uri failed: $($_.Exception.Message) $($_.ErrorDetails.Message)" }
}

function Get-Rows([string]$path) {
  $rows = [Collections.Generic.List[object]]::new()
  $next = $path
  while ($next) {
    $page = Invoke-Dv $next
    foreach ($row in $page.value) { $rows.Add($row) }
    $next = $page.'@odata.nextLink'
  }
  return $rows.ToArray()
}

function Get-Choice([string]$table, [string]$field, [string]$label) {
  $key = "$table.$field"
  if (-not $script:choiceMaps.ContainsKey($key)) {
    $response = Invoke-Dv "EntityDefinitions(LogicalName='$table')/Attributes(LogicalName='$field')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet(`$select=Options)"
    $map = @{}
    foreach ($option in $response.OptionSet.Options) {
      $english = @($option.Label.LocalizedLabels | Where-Object LanguageCode -eq 1033 | Select-Object -First 1)
      $name = if ($english.Count) { [string]$english[0].Label } else { '' }
      if ($name) { $map[$name] = [int]$option.Value }
    }
    $script:choiceMaps[$key] = $map
  }
  if (-not $script:choiceMaps[$key].ContainsKey($label)) {
    throw "Missing en-US choice '$label' on $key."
  }
  return $script:choiceMaps[$key][$label]
}

function Get-Nav([string]$table, [string]$attribute, [string]$target) {
  $key = "$table|$attribute|$target"
  if (-not $script:navigation.ContainsKey($key)) {
    throw "Missing lookup $table.$attribute -> $target in the installed solution."
  }
  return $script:navigation[$key]
}

function Add-Bind($body, [string]$table, [string]$attribute, [string]$target, [string]$id) {
  $nav = Get-Nav $table $attribute $target
  $body["$nav@odata.bind"] = "/$($script:entitySets[$target])($id)"
}

function Test-ValueEqual($expected, $actual, [string]$type) {
  if ($null -eq $expected -or $null -eq $actual) { return $null -eq $expected -and $null -eq $actual }
  if ($type -eq 'DateTime') { return [DateTimeOffset]::Parse($expected) -eq [DateTimeOffset]::Parse($actual) }
  if ($type -in @('Decimal', 'Double', 'Money', 'Integer', 'BigInt', 'Picklist', 'Status')) {
    return [decimal]$expected -eq [decimal]$actual
  }
  if ($type -eq 'Boolean') { return [bool]$expected -eq [bool]$actual }
  return [string]$expected -ceq [string]$actual
}

function Invoke-NorthwindSeed([switch]$ValidateOnly) {
  $solutions = @(Get-Rows "solutions?`$select=uniquename,version&`$filter=uniquename eq 'NorthwindTraders' or uniquename eq 'PPCCAgenticOperationsControlTower'")
  $compatibleSolutions = @($solutions | Where-Object {
    ($_.uniquename -eq 'NorthwindTraders' -and [version]$_.version -ge [version]$data.solutionVersion) -or
    ($_.uniquename -eq 'PPCCAgenticOperationsControlTower' -and [version]$_.version -ge [version]'1.0.0.3')
  })
  if (-not $compatibleSolutions.Count) {
    throw "Import Northwind Traders $($data.solutionVersion) or newer, or standalone Control Tower 1.0.0.3 or newer, before loading this snapshot."
  }
  $tables = @{}
  $metadata = @{}
  $sourceRows = @{}
  $targetRows = @{}
  $idMap = @{}
  $relationships = @{}
  $mismatches = [Collections.Generic.List[string]]::new()
  foreach ($table in $data.tables) {
    $name = [string]$table.name
    if ($name -notmatch '^nwind_[a-z0-9_]+$' -or $tables.ContainsKey($name)) {
      throw "Invalid or duplicate Northwind table: $name"
    }
    $tables[$name] = $table
    $meta = Invoke-Dv "EntityDefinitions(LogicalName='$name')?`$select=EntitySetName,PrimaryIdAttribute&`$expand=Attributes(`$select=LogicalName,AttributeType,IsValidForCreate),ManyToOneRelationships(`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName),ManyToManyRelationships(`$select=SchemaName,Entity1LogicalName,Entity2LogicalName,Entity1NavigationPropertyName,IntersectEntityName,Entity1IntersectAttribute,Entity2IntersectAttribute)"
    $metadata[$name] = $meta
    $attributes = @{}
    foreach ($attribute in $meta.Attributes) { $attributes[$attribute.LogicalName] = $attribute }
    $fields = [Collections.Generic.List[string]]::new()
    $fields.Add($meta.PrimaryIdAttribute)
    $fields.Add('statecode')
    foreach ($column in $table.columns) {
      $attribute = $attributes[$column.name]
      if (-not $attribute -or -not $attribute.IsValidForCreate -or
          $attribute.AttributeType -ne $column.type -or
          ($column.name -notlike 'nwind_*' -and $column.name -ne 'statuscode')) {
        throw "Missing, incompatible, or non-creatable column: $name.$($column.name)"
      }
      $fields.Add($column.name)
      if ($column.type -in @('Picklist', 'Status')) {
        $class = if ($column.type -eq 'Status') { 'StatusAttributeMetadata' } else { 'PicklistAttributeMetadata' }
        $options = Invoke-Dv "EntityDefinitions(LogicalName='$name')/Attributes(LogicalName='$($column.name)')/Microsoft.Dynamics.CRM.$class`?`$expand=OptionSet"
        $allowed = @($options.OptionSet.Options.Value)
        foreach ($row in $table.rows) {
          $value = $row.values[$column.name]
          if ($null -ne $value -and $value -notin $allowed) {
            throw "Unsupported choice value $value on $name.$($column.name)."
          }
        }
      }
    }
    foreach ($lookup in $table.lookups) {
      $matches = @($meta.ManyToOneRelationships | Where-Object {
        $_.ReferencingAttribute -eq $lookup.name -and $_.ReferencedEntity -eq $lookup.table
      })
      if ($matches.Count -ne 1 -or -not $attributes[$lookup.name].IsValidForCreate) {
        throw "Missing or non-creatable lookup: $name.$($lookup.name) -> $($lookup.table)"
      }
      $lookup.navigation = $matches[0].ReferencingEntityNavigationPropertyName
      $fields.Add("_$($lookup.name)_value")
    }
    foreach ($relationship in $meta.ManyToManyRelationships) { $relationships[$relationship.SchemaName] = $relationship }
    $sourceRows[$name] = @{}
    $originals = @{}
    foreach ($row in $table.rows) {
      $original = [string]$row.values.nwind_sampledataoriginalid
      if (-not [guid]::TryParse($row.id, [ref]([guid]::Empty)) -or -not $original -or
          $sourceRows[$name].ContainsKey($row.id) -or $originals.ContainsKey($original)) {
        throw "Missing or duplicate row identity in $name."
      }
      if (@($row.values.Keys | Where-Object { $_ -notin $table.columns.name }).Count -or
          @($row.lookups.Keys | Where-Object { $_ -notin $table.lookups.name }).Count) {
        throw "Undeclared fields in snapshot row $name/$($row.id)."
      }
      $sourceRows[$name][$row.id] = $row
      $originals[$original] = $row
    }
    $targetRows[$name] = @(Get-Rows "$($meta.EntitySetName)?`$select=$($fields -join ',')")
    $idMap[$name] = @{}
    foreach ($actual in $targetRows[$name]) {
      $expected = $originals[[string]$actual.nwind_sampledataoriginalid]
      if (-not $expected) {
        $mismatches.Add("Unrecognized $name row $($actual.($meta.PrimaryIdAttribute)).")
        continue
      }
      if ($idMap[$name].ContainsKey($expected.id)) {
        $mismatches.Add("Duplicate original identity in $name.")
        continue
      }
      $idMap[$name][$expected.id] = [string]$actual.($meta.PrimaryIdAttribute)
      if ($actual.statecode -ne 0) { $mismatches.Add("Inactive target row in $name.") }
      foreach ($column in $table.columns) {
        if (-not (Test-ValueEqual $expected.values[$column.name] $actual.($column.name) $column.type)) {
          $mismatches.Add("Different value: $name/$($expected.values.nwind_sampledataoriginalid)/$($column.name).")
        }
      }
    }
  }
  [int]$rowCount = ($data.tables | ForEach-Object { $_.rows.Count } | Measure-Object -Sum).Sum
  [int]$targetCount = ($targetRows.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
  $empty = $targetCount -eq 0
  $orderedTables = [Collections.Generic.List[object]]::new()
  $pending = @($data.tables)
  while ($pending.Count) {
    $ready = @($pending | Where-Object {
      $table = $_
      @($table.lookups.table | Where-Object { $_ -notin $orderedTables.name }).Count -eq 0
    })
    if (-not $ready.Count) { throw 'Snapshot has cyclic or unknown lookup dependencies.' }
    foreach ($table in $ready) { $orderedTables.Add($table) }
    $pending = @($pending | Where-Object { $_.name -notin $ready.name })
  }
  foreach ($table in $data.tables) {
    $name = $table.name
    if (-not $empty -and $targetRows[$name].Count -ne $table.rows.Count) {
      $mismatches.Add("Row count differs for $name ($($targetRows[$name].Count) vs $($table.rows.Count)).")
    }
    foreach ($row in $table.rows) {
      foreach ($lookup in $table.lookups) {
        $reference = $row.lookups[$lookup.name]
        if ($reference -and -not $sourceRows[$lookup.table].ContainsKey($reference)) {
          throw "Dangling snapshot lookup: $name/$($row.id)/$($lookup.name)."
        }
      }
    }
    if ($empty) { continue }
    foreach ($actual in $targetRows[$name]) {
      $expected = @($table.rows | Where-Object { $_.values.nwind_sampledataoriginalid -eq $actual.nwind_sampledataoriginalid })
      if ($expected.Count -ne 1) { continue }
      foreach ($lookup in $table.lookups) {
        $reference = $expected[0].lookups[$lookup.name]
        $expectedId = if ($reference) { $idMap[$lookup.table][$reference] } else { $null }
        if ([string]$actual.("_$($lookup.name)_value") -ine [string]$expectedId) {
          $mismatches.Add("Different lookup: $name/$($expected[0].id)/$($lookup.name).")
        }
      }
    }
  }
  $linkCount = 0
  foreach ($relationship in $data.relationships) {
    $meta = $relationships[$relationship.name]
    if (-not $meta -or $meta.Entity1LogicalName -ne $relationship.leftTable -or
        $meta.Entity2LogicalName -ne $relationship.rightTable) {
      throw "Missing or incompatible relationship: $($relationship.name)"
    }
    $relationship.navigation = $meta.Entity1NavigationPropertyName
    $expectedPairs = @{}
    foreach ($pair in $relationship.rows) {
      if (-not $sourceRows[$relationship.leftTable].ContainsKey($pair.left) -or
          -not $sourceRows[$relationship.rightTable].ContainsKey($pair.right) -or
          $expectedPairs.ContainsKey("$($pair.left)|$($pair.right)")) {
        throw "Invalid or duplicate snapshot relationship: $($relationship.name)."
      }
      $expectedPairs["$($pair.left)|$($pair.right)"] = $true
    }
    $linkCount += $relationship.rows.Count
    $leftSet = $metadata[$relationship.leftTable].EntitySetName
    $leftId = $metadata[$relationship.leftTable].PrimaryIdAttribute
    $xml = "<fetch><entity name='$($relationship.leftTable)'><attribute name='$leftId'/><link-entity name='$($meta.IntersectEntityName)' from='$($meta.Entity1IntersectAttribute)' to='$leftId' intersect='true'><attribute name='$($meta.Entity2IntersectAttribute)' alias='rightid'/></link-entity></entity></fetch>"
    $actualPairs = @(Get-Rows "$leftSet`?fetchXml=$([uri]::EscapeDataString($xml))")
    $mappedPairs = @{}
    if (-not $empty) {
      foreach ($pair in $relationship.rows) {
        $left = $idMap[$relationship.leftTable][$pair.left]
        $right = $idMap[$relationship.rightTable][$pair.right]
        $mappedPairs["$left|$right"] = $true
      }
    }
    if ($actualPairs.Count -ne $(if ($empty) { 0 } else { $relationship.rows.Count })) {
      $mismatches.Add("Relationship count differs for $($relationship.name).")
    }
    foreach ($pair in $actualPairs) {
      if (-not $mappedPairs.ContainsKey("$($pair.($leftId))|$($pair.rightid)")) {
        $mismatches.Add("Unexpected relationship in $($relationship.name).")
      }
    }
  }
  if ($mismatches.Count) {
    throw "Northwind is partial or differs from the snapshot; no data was changed. Use a fresh environment or explicitly reset Northwind after reviewing downstream dependencies. $($mismatches | Select-Object -First 8 | Join-String -Separator ' ')"
  }
  if (-not $empty) {
    Write-Host "Northwind snapshot already present: $rowCount rows and $linkCount relationships. No data was changed."
    return [pscustomobject]@{ Status = 'already-present'; Rows = $rowCount; Relationships = $linkCount }
  }
  if ($rowCount + $linkCount -gt 1000) { throw 'Snapshot exceeds the 1000-operation atomic batch limit.' }
  if ($ValidateOnly) {
    Write-Host "Validated empty target and schema: would create $rowCount Northwind rows and $linkCount relationships. No data was changed."
    return [pscustomobject]@{ Status = 'validated-empty'; Rows = $rowCount; Relationships = $linkCount }
  }
  $batchId = "batch_$([guid]::NewGuid().ToString('N'))"
  $changeId = "changeset_$([guid]::NewGuid().ToString('N'))"
  $lines = [Collections.Generic.List[string]]::new()
  $lines.Add("--$batchId")
  $lines.Add("Content-Type: multipart/mixed; boundary=$changeId")
  $lines.Add('')
  $batchState = @{ count = 0 }
  function Add-Operation([string]$path, $body) {
    $batchState.count++
    $lines.Add("--$changeId")
    $lines.Add('Content-Type: application/http')
    $lines.Add('Content-Transfer-Encoding: binary')
    $lines.Add("Content-ID: $($batchState.count)")
    $lines.Add('')
    $lines.Add("POST $api/$path HTTP/1.1")
    $lines.Add('Content-Type: application/json; charset=utf-8')
    $lines.Add('Accept: application/json')
    $lines.Add('')
    $lines.Add(($body | ConvertTo-Json -Depth 8 -Compress))
  }
  foreach ($table in $orderedTables) {
    $meta = $metadata[$table.name]
    foreach ($row in $table.rows) {
      $body = [ordered]@{}
      $body[$meta.PrimaryIdAttribute] = $row.id
      foreach ($column in $table.columns) { $body[$column.name] = $row.values[$column.name] }
      foreach ($lookup in $table.lookups) {
        $reference = $row.lookups[$lookup.name]
        if ($reference) {
          $body["$($lookup.navigation)@odata.bind"] = "/$($metadata[$lookup.table].EntitySetName)($reference)"
        }
      }
      Add-Operation $meta.EntitySetName $body
    }
  }
  foreach ($relationship in $data.relationships) {
    $leftSet = $metadata[$relationship.leftTable].EntitySetName
    $rightSet = $metadata[$relationship.rightTable].EntitySetName
    foreach ($pair in $relationship.rows) {
      Add-Operation "$leftSet($($pair.left))/$($relationship.navigation)/`$ref" @{
        '@odata.id' = "$api/$rightSet($($pair.right))"
      }
    }
  }
  $lines.Add("--$changeId--")
  $lines.Add("--$batchId--")
  $lines.Add('')
  try {
    $response = Invoke-WebRequest -Uri "$api/`$batch" -Method Post -Headers $headers `
      -ContentType "multipart/mixed; boundary=$batchId" -Body ([Text.Encoding]::UTF8.GetBytes(($lines -join "`r`n"))) `
      -TimeoutSec 600 -ErrorAction Stop
  }
  catch {
    throw "Northwind atomic batch failed or its outcome is unknown: $($_.Exception.Message) $($_.ErrorDetails.Message). Re-run -ValidateOnly before retrying."
  }
  $responseText = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
  $statuses = [regex]::Matches($responseText, 'HTTP/1\.[01]\s+(\d{3})[^\r\n]*')
  if ($statuses.Count -ne $batchState.count -or @($statuses | Where-Object { [int]$_.Groups[1].Value -notin 200..299 }).Count) {
    throw "Northwind changeset failed or returned an incomplete response. Inspect the batch error and re-run -ValidateOnly. $responseText"
  }
  try { $verification = Invoke-NorthwindSeed -ValidateOnly }
  catch {
    throw "The Northwind batch committed, but post-load verification failed: $($_.Exception.Message). No automatic reset was attempted."
  }
  if ($verification.Status -ne 'already-present') {
    throw 'The batch returned success, but the Northwind snapshot was not found during verification.'
  }
  Write-Host "Loaded and verified $rowCount Northwind rows and $linkCount relationships."
  return [pscustomobject]@{ Status = 'loaded'; Rows = $rowCount; Relationships = $linkCount }
}

Invoke-Dv 'WhoAmI' | Out-Null
$northwind = Invoke-NorthwindSeed -ValidateOnly
if ($NorthwindOnly) {
  if (-not $ValidateOnly -and $northwind.Status -eq 'validated-empty') { $northwind = Invoke-NorthwindSeed }
  return $northwind
}
$tables = @('nwind_suppliers','nwind_products','nwind_orders','nwind_orderdetails',
            'ppcc_disruptioncase','ppcc_impactedorder','ppcc_recoverydecision')
$requiredColumns = @{
  ppcc_disruptioncase = @('ppcc_title','ppcc_sourcereference','ppcc_source','ppcc_delaydays',
    'ppcc_reportedon','ppcc_disruptionstatus','ppcc_severity','ppcc_recommendedaction',
    'ppcc_recommendationsummary','ppcc_impactedordercount','ppcc_revenueatrisk',
    'ppcc_productid','ppcc_supplierid')
  ppcc_impactedorder = @('ppcc_priority','ppcc_quantityatrisk','ppcc_unitpricesnapshot',
    'ppcc_financialexposure','ppcc_includedinrecovery','ppcc_customerimpactsummary',
    'ppcc_disruptioncaseid','ppcc_orderid','ppcc_orderdetailid')
  ppcc_recoverydecision = @('ppcc_requestedaction','ppcc_approvalstate','ppcc_decisionsource',
    'ppcc_iscurrentdecision','ppcc_recommendationrationale','ppcc_disruptioncaseid')
}
$entitySets = @{}
$navigation = @{}
foreach ($table in $tables) {
  $entity = Invoke-Dv "EntityDefinitions(LogicalName='$table')?`$select=EntitySetName&`$expand=Attributes(`$select=LogicalName,IsValidForCreate),ManyToOneRelationships(`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName)"
  foreach ($column in $requiredColumns[$table]) {
    if (-not @($entity.Attributes | Where-Object { $_.LogicalName -eq $column -and $_.IsValidForCreate }).Count) {
      throw "Missing or non-creatable Control Tower column: $table.$column"
    }
  }
  $entitySets[$table] = [string]$entity.EntitySetName
  foreach ($rel in $entity.ManyToOneRelationships) {
    $navigation["$table|$($rel.ReferencingAttribute)|$($rel.ReferencedEntity)"] =
      [string]$rel.ReferencingEntityNavigationPropertyName
  }
}
$productEntity = Invoke-Dv "EntityDefinitions(LogicalName='nwind_products')?`$select=LogicalName&`$expand=ManyToManyRelationships(`$select=Entity1LogicalName,Entity2LogicalName,Entity1NavigationPropertyName,Entity2NavigationPropertyName)"
$supplierLinks = @($productEntity.ManyToManyRelationships | Where-Object {
  ($_.Entity1LogicalName -eq 'nwind_products' -and $_.Entity2LogicalName -eq 'nwind_suppliers') -or
  ($_.Entity2LogicalName -eq 'nwind_products' -and $_.Entity1LogicalName -eq 'nwind_suppliers')
})
if ($supplierLinks.Count -ne 1) { throw "Expected one Northwind product/supplier relationship; found $($supplierLinks.Count)." }
$supplierNav = if ($supplierLinks[0].Entity1LogicalName -eq 'nwind_products') {
  $supplierLinks[0].Entity1NavigationPropertyName
} else { $supplierLinks[0].Entity2NavigationPropertyName }
if (-not $supplierNav) { throw 'Northwind product/supplier navigation property is missing.' }

$choiceMaps = @{}
$source = Get-Choice 'ppcc_disruptioncase' 'ppcc_source' 'Manual'
$status = Get-Choice 'ppcc_disruptioncase' 'ppcc_disruptionstatus' 'Decision Pending'
$severity = Get-Choice 'ppcc_disruptioncase' 'ppcc_severity' 'High'
$action = Get-Choice 'ppcc_disruptioncase' 'ppcc_recommendedaction' 'Split Shipment'
$priority = Get-Choice 'ppcc_impactedorder' 'ppcc_priority' 'High'
$pending = Get-Choice 'ppcc_recoverydecision' 'ppcc_approvalstate' 'Pending'
$decisionSource = Get-Choice 'ppcc_recoverydecision' 'ppcc_decisionsource' 'Imported'
foreach ($lookup in @(
  @('ppcc_disruptioncase','ppcc_productid','nwind_products'),
  @('ppcc_disruptioncase','ppcc_supplierid','nwind_suppliers'),
  @('ppcc_impactedorder','ppcc_disruptioncaseid','ppcc_disruptioncase'),
  @('ppcc_impactedorder','ppcc_orderid','nwind_orders'),
  @('ppcc_impactedorder','ppcc_orderdetailid','nwind_orderdetails'),
  @('ppcc_recoverydecision','ppcc_disruptioncaseid','ppcc_disruptioncase')
)) { Get-Nav $lookup[0] $lookup[1] $lookup[2] | Out-Null }

if ($northwind.Status -eq 'validated-empty') {
  # Plan from the already-validated snapshot before creating any source rows.
  $snapshotRows = @{}
  foreach ($table in $data.tables) {
    $snapshotRows[$table.name] = @{}
    foreach ($row in $table.rows) {
      $values = @{} + $row.values
      $values["$($table.name)id"] = $row.id
      foreach ($lookup in $table.lookups) { $values["_$($lookup.name)_value"] = $row.lookups[$lookup.name] }
      $snapshotRows[$table.name][$row.id] = [pscustomobject]$values
    }
  }
  $links = @($data.relationships | Where-Object {
    $_.leftTable -eq 'nwind_suppliers' -and $_.rightTable -eq 'nwind_products'
  })
  if ($links.Count -ne 1) { throw 'Snapshot must contain one supplier/product relationship.' }
  $products = @($snapshotRows.nwind_products.Values)
  foreach ($product in $products) {
    $suppliers = @($links[0].rows | Where-Object right -eq $product.nwind_productsid |
      ForEach-Object { $snapshotRows.nwind_suppliers[$_.left] })
    $product | Add-Member -NotePropertyName $supplierNav -NotePropertyValue $suppliers
  }
  $orders = @($snapshotRows.nwind_orders.Values)
  $details = @($snapshotRows.nwind_orderdetails.Values)
} else {
  $products = Get-Rows "$($entitySets.nwind_products)?`$select=nwind_productsid,nwind_productname,nwind_productcode&`$expand=$supplierNav(`$select=nwind_suppliersid,nwind_company)"
  $orders = Get-Rows "$($entitySets.nwind_orders)?`$select=nwind_ordersid,nwind_ordernumber,nwind_orderstatusid"
  $details = Get-Rows "$($entitySets.nwind_orderdetails)?`$select=nwind_orderdetailsid,_nwind_orderid_value,_nwind_productid_value,nwind_quantity,nwind_unitprice"
}
if (-not $products.Count -or -not $orders.Count -or -not $details.Count) {
  throw 'Validated Northwind source has no products, orders, or order details.'
}
$ordersById = @{}
foreach ($order in $orders) { $ordersById[[string]$order.nwind_ordersid] = $order }
$linesByProduct = @{}
foreach ($line in $details) {
  if ($null -eq $line.nwind_quantity -or $null -eq $line.nwind_unitprice -or
      [decimal]$line.nwind_quantity -le 0 -or [decimal]$line.nwind_unitprice -lt 0) { continue }
  $productId = [string]$line._nwind_productid_value
  $orderId = [string]$line._nwind_orderid_value
  if (-not $productId -or -not $ordersById.ContainsKey($orderId)) { continue }
  if (-not $linesByProduct.ContainsKey($productId)) { $linesByProduct[$productId] = [Collections.Generic.List[object]]::new() }
  $linesByProduct[$productId].Add($line)
}

$featured = $null
$candidates = [Collections.Generic.List[object]]::new()
foreach ($product in $products) {
  $productId = [string]$product.nwind_productsid
  if (-not $linesByProduct.ContainsKey($productId)) { continue }
  $suppliers = @($product.$supplierNav | Sort-Object nwind_company, nwind_suppliersid)
  if (-not $suppliers.Count) { continue }
  $supplier = $suppliers[0]
  if ($product.nwind_productname -eq $config.featured.product) {
    $supplier = @($suppliers | Where-Object nwind_company -eq $config.featured.supplier | Select-Object -First 1)[0]
    if (-not $supplier) { throw "Featured product '$($config.featured.product)' is not linked to '$($config.featured.supplier)'." }
  }
  $productLines = @($linesByProduct[$productId].ToArray())
  if ($product.nwind_productname -eq $config.featured.product) {
    $productLines = @($productLines | Where-Object {
      $config.featured.orders -contains $ordersById[[string]$_._nwind_orderid_value].nwind_ordernumber
    })
  }
  $candidates.Add([pscustomobject]@{ product = $product; supplier = $supplier; lines = $productLines })
  if ($product.nwind_productname -eq $config.featured.product) { $featured = $candidates[-1] }
}
if (-not $candidates.Count) { throw 'No Northwind products have both a supplier and a valid order line.' }
if ($featured) {
  $found = @($featured.lines | ForEach-Object { $ordersById[[string]$_._nwind_orderid_value].nwind_ordernumber } | Sort-Object -Unique)
  $missing = @($config.featured.orders | Where-Object { $found -notcontains $_ })
  $total = [decimal]0
  foreach ($line in $featured.lines) {
    if ($config.featured.orders -contains $ordersById[[string]$line._nwind_orderid_value].nwind_ordernumber) {
      $total += [Math]::Round(([decimal]$line.nwind_quantity * [decimal]$line.nwind_unitprice), 2,
                              [MidpointRounding]::AwayFromZero)
    }
  }
  if ($missing.Count -or $total -ne [decimal]$config.featured.exposure) {
    throw "Featured Northwind fixture mismatch: missing orders [$($missing -join ', ')], exposure $total (expected $($config.featured.exposure)). No data was changed."
  }
}
$selected = @($candidates | Sort-Object @{Expression={ if ($_.product.nwind_productname -eq $config.featured.product) { 0 } else { 1 } }}, @{Expression={$_.product.nwind_productname}} | Select-Object -First $config.maxCases)
$existingCases = Get-Rows "$($entitySets.ppcc_disruptioncase)?`$select=ppcc_disruptioncaseid,ppcc_sourcereference,_ppcc_productid_value,_ppcc_supplierid_value&`$filter=startswith(ppcc_sourcereference,'PPCC-ControlTower:')"
$existingImpacts = Get-Rows "$($entitySets.ppcc_impactedorder)?`$select=ppcc_impactedorderid,_ppcc_disruptioncaseid_value,_ppcc_orderdetailid_value"
$existingDecisions = Get-Rows "$($entitySets.ppcc_recoverydecision)?`$select=ppcc_recoverydecisionid,_ppcc_disruptioncaseid_value,ppcc_iscurrentdecision"
$casesByRef = @{}
foreach ($row in $existingCases) {
  if ($casesByRef.ContainsKey([string]$row.ppcc_sourcereference)) { throw "Duplicate seed case key '$($row.ppcc_sourcereference)'." }
  $casesByRef[[string]$row.ppcc_sourcereference] = $row
}

$plan = [Collections.Generic.List[object]]::new()
$plannedRefs = @{}
foreach ($candidate in $selected) {
  $name = [string]$candidate.product.nwind_productname
  $supplier = [string]$candidate.supplier.nwind_company
  $identity = "$name|$supplier".ToLowerInvariant()
  $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity))).Substring(0,24)
  $reference = "PPCC-ControlTower:$hash"
  if ($plannedRefs.ContainsKey($reference)) { throw "Multiple products map to seed key '$reference'." }
  $plannedRefs[$reference] = $true
  $case = $casesByRef[$reference]
  if ($case -and ($case._ppcc_productid_value -ne $candidate.product.nwind_productsid -or
                  $case._ppcc_supplierid_value -ne $candidate.supplier.nwind_suppliersid)) {
    throw "Seed case '$reference' points to different Northwind rows. Resolve stale links before reseeding."
  }
  $exposure = [decimal]0
  foreach ($line in $candidate.lines) {
    $exposure += [Math]::Round(([decimal]$line.nwind_quantity * [decimal]$line.nwind_unitprice), 2,
                              [MidpointRounding]::AwayFromZero)
  }
  $plan.Add([pscustomobject]@{
    reference = $reference; case = $case; product = $candidate.product
    supplier = $candidate.supplier; lines = $candidate.lines; exposure = $exposure
  })
}
$impactCount = [int](($plan | ForEach-Object { $_.lines.Count } | Measure-Object -Sum).Sum)
Write-Host "Control Tower demo: $($plan.Count) cases and $impactCount source-linked order lines."
if ($ValidateOnly) {
  Write-Host 'Both datasets passed preflight; no records created.'
  return [pscustomobject]@{
    Status = 'validated'; Northwind = $northwind
    Cases = $plan.Count; ImpactedOrders = $impactCount; Decisions = $plan.Count
  }
}
if ($northwind.Status -eq 'validated-empty') { $northwind = Invoke-NorthwindSeed }

$created = @{ cases = 0; impacts = 0; decisions = 0 }
foreach ($item in $plan) {
  $case = $item.case
  if (-not $case) {
    $body = @{
      ppcc_title = "Workshop supplier delay: $($item.product.nwind_productname) ($($item.supplier.nwind_company))"
      ppcc_sourcereference = $item.reference
      ppcc_source = $source
      ppcc_delaydays = [int]$config.delayDays
      ppcc_reportedon = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
      ppcc_disruptionstatus = $status
      ppcc_severity = $severity
      ppcc_recommendedaction = $action
      ppcc_recommendationsummary = 'Workshop simulation: split shipment is proposed for human review, not approved or executed.'
      ppcc_impactedordercount = $item.lines.Count
      ppcc_revenueatrisk = $item.exposure
    }
    Add-Bind $body 'ppcc_disruptioncase' 'ppcc_productid' 'nwind_products' $item.product.nwind_productsid
    Add-Bind $body 'ppcc_disruptioncase' 'ppcc_supplierid' 'nwind_suppliers' $item.supplier.nwind_suppliersid
    $headers.Prefer = 'return=representation'
    $case = Invoke-Dv $entitySets.ppcc_disruptioncase 'POST' $body
    $created.cases++
  }
  $caseId = [string]$case.ppcc_disruptioncaseid
  foreach ($line in $item.lines) {
    if (@($existingImpacts | Where-Object {
      $_._ppcc_disruptioncaseid_value -eq $caseId -and $_._ppcc_orderdetailid_value -eq $line.nwind_orderdetailsid
    }).Count) { continue }
    $order = $ordersById[[string]$line._nwind_orderid_value]
    $amount = [Math]::Round(([decimal]$line.nwind_quantity * [decimal]$line.nwind_unitprice), 2,
                            [MidpointRounding]::AwayFromZero)
    $impact = @{
      ppcc_priority = $priority
      ppcc_quantityatrisk = [decimal]$line.nwind_quantity
      ppcc_unitpricesnapshot = [decimal]$line.nwind_unitprice
      ppcc_financialexposure = $amount
      ppcc_includedinrecovery = $true
      ppcc_customerimpactsummary = "Workshop scenario for order $($order.nwind_ordernumber); source order status $($order.nwind_orderstatusid). Exposure is hypothetical, not a live fulfillment assertion."
    }
    Add-Bind $impact 'ppcc_impactedorder' 'ppcc_disruptioncaseid' 'ppcc_disruptioncase' $caseId
    Add-Bind $impact 'ppcc_impactedorder' 'ppcc_orderid' 'nwind_orders' $order.nwind_ordersid
    Add-Bind $impact 'ppcc_impactedorder' 'ppcc_orderdetailid' 'nwind_orderdetails' $line.nwind_orderdetailsid
    Invoke-Dv $entitySets.ppcc_impactedorder 'POST' $impact | Out-Null
    $created.impacts++
  }
  if (-not @($existingDecisions | Where-Object {
    $_._ppcc_disruptioncaseid_value -eq $caseId -and $_.ppcc_iscurrentdecision -eq $true
  }).Count) {
    $decision = @{
      ppcc_requestedaction = $action
      ppcc_approvalstate = $pending
      ppcc_decisionsource = $decisionSource
      ppcc_iscurrentdecision = $true
      ppcc_recommendationrationale = 'Workshop simulation: review the source-linked impact before making a human decision.'
    }
    Add-Bind $decision 'ppcc_recoverydecision' 'ppcc_disruptioncaseid' 'ppcc_disruptioncase' $caseId
    Invoke-Dv $entitySets.ppcc_recoverydecision 'POST' $decision | Out-Null
    $created.decisions++
  }
}
$verifiedCases = @(Get-Rows "$($entitySets.ppcc_disruptioncase)?`$select=ppcc_disruptioncaseid,ppcc_sourcereference,_ppcc_productid_value,_ppcc_supplierid_value&`$filter=startswith(ppcc_sourcereference,'PPCC-ControlTower:')")
$verifiedImpacts = @(Get-Rows "$($entitySets.ppcc_impactedorder)?`$select=ppcc_impactedorderid,_ppcc_disruptioncaseid_value,_ppcc_orderdetailid_value")
$verifiedDecisions = @(Get-Rows "$($entitySets.ppcc_recoverydecision)?`$select=ppcc_recoverydecisionid,_ppcc_disruptioncaseid_value,ppcc_iscurrentdecision")
foreach ($item in $plan) {
  $cases = @($verifiedCases | Where-Object ppcc_sourcereference -eq $item.reference)
  if ($cases.Count -ne 1 -or $cases[0]._ppcc_productid_value -ne $item.product.nwind_productsid -or
      $cases[0]._ppcc_supplierid_value -ne $item.supplier.nwind_suppliersid) {
    throw "Control Tower post-load verification failed for '$($item.reference)'. Re-run -ValidateOnly before retrying; no automatic reset was attempted."
  }
  $caseId = $cases[0].ppcc_disruptioncaseid
  foreach ($line in $item.lines) {
    if (@($verifiedImpacts | Where-Object {
      $_._ppcc_disruptioncaseid_value -eq $caseId -and $_._ppcc_orderdetailid_value -eq $line.nwind_orderdetailsid
    }).Count -ne 1) { throw "Control Tower post-load verification failed for order detail '$($line.nwind_orderdetailsid)'. Re-run -ValidateOnly before retrying." }
  }
  if (@($verifiedDecisions | Where-Object {
    $_._ppcc_disruptioncaseid_value -eq $caseId -and $_.ppcc_iscurrentdecision -eq $true
  }).Count -ne 1) { throw "Control Tower post-load verification failed for the current decision on '$($item.reference)'. Re-run -ValidateOnly before retrying." }
}
Write-Host "Verified $($plan.Count) cases, $impactCount impacted orders, and $($plan.Count) current decisions. Created $($created.cases) cases, $($created.impacts) impacted orders, and $($created.decisions) Pending decisions; existing business data was not changed."
[pscustomobject]@{
  Status = 'completed'; Northwind = $northwind
  Cases = $plan.Count; ImpactedOrders = $impactCount; Decisions = $plan.Count
  Created = [pscustomobject]$created
}
