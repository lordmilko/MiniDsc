Component Folder @{
    Name = $null

    Apply    = { New-Item    $this.GetPath() -ItemType Directory | Out-Null }
    Revert   = { Remove-Item $this.GetPath() -Recurse -Force | Out-Null     }
    Test     = { Test-Path   $this.GetPath()                                }

    VerifyParent={
        param($parent)

        if ($parent.Type -ne "Folder" -and $parent.Type -ne "Drive")
        {
            throw "The parent of a folder component must be either a Folder or a Drive"
        }
    }

    GetPath = {
        if ($this.Parent)
        {
            return [IO.Path]::Combine($this.Parent.GetPath(), $this.Name)
        }

        return $this.Name
    }
}

Component Drive -Extends Folder @{
    Apply={}
    Revert={}

    Test={
        if(!(Test-Path $this.GetPath()))
        {
            throw "Cannot process drive '$($this.Name)': drive does not exist"
        }

        return [Component]::IsPermanent
    }

    GetPath={ $this.Name + "\" }
}