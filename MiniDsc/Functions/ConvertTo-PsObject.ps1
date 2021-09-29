function ConvertTo-PsObject {
    param (
        [hashtable] $Value
    )

    $newValue = @{}

    foreach($key in $Value.GetEnumerator() | foreach { $_.Name })
    {
        if($Value[$key] -eq $null)
        {
            $newValue[$key] = $Value[$key]
        }
        elseif($Value[$key].GetType() -eq @{}.GetType())
        {
            $newValue[$key] = ConvertTo-PsObject $Value[$key]
        }
        elseif($Value[$key].GetType().IsArray -and $Value[$key][0].GetType() -ne [string])
        {
            $newValue[$key] = $Value[$key] | foreach { ConvertTo-PsObject $_ }
        }
        else
        {
            $newValue[$key] = $Value[$key]
        }
    }

    [PSCustomObject]$newValue
}