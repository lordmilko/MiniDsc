Component RegistryHive @{
    Name=$null

    Test={
        return [Component]::IsPermanent
    }

    Verify={
        $item = Get-Item -Path Registry::$($this.Name.TrimEnd(":")) -ErrorAction SilentlyContinue

        if(!$item)
        {
            throw "Value '$($this.Name)' could not be resolved as the name or alias of a valid registry hive"
        }
        else
        {
            $this.Name = $item.Name
        }
    }

    GetPath={
        return $this.Name
    }
}

Component RegistryKey @{
    Name=$null

    Init={
        
        if(Split-Path $this.Name -IsAbsolute)
        {
            return
        }

        if($this.Parent -ne $null -and $this.Parent.Type -eq "RegistryHive")
        {
            return
        }

        throw "The parent of a RegistryKey must be a RegistryHive when an absolute registry path is not specified"

        #todo: we can either check our parent for a registryhive or do split-path is absolute. similarly,
        #getpath() returns the path if split-path is absolute or merges us with the hive if it isnt

        #todo: when we revert, we dont want to inadvertently delete system keys! we only want to delete keys that we added!

        throw "the parent of this object must either be a registryhive, or the path that was specified points to the hive we're interested in."
        throw "either way there should be a getpath method or something that combines the relative path in this object with the hive in the parent object or returns the single path contained in this object that specifies both the hive and key"
    }

    Test={
        $path = $this.GetPath()

        throw
    }

    Revert={
        throw "we dont want to remove registry keys that already existed!"
    }

    GetPath={
        if(Split-Path $this.Name -IsAbsolute) #todo: this doesnt work. HKLM\SOFTWARE returns false, but Registry::HKLM\SOFTWARE works, but Registry::HKLM:\SOFTWARE doesnt work. maybe we should split-path for the qualifier, trim the trailing : and check whether that matches a known psdrive?
        {
            return $this.Name
        }

        return Join-Path $this.Parent.GetPath() $this.Name
    }
}

Component RegistryValue @{
    #todo: either it MUST be the child of a registrykey, or we allow specifying the registrykey info to this cmdlet as an optional parameter as well? this would then supercede the parent registrykey this component is contained in
    #(and we'd need a test for that)
}