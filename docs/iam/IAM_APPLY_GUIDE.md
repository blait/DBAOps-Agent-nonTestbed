# IAM Policy 적용 가이드 (클라우드 팀용)

DBAOps-Agent 배포 담당자에게 권한을 부여하는 절차. 4 가지 방법 중 하나 선택.

---

## 무엇을 적용하는가

같은 디렉토리 안 JSON 파일:

| 파일 | 용도 | 크기 |
|---|---|---|
| `dbaops-deployer-policy.json` | 통합본 (1개) | 7,455 자 — managed 한계 6,144 자 초과. **inline policy 또는 customer managed policy 로만 사용 가능** |
| `dbaops-deployer-policy-1-compute.json` | compute (VPC/ELB/CloudFront/Lambda/ECS/ECR) | 4,570 자 — managed OK |
| `dbaops-deployer-policy-2-data.json` | data + auth + observability (S3/IAM/Cognito/Secrets/Logs/Bedrock/STS) | 2,791 자 — managed OK |

→ **권장: 분할본 2개를 customer managed policy 로 만들고 사용자에게 둘 다 attach**.

---

## 방법 1 — IAM 콘솔 (GUI, 가장 쉬움)

### 1-A. Policy 생성

1. AWS Console → **IAM** → 왼쪽 **Policies** → 우상단 **Create policy**
2. 상단 탭 **JSON** 클릭
3. 첨부 받은 `dbaops-deployer-policy-1-compute.json` 내용 그대로 붙여넣기
4. **Next: Tags** → 태그 (옵션) → **Next: Review**
5. **Name**: `DBAOpsAgentDeployerCompute`
6. **Description**: "DBAOps-Agent 배포용 — VPC/ELB/Lambda/ECS/ECR"
7. **Create policy**

같은 절차로 `dbaops-deployer-policy-2-data.json` → **Name**: `DBAOpsAgentDeployerData`.

### 1-B. 사용자에게 attach

1. IAM → **Users** → 배포 담당자 user 선택
2. **Permissions** 탭 → **Add permissions** → **Attach policies directly**
3. 검색창에 `DBAOpsAgentDeployer` → 위 두 정책 모두 체크
4. **Next** → **Add permissions**

IAM Role 에 attach 하는 경우도 동일 (Roles 메뉴에서 같은 절차).

---

## 방법 2 — AWS CLI

```bash
# Policy 2개 생성
aws iam create-policy \
  --policy-name DBAOpsAgentDeployerCompute \
  --policy-document file://dbaops-deployer-policy-1-compute.json \
  --description "DBAOps-Agent deploy — VPC/ELB/Lambda/ECS/ECR"

aws iam create-policy \
  --policy-name DBAOpsAgentDeployerData \
  --policy-document file://dbaops-deployer-policy-2-data.json \
  --description "DBAOps-Agent deploy — S3/IAM/Cognito/Secrets/Logs/Bedrock"

# Account ID 캡처
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 배포 담당자 user 에 attach (USER_NAME 치환)
USER_NAME=<배포담당자_user>
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/DBAOpsAgentDeployerCompute
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/DBAOpsAgentDeployerData
```

IAM role 에 attach 시 `attach-user-policy` 대신 `attach-role-policy`.

---

## 방법 3 — CloudFormation

다음을 `dbaops-deployer-stack.yaml` 로 저장:

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: DBAOps-Agent deployer policies (2 managed policies)

Parameters:
  AttachToUserName:
    Type: String
    Default: ""
    Description: "배포 담당자 IAM user 이름. 비우면 attach 안 함."

Resources:
  ComputePolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: DBAOpsAgentDeployerCompute
      Description: "DBAOps-Agent deploy — VPC/ELB/Lambda/ECS/ECR"
      PolicyDocument: !Include dbaops-deployer-policy-1-compute.json

  DataPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: DBAOpsAgentDeployerData
      Description: "DBAOps-Agent deploy — S3/IAM/Cognito/Secrets/Logs/Bedrock"
      PolicyDocument: !Include dbaops-deployer-policy-2-data.json

  Attach:
    Type: AWS::IAM::UserPolicyAttachment
    Condition: HasUser
    Properties:
      UserName: !Ref AttachToUserName
      PolicyArn: !Ref ComputePolicy

Conditions:
  HasUser: !Not [!Equals [!Ref AttachToUserName, ""]]
```

> ⚠️ CloudFormation 의 `!Include` 는 native 가 아니라 사전 처리 필요. 보통 `aws cloudformation package` 또는 직접 JSON 을 yaml 안에 inline 으로 박아 넣음. 가장 편한 건 방법 1·2.

---

## 방법 4 — Terraform

```hcl
resource "aws_iam_policy" "compute" {
  name        = "DBAOpsAgentDeployerCompute"
  description = "DBAOps-Agent deploy - VPC/ELB/Lambda/ECS/ECR"
  policy      = file("${path.module}/dbaops-deployer-policy-1-compute.json")
}

resource "aws_iam_policy" "data" {
  name        = "DBAOpsAgentDeployerData"
  description = "DBAOps-Agent deploy - S3/IAM/Cognito/Secrets/Logs/Bedrock"
  policy      = file("${path.module}/dbaops-deployer-policy-2-data.json")
}

resource "aws_iam_user_policy_attachment" "compute" {
  user       = var.deployer_user_name
  policy_arn = aws_iam_policy.compute.arn
}

resource "aws_iam_user_policy_attachment" "data" {
  user       = var.deployer_user_name
  policy_arn = aws_iam_policy.data.arn
}
```

---

## 방법 5 — 단일 inline policy (분할 싫을 때)

`dbaops-deployer-policy.json` 통합본을 사용자/role 에 inline 으로:

```bash
USER_NAME=<배포담당자_user>
aws iam put-user-policy \
  --user-name "$USER_NAME" \
  --policy-name DBAOpsAgentDeployer \
  --policy-document file://dbaops-deployer-policy.json
```

inline 한계 10,240 자 — 통합본 7,455 자 OK. 다만 inline 은 audit / 재사용에 불편.

---

## 적용 후 검증

배포 담당자 측에서:

```bash
# 권한 정상 부여 확인
aws sts get-caller-identity
aws iam list-attached-user-policies --user-name $(aws sts get-caller-identity --query 'Arn' --output text | awk -F/ '{print $NF}')

# DBAOps 자원 prefix 권한 검증
aws ec2 describe-vpcs --max-items 1 --no-cli-pager
aws bedrock list-foundation-models --region ap-northeast-2 --no-cli-pager --query 'modelSummaries[?contains(modelId,`opus-4`)].modelId'
aws bedrock-agentcore-control list-agent-runtimes --region ap-northeast-2 --no-cli-pager
```

세 명령 모두 성공해야 함. `AccessDenied` 가 떨어지면 해당 service 의 액션이 누락된 것.

---

## 추가로 클라우드 팀이 해줘야 하는 것 — IAM 외

| 항목 | 요청 |
|---|---|
| 서비스 쿼터 | Fargate Spot vCPU 8개, Lambda 동시 실행 100, RDS Aurora cluster 1, MSK Serverless cluster 1 |
| 리전 | ap-northeast-2 (서울) — 다른 리전 지원 안 함 |

---

## 회수 절차 (배포 종료 시)

```bash
USER_NAME=<배포담당자_user>
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam detach-user-policy --user-name "$USER_NAME" \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/DBAOpsAgentDeployerCompute
aws iam detach-user-policy --user-name "$USER_NAME" \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/DBAOpsAgentDeployerData

aws iam delete-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/DBAOpsAgentDeployerCompute
aws iam delete-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/DBAOpsAgentDeployerData
```

또는 콘솔 → IAM → Policies → 정책 선택 → Delete.

---

## 권한 범위 자세히

| 액션 | Resource 좁힘 | 비고 |
|---|---|---|
| Lambda | `arn:aws:lambda:*:*:function:dbaops-*` | 다른 Lambda 건드리지 않음 |
| S3 | `arn:aws:s3:::dbaops-*` | dbaops 로 시작하는 bucket 만 |
| IAM Role | `arn:aws:iam::*:role/dbaops-*` | dbaops-* role 만 생성/수정 |
| 그 외 | `Resource: "*"` | preview 서비스 (AgentCore) 또는 글로벌 lookup 필요 |

`bedrock-agentcore:*` 와 `bedrock-agentcore-control:*` 는 wildcard. AWS Bedrock AgentCore 가 preview 라 IAM action reference 가 미정. GA 후 좁힐 수 있음.

---

## 문의

- 액션 누락이 의심되는 `AccessDenied` 발생 시 → 에러 메시지의 `Action` 키 회신 (예: `User: ... is not authorized to perform: ec2:CreateXyz`)
- AgentCore preview 활성 region 확인 필요 시 → AWS support
