# Layer Management

This document outlines the management of Company Layers within the MxAgile framework.

## Structure

- `company-layers/`: The local registry. This is where you develop, version control, and maintain the source of truth for your company-wide layers. It is *not* used directly by the framework at runtime.
- `.mxagile/layers/`: The active, authoritative directory. The framework scans this directory for layers to apply to the project.

## Managing Layers

### Activating a Layer
To make a layer from your registry active, you must make it available within `.mxagile/layers/`.

**For Development:**
Use a symbolic link to ensure changes in `company-layers/` are immediately reflected in the active layer set.
```bash
ln -s ../../company-layers/<layer-name> .mxagile/layers/<layer-name>
```

**For Deployment/Stable Releases:**
Copy the files directly to ensure the active layer is pinned to a specific version.
```bash
cp -r company-layers/<layer-name> .mxagile/layers/<layer-name>
```

## Basic Workflow

1. **Develop/Edit**: Work on your layer files inside `company-layers/<layer-name>`.
2. **Validate**: Run framework validation tools to ensure the layer is correct.
3. **Activate**: Link or copy the layer to `.mxagile/layers/`.
4. **Apply**: Re-run framework operations to incorporate changes.

