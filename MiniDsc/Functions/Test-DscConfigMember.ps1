function Test-DscConfigMember($config, $record)
{
    $path = ""

    $root = $record["Path"] | select -first 1

    if($root -ne $null)
    {
        $path = $root.TrimEnd('[',']')

        $config = $config.($root.TrimEnd('[',']'))
    }

    $isArray = if($root -ne $null) { $root.EndsWith("[]") } else { $false }

    DoVerify $config $record $path $isArray
}

function DoVerify($config, $record, $path, $isArray, $ignoreLeaves = $false)
{
    $root = $record["Path"] | select -first 1
    $leaves = $record["Path"] | select -Skip 1

    if($isArray)
    {
        $i = 0

        foreach($entry in $config)
        {
            DoVerify $entry $record "$path[$i]" $false $ignoreLeaves

            $i++
        }

        return
    }
    else
    {
        if($leaves -ne $null -and !$ignoreLeaves)
        {
            foreach($r in @($leaves))
            {
                $path = "$path.$($r.TrimEnd('[',']'))"

                $config = $config.$($r.TrimEnd('[',']'))
            }

            if(($leaves|select -last 1).EndsWith("[]"))
            {
                DoVerify $config $record $path $true $true
                return
            }
        }
    }

    $members = $config.PSObject.Properties.Name

    $missing = (GetMissing $config $record["Children"] $members $isArray)|where { $_ -notlike "*\?" }
    $extra = (GetMissing $config $members $record["Children"] $isArray)|where { $_ -notlike "*\?" }

    if(!$path)
    {
        $path = "<Root>"
    }

    if($missing)
    {
        throw "Config at path '$path' did not contain mandatory member(s) $(($missing|foreach { "'$_'" }) -join ",")"
    }

    if($extra)
    {
        throw "Config at path '$path' contained extra member(s) $(($extra|foreach { "'$_'" }) -join ",")"
    }
}

function GetMissing($config, $first, $second, $isArray)
{
    $missing = @()

    foreach($entry in $first)
    {
        if(!($entry -in $second))
        {
            $missing += $entry
        }
    }

    return $missing
}