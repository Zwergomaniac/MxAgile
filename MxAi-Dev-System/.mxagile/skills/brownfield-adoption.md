# Skill: Brownfield Adoption

## Goal

To analyze an existing Mendix project (an .mpr file) and reverse-engineer its domain model into a set of MxAgile `.spec` files, making the project compatible with the MxAgile workflow.

## Trigger

This skill should be invoked when the user asks to adopt an existing project, import a domain model, or create specs from an MPR file.

## Step-by-Step Process

### 1. Get Project Path

- Ask the user for the full path to the Mendix project file (`.mpr`).
- Ask for the path to the `mxcli` executable.

### 2. Analyze the .mpr File

- The `.mpr` file is an XML file (inside a zip archive). You need to read it to identify all modules and their types.
- Use a PowerShell snippet or another tool to unzip and parse the XML.

**Example PowerShell to list modules and their type:**

```powershell
param([string]$MprPath)

[System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
$zip = [System.IO.Compression.ZipFile]::OpenRead($MprPath)
$mprEntry = $zip.GetEntry('Project.mpr')
$stream = $mprEntry.Open()

$xml = [xml](New-Object System.IO.StreamReader($stream)).ReadToEnd()

$stream.Close()
$zip.Dispose()

$modules = @{}
# Select all AppStoreModules and ProjectModules
$xml.Project.AppStoreModules.AppStoreModule | ForEach-Object { $modules[$_.Name] = "Marketplace" }
$xml.Project.ProjectModules.ProjectModule | ForEach-Object { $modules[$_.Name] = "Custom" }

# You can add logic here to identify Platform modules by name prefix if needed
# For example:
# foreach ($name in $modules.Keys) {
#   if ($name.StartsWith("MB_")) { $modules[$name] = "Platform" }
# }

return $modules | ConvertTo-Json
```

- Execute this logic to get a JSON map of `ModuleName: Type`.

### 3. Export Domain Model using mxcli

- For each module identified in the previous step (excluding `System` and `Administration`):
    - **Get Entities:** Run `mxcli -p <MprPath> -c "SHOW ENTITIES IN <ModuleName>"`.
    - **Get Associations:** Run `mxcli -p <MprPath> -c "SHOW ASSOCIATIONS IN <ModuleName>"`.

### 4. Generate .spec Files

- Create a temporary directory to store the full MDL descriptions.
- Loop through every entity and every association from the previous step.
- For each one, run the appropriate `DESCRIBE` command and save the output to a file:
    - `mxcli -p <MprPath> -c "DESCRIBE ENTITY <Module.EntityName>" > temp/Module_Entity.mdl`
    - `mxcli -p <MprPath> -c "DESCRIBE ASSOCIATION <Module.AssocName>" > temp/Module_Assoc.mdl`

- Now, loop through the generated `.mdl` files in your temporary directory.
- For each file:
    - **Parse the content:** Extract the name, attributes, etc.
    - **Determine Module Type:** Look up the module's type from the JSON map you created in Step 2.
    - **Generate a Spec ID:** Create a new, unique ID (e.g., `SP-001`, `SP-002`).
    - **Construct the `.spec` file content** with the appropriate flags:

        **For a Custom Module Entity:**
        ```
        ID: SP-XXX
        Type: CustomModule
        Mutable: true
        Description: Defines the ... entity.
        ENTITY: ...
        ```

        **For a Marketplace/Platform Module Entity:**
        ```
        ID: SP-YYY
        Type: MarketplaceModule
        Mutable: false
        Description: Defines the ... entity from the read-only ... module.
        ENTITY: ...
        ```

    - **Save the file:** Write the content to `specs/<ModuleName>_<ElementName>.spec`.

### 5. Final Cleanup

- Delete the temporary directory containing the intermediate MDL files.
- Inform the user that the adoption is complete and that they should review the generated `.spec` files.
