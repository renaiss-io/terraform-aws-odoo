# Odoo in AWS

This module deploys [odoo](https://odoo.com) in AWS using:

- **ECS** backed with EC2 to run the containerized version of odoo server
- **RDS** for the postgres database
- **EFS** as a filesystem for odoo's filestore
- **SES** as a [mail gateway](docs/ses_as_mail_gateway.md)
- **CloudFront** as a CDN with cache capabilities
- **Secrets Manager** to store credentials

To [manage custom modules](docs/custom_modules_management.md):

- **S3** to store custom modules files
- **EventBridge** to manage event driven actions
- **DataSync** to sync S3 custom module files to EFS
- **ECR** to store a custom docker image in case of extra python dependencies
- **ImageBuilder** to define a build pipeline for a custom docker image
- **SSM automations** to execute DataSync tasks and ImageBuilder pipelines

## Architecture reference

![Architecture diagram](images/Main.svg)
