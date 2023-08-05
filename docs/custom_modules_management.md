# Odoo Custom Modules

Odoo custom modules can be installed in the infrastructure deployed with this module. For that, two different processes are exposed through variables:

## Custom python dependencies

When using custom modules, the python environment running odoo server might need extra packages installed. The default docker image used by this module is `bitnami/odoo:16`, which has all the default dependencies needed for the community version of odoo in a python venv installed in `/opt/bitnami/odoo/venv`.

When a `requirements.txt` file is provided through the `python_requirements_file` variable, some resources are created to be able to create and use a new docker image based on the bitnami one:

1. An **AWS ImageBuilder** pipeline with instructions to build a new docker image
2. An **AWS ECR** repository to store the new image
3. A **S3** bucket to store the new requirements file
4. **EventBridge** and **SSM Automations** to trigger the build

### Process reference:

![ECR build](../images/ECR-build.svg)

## Custom modules

To install custom modules, we need to store the source code of the modules in a place accessible by the odoo server processes. To do this, the variable `odoo_custom_modules_paths` allows to send a list of directories where the custom modules' source code is.

> The paths sent to this variable should not be the path to the modules, but to a parent folder containing the modules to be installed.
> This is behavior is intended so we can clone repositories containing custom modules code and point to them.
> It is suggested to version the code used to deploy and point to the custom modules repositories with git submodules.

In addition, if python packages must be provided with the compiled source code (for example for private packages or packages not available to be installed with pip), an extra variable `odoo_python_dependencies_paths` is provided to send python packages that will be installed by copying them in an extra packages folder pointed in the odoo servers containers with the `PYTHONPATH` environment variable.

> This is not the recommended way of customizing the packages installed in the python virtual environment used by odoo, it is exposed for specific use cases.
> If possible, prefer to use the `python_requirements_file` variable.

In these two cases, some extra resources are created to install these files:

1. A **S3** bucket to store files
2. **AWS DataSync** locations and tasks to sync s3 objects to EFS
3. **EventBridge** and **SSM automation** resources to use as triggers of the sync tasks

### Process reference:

![S3 sync](../images/S3-sync.svg)
