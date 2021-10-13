# MiniDsc

MiniDsc is a lightweight framework for performing infrastructure as code using PowerShell.

MiniDsc serves to resolve some of the [major deficiencies](https://github.com/lordmilko/MiniDsc/wiki/What's-Wrong-with-Terraform-and-PowerShell-DSC%3F) found in more well established tools such as Terraform and Regular PowerShell DSC. MiniDsc aims to be as dynamic as possible, generating all of the underlying plumbing required to use a given resource from a minimal configuration definition.

## Overview

Configuration resources in MiniDsc are defined via the use of *components*. Each *component* describes how to apply, revert or test it to see if it has already been applied.

Suppose we want to ensure a folder exists at a specified destination. To do so, we can utilize a `Folder` component. Here is how the `Folder` component can be defined

```powershell
Component Folder @{
    Name = $null

    Apply  = { New-Item    $this.GetPath() -ItemType Directory | Out-Null }
    Revert = { Remove-Item $this.GetPath() -Recurse -Force | Out-Null }
    Test   = { Test-Path   $this.GetPath() }

    GetPath = {
        if ($this.Parent) {
            return [IO.Path]::Combine($this.Parent.GetPath(), $this.Name)
        }

        return $this.Name
    }
}
```

When this component is declared, the `Component` function *basically* defines a brand new Folder "class" based on the specified component definition containing a `Name` property, `Apply`, `Revert`, `Test` and `GetPath` methods, as well as several other members that the framework ensures that all component items have. In addition to this, an automatic `Folder` *function* is declared that we will be able to use to instantiate *instances* of our Folder class

```powershell
C:\> Folder foo

Name Type   Parent Children
---- ----   ------ --------
foo  Folder                
```

On Windows systems at least, we probably also want to specify a *drive* to indicate where our folder should go. In a sense, a drive is also a type of folder. The `Component` function can model such relationships for us

```powershell
Component Drive -Extends Folder @{
    Apply={}
    Revert={}

    Test={
        if(!(Test-Path $this.GetPath())) {
            throw "Cannot process drive '$($this.Name)': drive does not exist"
        }

        return $true
    }

    GetPath={ $this.Name + "\" }
}
```

By specifying the `-Extends` parameter, we effectively create a new "class" `Drive` that inherits from the base `Folder` "class". We then override any of the methods whose functionality should be different in this class, and presto! We have our `Drive` component definition

Now we can easily define a bunch of folders under our drive!

```powershell
Drive C: {
    Folder foo {
        Folder bar
    }
}
```

Configuration in MiniDsc is done in a hierarchical manner by describing a tree like structure. Simply by *looking* at the configuration you can easily grasp the relationships between the various components. Each `Component` (`Drive` and `Folder`) takes an optional `ScriptBlock` describing its *children*. Any component objects that are returned from this `ScriptBlock` will be incorporated into the parent object. As such you are free to do whatever custom programming logic you like

```powershell
# Describe the folders C:\foo, C:\bar and C:\baz
Drive C: {
    "foo","baz","bar" | foreach { Folder $_ }
}
```

Once we've defined our configuration, it's simply a matter of applying it

```powershell
# Describe the configuration
$tree = Drive C: {
    "foo","baz","bar" | foreach { Folder $_ }
}

# Apply the configuration
$tree | Invoke-MiniDsc -Apply
```

It's as easy as that! The hard part is simply defining all the little components you'll need in order to achieve your goal. If somebody else has already written some of these components, that just makes things even easier for you.

For more information, including advanced configuration scenarios, please see the [wiki](https://github.com/lordmilko/MiniDsc/wiki).