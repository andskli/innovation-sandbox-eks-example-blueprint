# Innovation Sandbox — EKS Example Blueprint

An example [AWS Innovation Sandbox](https://aws.amazon.com/solutions/implementations/innovation-sandbox-on-aws/) Blueprint that provisions an EKS cluster into a sandbox account using a CodeBuild + Step Functions pattern.

This is a **reference implementation** — adapt it to your own infrastructure tooling and cluster configuration.

## How it works

```
Learner requests lease
  → Innovation Sandbox assigns account from pool
  → Blueprint StackSet deploys this template
  → Custom resource triggers Step Functions (CREATE)
  → Step Functions starts CodeBuild, polls until complete
  → CodeBuild runs eksctl create cluster
  → Step Functions sends SUCCESS to CloudFormation
  → Learner gets a ready-to-use EKS environment

Lease expires
  → StackSet deletion triggers custom resource (DELETE)
  → Step Functions starts CodeBuild for teardown
  → CodeBuild runs eksctl delete cluster (ordered teardown)
  → aws-nuke sweeps anything left over
  → Account returns to pool
```

## Repository structure

```
template.yaml              # CloudFormation Blueprint template (all logic inline)
buildspec-create.yml       # CodeBuild spec — cluster provisioning
buildspec-destroy.yml      # CodeBuild spec — ordered teardown
example/cluster.yaml       # eksctl cluster configuration
```

## The pattern

The Blueprint deploys these resources into the sandbox account:

1. **CodeBuild project** — source from S3, runs your provisioning code
2. **Step Functions state machine** — orchestrates CodeBuild with polling and timeout
3. **Trigger Lambda** — thin function that starts the state machine from the CFN event
4. **Response Lambda** — sends the CFN callback (SUCCESS/FAILED) on behalf of Step Functions
5. **Custom resource** — wires it all together

### Why Step Functions?

EKS cluster creation takes 15–20 minutes. Lambda has a hard 15-minute timeout. Rather than fire-and-forget (which can't report failures), the state machine polls CodeBuild every 30 seconds and handles three outcomes:

- **Build succeeds** → sends SUCCESS to CloudFormation
- **Build fails** → sends FAILED to CloudFormation (triggers rollback on Create, leaves DELETE_FAILED for operator visibility on Delete)
- **Build times out** → CodeBuild's own timeout fires, status becomes TIMED_OUT, reported as FAILED

On **Delete** failures, the stack enters `DELETE_FAILED` state — giving operators visibility that cleanup didn't complete cleanly. The Innovation Sandbox's scheduled aws-nuke sweep handles any residual resources regardless.

### Why not just aws-nuke?

aws-nuke *will* eventually delete everything, but EKS creates implicit dependencies (load balancer ENIs, security group cross-references, PVC finalizers) that make brute-force deletion slow — often 40+ minutes of retry cycles. Running an ordered teardown first lets aws-nuke finish quickly on the stragglers.

## Packaging the source

CodeBuild pulls source from S3. Package and upload before deploying the Blueprint:

```bash
zip -r source.zip buildspec-create.yml buildspec-destroy.yml example/
aws s3 cp source.zip s3://YOUR-BUCKET/blueprint/source.zip
```

## Deploying as a Blueprint

Register this template as an Innovation Sandbox Blueprint. Set the `SourceBucket` and `SourceKey` parameters to point at your packaged artifact.

See the [Blueprints documentation](https://docs.aws.amazon.com/solutions/latest/innovation-sandbox-on-aws/blueprints.html) for registration steps.

## Customization

This example uses eksctl for simplicity. The pattern works with any tool that has a create and destroy path:

- **Terraform** — `terraform apply` / `terraform destroy` (store state in the in-account S3 bucket)
- **CDK** — `cdk deploy` / `cdk destroy`
- **Pulumi** — `pulumi up` / `pulumi destroy`
- **Shell scripts** — any arbitrary provisioning code

Replace the contents of `buildspec-create.yml`, `buildspec-destroy.yml`, and `example/` with your own tooling.

## Related

- [Blog post: Self-service Kubernetes training labs with AWS Innovation Sandbox](https://andskli.dev/posts/self-service-k8s-training-labs/) *(coming soon)*
- [AWS Innovation Sandbox on AWS](https://aws.amazon.com/solutions/implementations/innovation-sandbox-on-aws/)
- [ekristen/aws-nuke](https://github.com/ekristen/aws-nuke)

## License

MIT
