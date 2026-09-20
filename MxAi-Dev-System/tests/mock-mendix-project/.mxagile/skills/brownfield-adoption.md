# Skill: Brownfield Adoption

## Goal

To analyze an existing Mendix project and any related documentation to reverse-engineer its domain model into a set of well-described MxAgile `.spec` files.

## Trigger

This skill should be invoked when the user asks to adopt an existing project, import a domain model, or create specs from an MPR file.

## Step-by-Step Process

### 1. Gather Context

- **Ask for Project Path:** Get the full path to the Mendix project file (`.mpr`) and the `mxcli` executable from the user.
- **Ask for Existing Artifacts:** Ask the user if they have any existing documentation that describes the project (e.g., Markdown files, HTML mockups, sprint plans, user stories). 
- **Read Artifacts:** If they provide file paths, read the content of these files. This content will serve as crucial context for writing meaningful descriptions in the generated `.spec` files.

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
$xml.Project.AppStoreModules.AppStoreModule | ForEach-Object { $modules[$_.Name] = "Marketplace" }
$xml.Project.ProjectModules.ProjectModule | ForEach-Object { $modules[$_.Name] = "Custom" }

# You can add logic here to identify Platform modules by name prefix if needed

return $modules | ConvertTo-Json
```

- Execute this logic to get a JSON map of `ModuleName: Type`.

### 3. Export Domain Model using mxcli

- For each module identified (excluding `System` and `Administration`):
    - **Get Entities:** Run `mxcli -p <MprPath> -c "SHOW ENTITIES IN <ModuleName>"`.
    - **Get Associations:** Run `mxcli -p <MprPath> -c "SHOW ASSOCIATIONS IN <ModuleName>"`.

### 4. Generate .spec Files

- Create a temporary directory to store the full MDL descriptions for each element.
- Loop through every entity and association and use the appropriate `DESCRIBE` command, saving the output to a file in the temp directory.
- Now, loop through the generated `.mdl` files in the temporary directory.
- For each file:
    - **Parse the content** to extract its structure (name, attributes, etc.).
    - **Determine Module Type** from the map created in Step 2.
    - **Generate a Spec ID** (e.g., `SP-001`).
    - **Write a meaningful description:** Instead of a generic message, use the context from the artifacts gathered in Step 1 to write a relevant description for the `Description:` field.
    - **Construct the `.spec` file content** with the appropriate flags (`Type:`, `Mutable:`).
    - **Save the file:** Write the content to `specs/<ModuleName>_<ElementName>.spec`.

### 5. Final Cleanup

- Delete the temporary directory.
- Inform the user that the adoption is complete and that they should review the generated `.spec` files.
