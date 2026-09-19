# Company Layers

Company Layers are a powerful feature of MxAgile that allow organizations to inject their own standards, best practices, and reusable components into the framework. A layer is essentially a portable, version-controlled collection of company-specific assets.

This allows the core MxAgile framework to remain generic, while individual projects can be tailored to a specific company's ecosystem.

## Creating a Company Layer

To create a new layer, a company architect would typically do the following:

1.  **Scaffold a New Layer:** In the future, a script (`mxagile-new-layer.ps1`) will automate this. For now, you can copy the structure from an existing layer or the `company-layer-template` directory in the MxAgile template repository.

2.  **Customize the Content:** Edit the files within the layer directory:
    - **`layer.json`**: A manifest file. The `id` field is critical and must be unique.
    - **`glossary.md`**: Define standard business and technical terms.
    - **`platform-modules.md`**: List required Mendix modules for all company projects.
    - **`modules/`**: Add company-specific reusable Mendix modules (e.g., connectors, process templates) as `.mpk` files or MDL source.

3.  **Publish to Git:** The entire layer directory should be committed to its own Git repository to make it accessible to developers.

## Using a Company Layer in a Project

Once a company layer has been published, a developer can add it to their MxAgile-enabled Mendix project.

1.  **Run the `add-layer` script:** From the root of your Mendix project, run the `mxagile-add-layer.ps1` script, providing the URL of the layer's Git repository.

    ```powershell
    ./scripts/mxagile-add-layer.ps1 -RepositoryUrl "https://github.com/your-company/our-mendix-layer.git"
    ```

2.  **What it Does:**
    - The script clones the layer repository.
    - It copies the contents into your project under `.mxagile/layers/<layer-id>/`.
    - Future versions will automatically integrate the content, such as importing the Mendix modules from the `modules/` directory.

This makes it simple to ensure that all projects are consistently aligned with company standards.