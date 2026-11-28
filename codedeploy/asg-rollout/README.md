# GitHub Action: ASG rollout

This action builds the AMIs of the standalone instances and rolls the auto scaling groups out by starting the
`deploy-runner` CodeBuild project of the account (`deploy.rb` with automatic rollback, created by the codedeploy stack
of `Cloud-Officer/aws`) and following it until it ends. Use it after [deploy](../deploy/README.md) has put the new code
on the standalone instances, instead of running `deploy.rb` on a workstation.

## Inputs

```yml
inputs:
  aws-access-key-id:
    description: 'aws access key id; leave empty when aws-role-to-assume is set'
    required: false
  aws-secret-access-key:
    description: 'aws secret access key; leave empty when aws-role-to-assume is set'
    required: false
  aws-region:
    description: 'aws region of the deploy-runner project'
    required: true
  aws-role-to-assume:
    description: 'ARN of the IAM role to assume with GitHub OIDC instead of access keys; the job needs permissions: id-token: write'
    required: false
  aws-audience:
    description: 'audience of the GitHub OIDC token'
    required: false
    default: 'sts.amazonaws.com'
  aws-role-session-name:
    description: 'session name recorded in CloudTrail for the assumed role'
    required: false
    default: 'GitHubActions'
  aws-role-duration-seconds:
    description: 'lifetime of the assumed role credentials, in seconds; cover the whole rollout'
    required: false
    default: '10800'
  environment:
    description: 'environment to roll out, such as beta1, rc5 or prod3'
    required: true
  instances:
    description: 'comma-separated instances whose standalone AMI is built and whose auto scaling group is rolled out: api, grpc, worker, ml'
    required: true
  flags:
    description: 'extra deploy.rb flags allowed by deploy-runner: --redeploy-latest, --patch-standalone, --sequential_rollout, --skip_scale_down, --preserve_desired_capacity'
    required: false
    default: ''
  project-name:
    description: 'CodeBuild project that runs deploy.rb'
    required: false
    default: 'deploy-runner'
  monitor-timeout-minutes:
    description: 'how long to follow the build before failing the step'
    required: false
    default: '180'
```

The step checks the inputs, starts the build with only the `DEPLOY_ENVIRONMENT`, `DEPLOY_INSTANCES` and `DEPLOY_FLAGS`
overrides (the only ones the `github-actions` role may pass), prints the build log in the job as it runs, and exits 0
only when the build succeeds. A failed, stopped or timed-out build fails the step; the log ends with the `deploy.rb`
exit code (`2`: the rollout was rolled back to the previous AMIs, `3`: someone must check the environment). When the
build is still running after `monitor-timeout-minutes`, the step fails and the build keeps running in CodeBuild.

`flags` accepts only the flags `deploy-runner` allows; `--skip-rollback`, `--skip-lock`, `--reset-instances`,
`--resize` and anything else stop the step before AWS is called.

## Authentication

Supply one of:

- **GitHub OIDC (recommended):** set `aws-role-to-assume` to an IAM role whose trust policy allows this repository,
  and grant the job `id-token: write`. The role needs `codebuild:StartBuild` and `codebuild:BatchGetBuilds` on the
  project and `logs:GetLogEvents` on its log group, which the `github-actions` role of the codedeploy stack has.
  Keep `aws-role-duration-seconds` longer than the rollout.
- **Access keys:** set `aws-access-key-id` and `aws-secret-access-key`.

```yml
  beta_rollout:
    runs-on: ubuntu-latest
    needs: beta_deploy
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Beta ASG rollout
        uses: cloud-officer/ci-actions/codedeploy/asg-rollout@v3
        with:
          aws-role-to-assume: "arn:aws:iam::123456789012:role/github-actions"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
          environment: beta1
          instances: api,worker
```
