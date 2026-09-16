[CmdletBinding()]
param(
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceUrl = 'https://www.microsoft.com/en-us/wdsi/defenderupdates'

function Get-LatestMicrosoftDefenderVersion {
    [CmdletBinding()]
    param()

    $response = Invoke-WebRequest `
        -Uri $SourceUrl `
        -UseBasicParsing `
        -TimeoutSec 30 `
        -Headers @{ 'User-Agent' = 'Mozilla/5.0' }

    if (-not $response.Content) {
        throw 'Microsoft Defender update page returned no content.'
    }

    # Convert the Microsoft page to normalized plain text so the parser is not
    # coupled to a specific HTML tag layout.
    $plainText = $response.Content
    $plainText = [regex]::Replace($plainText, '(?is)<script.*?</script>', ' ')
    $plainText = [regex]::Replace($plainText, '(?is)<style.*?</style>', ' ')
    $plainText = [regex]::Replace($plainText, '(?s)<[^>]+>', ' ')
    $plainText = [System.Net.WebUtility]::HtmlDecode($plainText)
    $plainText = [regex]::Replace($plainText, '\s+', ' ')

    $pattern = @'
Latest security intelligence update.*?Version:\s*(?<Intelligence>\d+\.\d+\.\d+\.\d+)\s+Engine Version:\s*(?<Engine>\d+\.\d+\.\d+\.\d+)\s+Platform Version:\s*(?<Platform>\d+\.\d+\.\d+\.\d+)\s+Released:\s*(?<Released>.+?)\s+Documentation:
'@

    $match = [regex]::Match(
        $plainText,
        $pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $match.Success) {
        throw 'Could not parse the current Defender versions from the Microsoft Security Intelligence page. The site format may have changed.'
    }

    [pscustomobject]@{
        SecurityIntelligenceVersion = $match.Groups['Intelligence'].Value
        EngineVersion               = $match.Groups['Engine'].Value
        PlatformVersion             = $match.Groups['Platform'].Value
        Released                    = $match.Groups['Released'].Value.Trim()
        RetrievedAtUtc              = (Get-Date).ToUniversalTime().ToString('o')
        Source                      = $SourceUrl
    }
}

$result = Get-LatestMicrosoftDefenderVersion

if ($AsJson) {
    $result | ConvertTo-Json -Depth 4
}
else {
    $result
}
