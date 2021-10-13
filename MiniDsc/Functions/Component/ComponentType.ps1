if(!([System.Management.Automation.PSTypeName]"Component").Type)
{
    Add-Type -Language CSharp @"
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;

public class Component
{
    public static Dictionary<string, Component> KnownComponents { get; set; }

    public static object IsPermanent { get; set; }

    public string Type { get; set; }
    public Component Parent { get; set; }
    public Component[] Children { get; set; }
    
    [Hidden]
    public string ForEach { get; set; }

    [Hidden]
    public Hashtable Vars { get; set; }

    static Component()
    {
        KnownComponents = new Dictionary<string, Component>();
        IsPermanent = new object();
    }

    public Component(string type)
    {
        Type = type;
        Vars = new Hashtable();
    }

    public static Component GetComponentPrototype(string name)
    {
        Component component;

        if (KnownComponents.TryGetValue(name, out component))
            return component;

        throw new InvalidOperationException(string.Format("Component '{0}' is not defined.", name));
    }

    public override string ToString()
    {
        var pso = new PSObject(this);

        var method = pso.Methods.FirstOrDefault(m => m.Name == "ToString");

        if (method != null)
        {
            var result = method.Invoke();

            if (result != null)
                return result.ToString();
        }

        return base.ToString();
    }
}
"@
}