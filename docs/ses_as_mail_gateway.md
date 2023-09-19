# Odoo Mail Gateway

This module implements SES as a mail gateway for Odoo. This is done by creating an [IAM user with permissions to send emails with access keys that are stored in AWS Secrets Manager](../main.tf#L747-#L789) and exposed as environment variables to the odoo server containers (via [ECS task definition secrets](../main.tf#L654-#L657)).

This means that any email sent from Odoo will use SES as a gateway. For this to work, two actions need to be done in the AWS account and region where odoo is deployed:

1. Any email origin must be validated in SES. This can be done by validating each source email manually or validating a domain.

2. The account must be taken out of the sandbox in the region used to be able to increase the daily limits of emails that can be send, and to allow non-verified emails as destinations.
