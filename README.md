# Innovation Sandbox — EKS Example Blueprint

An example [AWS Innovation Sandbox](https://aws.amazon.com/solutions/implementations/innovation-sandbox-on-aws/) Blueprint that provisions an EKS Auto Mode cluster into a sandbox account using Terraform, orchestrated by Step Functions.

This is a **reference implementation** — adapt the Terraform modules to your own cluster configuration.

## How it works

```
Learner requests lease
  → Innovation Sandbox assigns account from pool
  → Blueprint StackSet deploys this template
  → Custom resource triggers Step Functions (CREATE)
  → Step Functions starts CodeBuild, polls until complete
  → CodeBuild runs terraform apply (VPC + EKS Auto Mode)
  → Step Functions sends SUCCESS to CloudFormation
  → Learner gets a ready-to-use EKS environment

Lease expires
  → StackSet deletion triggers custom resource (DELETE)
  → Step Functions starts CodeBuild for teardown
  → CodeBuild runs terraform destroy
  → aws-nuke sweeps anything left over
  → Account returns to pool
```

## Repository structure

```
template.yaml              # CloudFormation Blueprint template (all orchestration inline)
buildspec-create.yml       # CodeBuild spec — terraform apply
buildspec-destroy.yml      # CodeBuild spec — terraform destroy
terraform/
  main.tf                  # VPC + EKS Auto Mode cluster
  variables.tf             # Cluster name, region, version
  outputs.tf               # Cluster endpoint and name
```

## The pattern

The Blueprint deploys these resources into the sandbox account:

1. **S3 bucket** — Terraform state, stored in-account (disposable — cleaned up when the account is recycled)
2. **CodeBuild project** — runs Terraform with state bucket passed as env var
3. **Step Functions state machine** — orchestrates CodeBuild with polling and timeout
4. **Trigger Lambda** — starts the state machine from the CFN event
5. **Response Lambda** — sends the CFN callback (SUCCESS/FAILED) on behalf of Step Functions
6. **Custom resource** — wires it all together

### Why Step Functions?

Infrastructure provisioning can take longer than Lambda's 15-minute maximum execution time. Rather than fire-and-forget (which can't report failures), the state machine polls CodeBuild every 30 seconds and handles three outcomes:

- **Build succeeds** → sends SUCCESS to CloudFormation
- **Build fails** → sends FAILED to CloudFormation (triggers rollback on Create, leaves DELETE_FAILED for operator visibility on Delete)
- **Build times out** → CodeBuild's own timeout fires, status becomes TIMED_OUT, reported as FAILED

On **Delete** failures, the stack enters `DELETE_FAILED` state — giving operators visibility that cleanup didn't complete cleanly. The Innovation Sandbox's scheduled aws-nuke sweep handles any residual resources regardless.

### Why not just aws-nuke?

aws-nuke *will* eventually delete everything, but EKS creates implicit dependencies (load balancer ENIs, security group cross-references, PVC finalizers) that make brute-force deletion slow — often 40+ minutes of retry cycles. Running `terraform destroy` first lets aws-nuke finish quickly on the stragglers.

## Packaging the source

CodeBuild pulls source from S3. Package and upload before deploying the Blueprint:

```bash
zip -r source.zip buildspec-create.yml buildspec-destroy.yml terraform/
aws s3 cp source.zip s3://YOUR-BUCKET/blueprint/source.zip
```

## Deploying as a Blueprint

Register this template as an Innovation Sandbox Blueprint. Set the `SourceBucket` and `SourceKey` parameters to point at your packaged artifact.

See the [Blueprints documentation](https://docs.aws.amazon.com/solutions/latest/innovation-sandbox-on-aws/blueprints.html) for registration steps.

## Customization

This example creates an EKS Auto Mode cluster. Adapt the Terraform to your needs:

- Add add-ons, IAM roles for service accounts, or sample workloads
- Swap the VPC module for your organization's networking standard
- Pin a specific Kubernetes version via the `cluster_version` variable
- Replace EKS entirely — the CodeBuild + Step Functions pattern works with any Terraform configuration

## Related

- [Blog post: Self-service Kubernetes training labs with AWS Innovation Sandbox](https://andskli.dev/posts/self-service-k8s-training-labs/) *(coming soon)*
- [AWS Innovation Sandbox on AWS](https://aws.amazon.com/solutions/implementations/innovation-sandbox-on-aws/)
- [ekristen/aws-nuke](https://github.com/ekristen/aws-nuke)

## License

MIT
