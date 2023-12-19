# Template - Bicep ACR Flow

## Project Description

This project contains the flow to build and publish Bicep templates to an Azure Container Registry. The templates are located in the modules folder. The flow contains the following features:

- Build and publish Bicep templates to an Azure Container Registry.
- Versioning of the modules (only when they have changed).
- Create a wiki page for each version of a template.
- Publish those pages to a DevOps Wiki in the project.

## Members & Roles

| naam            | rol             | e-mail                         |
|-----------------|-----------------|--------------------------------|
| Jarne Segers    | DevOps engineer | <jarne.segers@delaware.pro>    |
| Donnely Defoort | DevOps engineer | <donnely.defoort@delaware.pro> |

## Extra Info

This flow will only publish a new version of a module when the module has changed. This is done by comparing the main branch with it's previous version. If the module has changed, it will be published to the Azure Container Registry and a new wiki page will be created.

### Version strategy

Versioning: `major.minor.patch` --> example: `1.0.0`

| Version      | Change                                                                                                                                |
|--------------|---------------------------------------------------------------------------------------------------------------------------------------|
| majorVersion | Breaking changes. (vb.: rename a parameter, add new parameter without default value, ...)                                             |
| minorVersion | No breaking change, but adds new functionality. (vb.: new functionality without any impact, new parameter(s) with default value, ...) |
| patch        | No breaking change and no new functionality. (vb.: bugfix for a minor or major update, config change, update descriptions, ...)       |

### How to set up

#### Prerequisites

- Azure DevOps project
- Azure Container Registry
- Azure Key Vault for storing the DevOps PAT (Personal Access Token)
- Dedicated repository to place this flow in

#### Steps

1. Place the content of this repository in the dedicated repository.
2. Add bicep modules in the modules folder.
3. Add the 2 metadata tags on top of every bicep module.

    ```bicep
    metadata majorVersion = '1'
    metadata minorVersion = '0'
    ```

4. provide the correct values in the pipeline

    ```yaml
    resources:
        repositories:
        - repository: wiki
          type: git
          name: # {devops project name}/{wiki repository name}

    variables:
        containerRegistryName: ''   # Name of the Azure Container Registry
        devOpsPatSecretName: ''     # Name of the secret in the Azure Key Vault
        keyVaultName: ''            # Name of the Azure Key Vault
        repositoryPrefix: ''        # (optional) Prefix for the repository name
        serviceConnection: ''       # Name of the service connection to Azure
        wikiRepo: ''                # Name of the wiki repository
    ```

5. Create a branch and push the changes to the repository.
6. Import the pipeline in the Azure DevOps project (only pipelines/azure-pipelines.yaml).
7. PR the changes to the main branch.
8. Run the pipeline.
9. Check the wiki for the new pages.
