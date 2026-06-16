# Innovation Sandbox on AWS — EKS Example Blueprint

An example [Innovation Sandbox on AWS](https://aws.amazon.com/solutions/implementations/innovation-sandbox-on-aws/) Blueprint that provisions an EKS Auto Mode cluster into a sandbox account using Terraform, orchestrated by Step Functions. It's a **reference implementation**, adapt the Terraform to your own cluster configuration.

## How it works

When a learner is granted a lease, Innovation Sandbox on AWS deploys this Blueprint into a sandbox account. The stack's custom resource starts a Step Functions execution that runs CodeBuild, which applies the Terraform and leaves the learner with a ready-to-use EKS cluster.

## Components

CloudFormation only deploys CloudFormation, but the cluster is defined in Terraform, so this template is a thin shim that hands provisioning to CodeBuild:

- **CodeBuild** runs your Terraform. `buildspec-create.yml` (`terraform apply`) runs when the lease is granted; `buildspec-destroy.yml` (`terraform destroy`) ships for manual teardown and create-failure rollback only — Innovation Sandbox on AWS never invokes it on lease end (see [Teardown and idempotency](#teardown-and-idempotency)).
- **Step Functions** orchestrates CodeBuild rather than a bare Lambda, because a cluster build can run longer than Lambda's 15-minute limit. The state machine starts the build, polls it to completion, and reports SUCCESS or FAILED back to CloudFormation.
- **`LabProvisioner`** (custom resource) is the CloudFormation-facing trigger: on create and delete it starts the state machine via a thin trigger Lambda, with a small response Lambda sending the callback on the state machine's behalf.
- **`WorkspaceBucket`** (custom resource) creates an in-account S3 bucket for Terraform state on create. On a manual stack delete it empties and removes the bucket; on lease end `aws-nuke` deletes it with everything else. Either way state lives and dies with the lease, with no central tooling account to maintain.

### Teardown and idempotency

Innovation Sandbox on AWS owns recycle. On lease end it removes the blueprint's stack-instance metadata — a `DeleteStackInstances` call with `RetainStacks=true`, so the StackSet record goes but the account is left intact — then its Account Cleaner runs [`aws-nuke`](https://github.com/ekristen/aws-nuke) (multi-pass) to wipe the account. CloudFormation never deletes the stack, so the `LabProvisioner` Delete handler and `buildspec-destroy.yml` are **never invoked on recycle**; `aws-nuke` owns teardown.

`buildspec-destroy.yml` is kept for developing the blueprint as a standalone stack — `delete-stack` then runs an ordered `terraform destroy` to tear your test cluster down, and the same handler backs CloudFormation's create-failure rollback. Because every lease provisions into a freshly recycled account, the Terraform must also be idempotent: fixed account-scoped names (a stray `alias/eks/<cluster>` KMS alias, the cluster name) that survive an imperfect `aws-nuke` pass collide on the next deploy and fail it, so this example derives a per-deployment suffix (`deploy_id`) to keep names unique across leases.

## Using it

**1. Publish the Terraform source to a bucket in your hub account.** Innovation Sandbox on AWS runs in the hub account; keep the artifact there and grant the sandbox account-pool OU cross-account read so leased accounts can pull it. CodeBuild fetches it at deploy time via the template's `SourceBucket`/`SourceKey` parameters — separate from how the Blueprint is registered.

```bash
zip -r source.zip buildspec-create.yml buildspec-destroy.yml terraform/
aws s3 cp source.zip s3://YOUR-BUCKET/blueprint/source.zip
```

**2. Create a self-managed StackSet from `template.yaml` in the hub account.** Innovation Sandbox on AWS registers Blueprints as self-managed CloudFormation StackSets, using the IAM roles the solution provisions. Give it no deployment targets — Innovation Sandbox on AWS creates the per-account stack instance itself when a lease is granted.

```bash
aws cloudformation create-stack-set \
  --stack-set-name eks-lab-blueprint \
  --template-body file://template.yaml \
  --administration-role-arn arn:aws:iam::HUB_ACCOUNT_ID:role/InnovationSandbox-NAMESPACE-IntermediateRole \
  --execution-role-name InnovationSandbox-NAMESPACE-SandboxAccountRole \
  --managed-execution Active=true \
  --capabilities CAPABILITY_IAM \
  --parameters \
      ParameterKey=SourceBucket,ParameterValue=YOUR-BUCKET \
      ParameterKey=SourceKey,ParameterValue=blueprint/source.zip
```

Replace `HUB_ACCOUNT_ID` with your hub account ID and `NAMESPACE` with your solution namespace.

**3. Register the StackSet as a Blueprint** in the Innovation Sandbox on AWS web console (**Administration → Blueprints → Register blueprint**), then have a manager attach it to a lease template. The wizard sets the **deployment timeout** (30 minutes by default) — raise it for EKS, since a full build runs ~15–20 minutes and Innovation Sandbox on AWS treats an overrun as a failed deployment and recycles the account. Bump the template's `BuildTimeout` parameter to match. See the [administrator guide](https://docs.aws.amazon.com/solutions/latest/innovation-sandbox-on-aws/administrator-guide.html) (registering blueprints) and [manager guide](https://docs.aws.amazon.com/solutions/latest/innovation-sandbox-on-aws/manager-guide.html) (lease templates).

> [!WARNING]
> The example `CodeBuildRole` ships with **`AdministratorAccess`** to stay lab- and tool-agnostic. **Scope it down to exactly what your Terraform provisions before using this for anything real.**

## Customization

This example builds an EKS Auto Mode cluster; adapt the Terraform to your needs — swap the VPC module for your networking standard, add add-ons, IRSA roles, or sample workloads, pin a Kubernetes version, or replace EKS entirely. The CodeBuild + Step Functions shim works with any Terraform configuration, or any tool with a create and destroy path.

## Related

- [Blog post: Self-service Kubernetes training labs with Innovation Sandbox on AWS](https://andskli.github.io/posts/self-service-k8s-training-labs/) *(coming soon)*
- [Innovation Sandbox on AWS](https://aws.amazon.com/solutions/implementations/innovation-sandbox-on-aws/)
- [`ekristen/aws-nuke`](https://github.com/ekristen/aws-nuke)
