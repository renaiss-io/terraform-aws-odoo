# Odoo in AWS

This module deploys [odoo](https://odoo.com) in AWS using:

- ECS backed with EC2 to run the containerized version of odoo server
- RDS for the postgres database
- EFS as a filesystem for odoo's filestore
- SES as a mail gateway
- CloudFront as a CDN with cache capabilities
- AWS Secrets to store credentials

## Architecture reference

![Architecture diagram](images/Diagram.svg)
