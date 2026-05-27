# 고객 onboarding — 권한 요청 + 5단계 배포

## 1. 클라우드 팀에 IAM Policy 신청

배포 담당자 IAM user/role 에 다음 policy attach 요청.

**요청 메일 템플릿**:

```
제목: DBAOps-Agent 배포용 IAM Policy 생성 요청

DBAOps-Agent 배포를 위해 다음 IAM Policy 생성 + 배포 담당자에게 attach 요청드립니다.

[1] Policy 생성
- 이름: DBAOpsAgentDeployerPolicy
- 첨부: dbaops-deployer-policy.json (아래)

[2] Attach 대상
- IAM user 또는 IAM role: <배포 담당자>

[3] 사용 기간
- 배포·운영 기간 (예: 2026-01-01 ~ 2026-12-31)

[4] 추가 요청 (IAM 외)
- Bedrock 모델 access 활성: Anthropic Claude Opus 4.7 (Bedrock 콘솔 → Model access)
- 서비스 쿼터: Fargate Spot vCPU 8개, Lambda 동시 실행 100, ECS service 1
- 리전: ap-northeast-2
```

### IAM Policy JSON

다음을 `dbaops-deployer-policy.json` 으로 첨부.

<details>
<summary>전체 JSON (열기)</summary>

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VPCNetwork",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:DescribeVpcs",
        "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute", "ec2:DescribeSubnets",
        "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DescribeInternetGateways",
        "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:DescribeRouteTables",
        "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
        "ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:ModifyNetworkInterfaceAttribute", "ec2:AttachNetworkInterface", "ec2:DetachNetworkInterface",
        "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint", "ec2:DescribeVpcEndpoints",
        "ec2:DescribeAvailabilityZones", "ec2:DescribePrefixLists", "ec2:DescribeManagedPrefixLists", "ec2:GetManagedPrefixListEntries",
        "ec2:DescribeAccountAttributes"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Instance",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances", "ec2:TerminateInstances", "ec2:StopInstances", "ec2:StartInstances",
        "ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:DescribeInstanceTypes", "ec2:DescribeImages",
        "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
        "ec2:DescribeVolumes", "ec2:CreateVolume", "ec2:DeleteVolume", "ec2:AttachVolume", "ec2:DetachVolume",
        "ec2:DescribeKeyPairs"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecurityGroup",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
        "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
        "ec2:ModifySecurityGroupRules"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ELB",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes", "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags", "elasticloadbalancing:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudFront",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateDistribution", "cloudfront:DeleteDistribution", "cloudfront:UpdateDistribution",
        "cloudfront:GetDistribution", "cloudfront:GetDistributionConfig", "cloudfront:ListDistributions",
        "cloudfront:TagResource", "cloudfront:UntagResource", "cloudfront:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3Bucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket", "s3:GetBucketLocation",
        "s3:PutBucketPolicy", "s3:GetBucketPolicy", "s3:DeleteBucketPolicy",
        "s3:PutBucketVersioning", "s3:GetBucketVersioning",
        "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
        "s3:PutEncryptionConfiguration", "s3:GetEncryptionConfiguration",
        "s3:PutLifecycleConfiguration", "s3:GetLifecycleConfiguration",
        "s3:PutBucketTagging", "s3:GetBucketTagging",
        "s3:PutObject", "s3:GetObject", "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::dbaops-*",
        "arn:aws:s3:::dbaops-*/*"
      ]
    },
    {
      "Sid": "Lambda",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:ListFunctions",
        "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
        "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags",
        "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency"
      ],
      "Resource": "arn:aws:lambda:*:*:function:dbaops-*"
    },
    {
      "Sid": "ECS",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters", "ecs:UpdateCluster",
        "ecs:PutClusterCapacityProviders",
        "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions",
        "ecs:CreateService", "ecs:DeleteService", "ecs:UpdateService", "ecs:DescribeServices", "ecs:ListServices",
        "ecs:RunTask", "ecs:StopTask", "ecs:DescribeTasks", "ecs:ListTasks",
        "ecs:TagResource", "ecs:UntagResource", "ecs:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECR",
      "Effect": "Allow",
      "Action": [
        "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
        "ecr:SetRepositoryPolicy", "ecr:GetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
        "ecr:TagResource", "ecr:UntagResource", "ecr:ListTagsForResource",
        "ecr:PutImageScanningConfiguration"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMForServiceRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
        "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::*:role/dbaops-*",
        "arn:aws:iam::*:instance-profile/dbaops-*"
      ]
    },
    {
      "Sid": "Cognito",
      "Effect": "Allow",
      "Action": [
        "cognito-idp:CreateUserPool", "cognito-idp:DeleteUserPool", "cognito-idp:UpdateUserPool", "cognito-idp:DescribeUserPool",
        "cognito-idp:CreateUserPoolDomain", "cognito-idp:DeleteUserPoolDomain", "cognito-idp:DescribeUserPoolDomain",
        "cognito-idp:CreateUserPoolClient", "cognito-idp:DeleteUserPoolClient", "cognito-idp:UpdateUserPoolClient", "cognito-idp:DescribeUserPoolClient",
        "cognito-idp:CreateResourceServer", "cognito-idp:DeleteResourceServer", "cognito-idp:UpdateResourceServer", "cognito-idp:DescribeResourceServer", "cognito-idp:ListResourceServers"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Secrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets",
        "secretsmanager:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Logs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
        "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
        "logs:PutResourcePolicy", "logs:DescribeResourcePolicies"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BedrockAgentCore",
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:*",
        "bedrock-agentcore-control:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BedrockModelInvoke",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:GetFoundationModel",
        "bedrock:ListFoundationModels",
        "bedrock:GetInferenceProfile",
        "bedrock:ListInferenceProfiles"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Identity",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

</details>

### CLI 로 적용 (참고)

```bash
aws iam create-policy \
  --policy-name DBAOpsAgentDeployerPolicy \
  --policy-document file://dbaops-deployer-policy.json

aws iam attach-user-policy \
  --user-name <user> \
  --policy-arn arn:aws:iam::<account>:policy/DBAOpsAgentDeployerPolicy
```

---

## 2. 배포 담당자 PC 사전 준비

```bash
aws --version           # >= 2
terraform --version     # >= 1.7
docker buildx ls        # linux/arm64 지원 확인
python3 --version       # >= 3.12
```

`aws configure` 또는 `aws sso login` 으로 인증.

---

## 3. State backend 준비 (한 번만)

고객 계정에 terraform state 용 S3 + DynamoDB:

```bash
aws s3api create-bucket \
  --bucket dbaops-tfstate-<account_id>-<region> \
  --create-bucket-configuration LocationConstraint=ap-northeast-2 \
  --region ap-northeast-2

aws s3api put-bucket-versioning \
  --bucket dbaops-tfstate-<account_id>-<region> \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name dbaops-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-2
```

---

## 4. 외부 자원 매핑

[EXTERNAL_RESOURCES.md](EXTERNAL_RESOURCES.md) 참조.

---

## 5. 5단계 배포 — README 의 "5단계 배포" 그대로

상세는 [../README.md](../README.md) 의 "5단계 배포" 섹션.

요약:
1. `terraform.tfvars` 채우기 (외부 자원 + identifiers)
2. 1차 `terraform apply -var=mcp_images_pushed=false -var=streamlit_image_pushed=false`
3. `bash scripts/build_*.sh` 3종
4. 2차 apply + `ENV=customer python scripts/register_gateway_targets.py`
5. 3차 apply 후 `terraform output streamlit_url`

---

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| 첫 apply 가 `AccessDenied` | 위 IAM policy 누락 액션. 에러 메시지의 액션 추가 요청 |
| Lambda 가 RDS 에 도달 못 함 (timeout) | 고객 RDS SG 가 Lambda SG 의 인바운드 미허용. `lambda_community_postgres` 의 SG ID 를 RDS SG 에 추가 |
| Streamlit 이 502 | ECS task 가 떠있는지 (`aws ecs describe-services ... --cluster dbaops-customer`) 확인. ALB target health 도 |
| `register_gateway_targets.py` 가 ENV mismatch | `ENV=customer` 명시했는지. default 는 `customer` 지만 옛 PoC 와 혼동 시 명시 |
| Bedrock 호출에 `AccessDenied` | 콘솔 → Bedrock → Model access 에서 Claude Opus 4.7 활성 |
