# Odoo Hosting in AWS Costs

## Free tier

This module is configured to be covered entirely by the [AWS free tier](https://aws.amazon.com/free/) by default (assuming `us-east-1` as region to deploy and no other resources deployed in the account). The main savings being used from the free tier are:

- EC2 instance used as ECS node: a `t3.micro` with 2 vCPU and 1gb of ram is used by default, supporting up to ~20 users connected concurrently.

- RDS instance: a `db.t4g.micro` with 20gb of storage is used by default. The DB is set to autoexpand capacity up to 100gb if needed (the free tier only supports the initial 20gb, which is the initial space allocation recommended for 20 users).

- ALB: the load balancer monthly fixed cost is included in the free tier, and up to 15 LCUs (aproximatelly 15gb/hour processed).

- CDN: 1TB of data out from the CDN.

>The main compromise solution between a well architected design and a free design is done at the network level.
> AWS Nat Gateways are not included in the free tier, and therefore, a proper design of the base VPC and its subnets can not be done without incurring costs.
> By default, Nat Gateways are not created and public subnets are used to create the EC2 instances acting as ECS nodes; the RDS db is created under a separate set of subnets (`database subnets`) which don't have access to internet, so this doesn't affect its behavior.
> To change this, set the `deploy_nat` variable to true.

## On demand

Assuming we are deploying in AWS' main region (`us-east-1`) and using only on-demand resources, the default parameters set in the module support up to 20 concurrent users, and the cost of the infrastructure is ~52usd/month.

The estimate can be found in [this AWS calculator](https://calculator.aws/#/estimate?id=7086ea150b55d201fc6b96f5062dbcfc1648ab1b).

## With reservations

If we continue with the assumption of main region and default parameters, cost saving can be applied with reservations. Different reservation parameters will vary the savings, but as an example:

- **1 year commitment with no upfront**: ~**46usd/month** -> [AWS calculator](https://calculator.aws/#/estimate?id=074124db7c2c9af32dd2ec6ab0113cb3f1ab1afc)

- **1 year commitment with all upfront** (only compute can be paid upfront): ~**32usd/month** and ~**150usd** upfront -> [AWS calculator](https://calculator.aws/#/estimate?id=883962e90ca2bd65c9a4c756986f929482ec42b5)
