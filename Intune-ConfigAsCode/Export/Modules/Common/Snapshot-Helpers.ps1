function Get-GraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $Items = [System.Collections.Generic.List[object]]::new()
    $VisitedUris = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    while (-not [string]::IsNullOrWhiteSpace($Uri)) {
        if (-not $VisitedUris.Add($Uri)) {
            throw "Microsoft Graph returned a repeated pagination link: '$Uri'."
        }

        $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri

        if ($Response -is [System.Collections.IDictionary]) {
            if ($Response.Contains('value')) {
                foreach ($Item in @($Response['value'])) {
                    $Items.Add($Item)
                }
            }

            $Uri = if ($Response.Contains('@odata.nextLink')) {
                [string]$Response['@odata.nextLink']
            }
            else {
                $null
            }
        }
        else {
            foreach ($Item in @($Response.value)) {
                $Items.Add($Item)
            }

            $NextLinkProperty = $Response.PSObject.Properties['@odata.nextLink']
            $Uri = if ($null -ne $NextLinkProperty) {
                [string]$NextLinkProperty.Value
            }
            else {
                $null
            }
        }
    }

    return $Items.ToArray()
}

function Add-SnapshotProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        $InputObject[$Name] = $Value
    }
    else {
        $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Get-SnapshotPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }

    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $Property) {
        return $Property.Value
    }
    return $null
}

function ConvertTo-OrderedSnapshotObject {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive -or
            $InputObject -is [decimal] -or $InputObject -is [datetime] -or
            $InputObject -is [datetimeoffset] -or $InputObject -is [guid]) {
            return $InputObject
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $Result = [ordered]@{}
            foreach ($Key in @($InputObject.Keys) | Sort-Object { [string]$_ }) {
                if ([string]$Key -notin @('@odata.context', '@odata.nextLink')) {
                    $Result[[string]$Key] = ConvertTo-OrderedSnapshotObject -InputObject $InputObject[$Key]
                }
            }
            return $Result
        }

        if ($InputObject -is [System.Collections.IEnumerable]) {
            $Result = [System.Collections.Generic.List[object]]::new()
            foreach ($Item in $InputObject) {
                $Result.Add((ConvertTo-OrderedSnapshotObject -InputObject $Item))
            }
            return ,$Result.ToArray()
        }

        $Result = [ordered]@{}
        foreach ($Property in $InputObject.PSObject.Properties | Sort-Object Name) {
            if ($Property.Name -notin @('@odata.context', '@odata.nextLink')) {
                $Result[$Property.Name] = ConvertTo-OrderedSnapshotObject -InputObject $Property.Value
            }
        }
        return $Result
    }
}

function Get-SnapshotFileName {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Id
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = $Id
    }

    $SafeName = ($Name -replace '[\\/:*?"<>|]', '_').Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($SafeName)) {
        $SafeName = 'unnamed'
    }

    $SafeId = ($Id -replace '[\\/:*?"<>|]', '_').Trim().TrimEnd('.')

    # The ID makes duplicate display names collision-safe while remaining stable.
    return '{0}__{1}.json' -f $SafeName, $SafeId
}

function Export-SnapshotObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter(Mandatory)]
        [scriptblock]$NameScript
    )

    $ParentPath = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $ParentPath -PathType Container)) {
        New-Item -ItemType Directory -Path $ParentPath -Force | Out-Null
    }

    $LeafName = Split-Path -Leaf $OutputPath
    $StagePath = Join-Path $ParentPath ('.{0}.staging-{1}' -f $LeafName, [guid]::NewGuid().ToString('N'))
    $BackupPath = Join-Path $ParentPath ('.{0}.backup-{1}' -f $LeafName, [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $StagePath -Force | Out-Null

    try {
        foreach ($Item in @($InputObject)) {
            $Id = [string]$Item.id
            if ([string]::IsNullOrWhiteSpace($Id)) {
                throw "Cannot export an object without an id to '$OutputPath'."
            }

            $DisplayName = [string](& $NameScript $Item)
            $FileName = Get-SnapshotFileName -Name $DisplayName -Id $Id
            $FilePath = Join-Path $StagePath $FileName

            $OrderedObject = ConvertTo-OrderedSnapshotObject -InputObject $Item
            $Json = $OrderedObject | ConvertTo-Json -Depth 100
            Set-Content -LiteralPath $FilePath -Value $Json -Encoding utf8
            Write-Host "   [+] $DisplayName" -ForegroundColor Green
        }

        $ExistingSnapshotMoved = $false
        if (Test-Path -LiteralPath $OutputPath) {
            Move-Item -LiteralPath $OutputPath -Destination $BackupPath
            $ExistingSnapshotMoved = $true
        }

        try {
            Move-Item -LiteralPath $StagePath -Destination $OutputPath
        }
        catch {
            if ($ExistingSnapshotMoved -and -not (Test-Path -LiteralPath $OutputPath)) {
                Move-Item -LiteralPath $BackupPath -Destination $OutputPath
                $ExistingSnapshotMoved = $false
            }
            throw
        }

        if ($ExistingSnapshotMoved -and (Test-Path -LiteralPath $BackupPath)) {
            Remove-Item -LiteralPath $BackupPath -Recurse -Force
        }
    }
    catch {
        if (Test-Path -LiteralPath $StagePath) {
            Remove-Item -LiteralPath $StagePath -Recurse -Force
        }
        throw
    }
}

function Get-GraphObjectWithRelatedData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ObjectUri,

        [string[]]$RelatedCollections = @()
    )

    $Object = Invoke-MgGraphRequest -Method GET -Uri $ObjectUri
    foreach ($CollectionName in $RelatedCollections) {
        $Collection = @(Get-GraphCollection -Uri "$ObjectUri/$CollectionName" | Sort-Object id)
        Add-SnapshotProperty -InputObject $Object -Name $CollectionName -Value @($Collection)
    }

    return $Object
}

function Export-GraphSnapshotCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$RelativeOutputPath,

        [Parameter(Mandatory)]
        [string]$CollectionUri,

        [scriptblock]$FilterScript = { $true },

        [scriptblock]$NameScript = {
            param($Item)
            $DisplayName = [string](Get-SnapshotPropertyValue -InputObject $Item -Name 'displayName')
            $Name = [string](Get-SnapshotPropertyValue -InputObject $Item -Name 'name')
            if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
                $DisplayName
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Name)) {
                $Name
            }
            else {
                Get-SnapshotPropertyValue -InputObject $Item -Name 'id'
            }
        },

        [string[]]$RelatedCollections = @(),

        [string]$Label = $RelativeOutputPath
    )

    Write-Host "Exporting $Label..." -ForegroundColor Cyan

    $Items = @(Get-GraphCollection -Uri $CollectionUri | Where-Object $FilterScript)
    $DetailedItems = [System.Collections.Generic.List[object]]::new()

    foreach ($Item in $Items) {
        $ObjectUri = '{0}/{1}' -f $CollectionUri.TrimEnd('/'), $Item.id
        if ($RelatedCollections.Count -gt 0) {
            $DetailedItems.Add((Get-GraphObjectWithRelatedData -ObjectUri $ObjectUri -RelatedCollections $RelatedCollections))
        }
        else {
            # Collection responses are sufficient for simple resources. Avoid an
            # extra request per object unless related data is required.
            $DetailedItems.Add($Item)
        }
    }

    $OutputPath = Join-Path $RepositoryRoot $RelativeOutputPath
    Export-SnapshotObjects -OutputPath $OutputPath -InputObject $DetailedItems.ToArray() -NameScript $NameScript

    Write-Host "Exported $($DetailedItems.Count) $Label object(s)." -ForegroundColor Green
    Write-Host ''
}
