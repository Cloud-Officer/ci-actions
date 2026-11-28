# AWS CodeDeploy GitHub Actions

A collection of AWS CodeDeploy GitHub Actions.

* [checkout](checkout/README.md) checks out the code in preparation for the archive creation
* [deploy](deploy/README.md) triggers a CodeDeploy deployment
* [asg-rollout](asg-rollout/README.md) builds the standalone AMIs and rolls the auto scaling groups out through the deploy-runner CodeBuild project
* [s3copy](s3copy/README.md) uploads an archive to an AWS S3 bucket
