# Quickstart — 샌드박스 계정에 처음부터 배포하기

DBAOps-Agent 를 자기 AWS 샌드박스 계정에 띄우는 step-by-step 가이드. **이 문서대로 따라가면 ~30~60분 후 CloudFront URL 로 UI 접속 가능**.

문서 안 명령은 모두 그대로 복사해서 실행할 수 있게 적었다. `<...>` 자리만 자기 값으로 치환.

---

## 0. 들어가기 전에 — 5분 체크

다음이 준비됐는지 확인:

- [ ] AWS 샌드박스 계정 (관리자 권한)
- [ ] 본인 PC: AWS CLI v2, Terraform 1.7+, Docker (buildx 포함), Python 3.12+, git
- [ ] **`boto3` Python 패키지** 설치 (`pip install boto3` — register 스크립트가 import)
- [ ] 분석할 대상이 있는 리소스 (최소 1개):
  - RDS PostgreSQL **또는** RDS MySQL endpoint + Secrets Manager secret
  - 또는 EC2 위의 Prometheus URL
  - 또는 MSK cluster
  - 또는 S3 log bucket
- [ ] 위 리소스에 도달 가능한 VPC (subnet + SG)
- [ ] **VPC private subnet 에 NAT** (Lambda 가 docs.aws.amazon.com / Bedrock / Cognito / Secrets Manager 외부 호출). 없으면 `awslabs-aws-doc` 도구가 동작 안 함, 일부 다른 도구도 timeout. customer VPC 에 NAT 가 없다면 **`create_vpc=true`** 로 신규 VPC 만들어 사용 권장.
- [ ] **분석 대상 리소스의 secret 이 `{"username": "...", "password": "..."}` JSON 형식**. RDS 의 `master_user_secret` 자동 발급은 이 형식 ✅. 직접 만든 secret 이라면 키 이름 확인.

위 중 하나도 없으면 PoC 시연 자체가 안 됨. 데모만 보고 싶다면 RDS PG 1대 정도만이라도 미리 띄워둘 것.

---

## 1. AWS 자격증명 + 샌드박스 계정 ID 확인

```bash
# 본인 PC 에서
aws configure
# Access Key ID, Secret Access Key, Default region (ap-northeast-2), output (json) 입력

# 또는 SSO 사용자라면:
aws sso login --profile <profile>
export AWS_PROFILE=<profile>

# 확인
aws sts get-caller-identity
```

출력의 `Account` 값을 메모. 아래에서 `<ACCOUNT_ID>` 자리에 사용.

---

## 2. IAM 권한 받기 (이미 admin 이면 skip)

샌드박스라 보통 admin 일 것. 아니면 `docs/CUSTOMER_ONBOARDING.md` 의 IAM JSON 을 클라우드 팀에 요청.

**확인 명령**:
```bash
aws ec2 describe-vpcs --max-items 1 --region ap-northeast-2 --no-cli-pager
aws bedrock list-foundation-models --region ap-northeast-2 --no-cli-pager --query 'modelSummaries[?contains(modelId,`opus-4`)].modelId'
```

둘 다 정상 응답이 와야 함.

---

## 3. Bedrock 모델 호출 가능 여부 확인

```bash
aws bedrock-runtime invoke-model \
  --model-id global.anthropic.claude-opus-4-7 \
  --region ap-northeast-2 \
  --body '{"messages":[{"role":"user","content":"hi"}],"anthropic_version":"bedrock-2023-05-31","max_tokens":10}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/bedrock_test.json
cat /tmp/bedrock_test.json
```

`{"id":"msg_...","type":"message","role":"assistant",...}` 응답 오면 OK. `AccessDeniedException` 떨어지면 IAM policy 의 `bedrock:InvokeModel` 액션이 부여돼있는지 확인 (Step 2 의 IAM JSON).

---

## 4. State 저장소 만들기 (한 번만)

terraform state 를 저장할 S3 + DynamoDB lock 테이블:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
BUCKET="dbaops-tfstate-${ACCOUNT_ID}-${REGION}"

# S3 bucket
aws s3api create-bucket \
  --bucket "${BUCKET}" \
  --create-bucket-configuration LocationConstraint=${REGION} \
  --region ${REGION}

aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB lock
aws dynamodb create-table \
  --table-name dbaops-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ${REGION}

echo "state bucket: ${BUCKET}"
echo "lock table:   dbaops-tfstate-lock"
```

성공하면 두 줄 출력.

---

## 5. Repo clone

```bash
git clone https://github.com/blait/DBAOps-Agent-nonTestbed.git
cd DBAOps-Agent-nonTestbed
```

---

## 6. 외부 리소스 정보 수집

terraform.tfvars 에 채울 값을 미리 모아둔다.

### VPC / Subnet (분석 대상 RDS 와 같은 VPC 권장)

```bash
# 기본 VPC 보기
aws ec2 describe-vpcs --region ${REGION} --no-cli-pager \
  --query 'Vpcs[*].{id:VpcId,cidr:CidrBlock,tag:Tags[?Key==`Name`]|[0].Value}' --output table

# 그 VPC 의 subnet 들
VPC_ID=<위에서_고른_vpc_id>
aws ec2 describe-subnets --region ${REGION} --no-cli-pager \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[*].{id:SubnetId,cidr:CidrBlock,az:AvailabilityZone,public:MapPublicIpOnLaunch}' --output table
```

`MapPublicIpOnLaunch=true` → public, false → private. 양쪽에서 2개씩 필요.

### RDS PostgreSQL endpoint + secret

```bash
# 인스턴스 목록
aws rds describe-db-instances --region ${REGION} --no-cli-pager \
  --query 'DBInstances[*].{id:DBInstanceIdentifier,engine:Engine,endpoint:Endpoint.Address,status:DBInstanceStatus,secret:MasterUserSecret.SecretArn}' --output table

# 또는 cluster (Aurora) 목록
aws rds describe-db-clusters --region ${REGION} --no-cli-pager \
  --query 'DBClusters[*].{id:DBClusterIdentifier,engine:Engine,endpoint:Endpoint,secret:MasterUserSecret.SecretArn}' --output table
```

저장: `customer_pg_host`, `customer_pg_dbname`, `customer_pg_secret_arn`, `customer_aurora_cluster_id`, `customer_aurora_writer_id`.

### MySQL (있으면)

```bash
aws rds describe-db-instances --region ${REGION} --no-cli-pager \
  --query 'DBInstances[?Engine==`mysql`].{id:DBInstanceIdentifier,endpoint:Endpoint.Address,secret:MasterUserSecret.SecretArn}' --output table
```

### Prometheus URL

EC2 위에 self-hosted Prometheus 가 있으면 그 인스턴스의 private IP + port (`http://<ip>:9090`).

```bash
# Prometheus EC2 인스턴스 ID 확인
aws ec2 describe-instances --region ${REGION} --no-cli-pager \
  --filters "Name=tag:Name,Values=*prometheus*" \
  --query 'Reservations[].Instances[].{id:InstanceId,ip:PrivateIpAddress,az:Placement.AvailabilityZone}' --output table
```

저장: `customer_prometheus_url=http://<ip>:9090`, `customer_prom_instance_id=<i-xxxx>`.

### MSK cluster (있으면)

```bash
aws kafka list-clusters-v2 --region ${REGION} --no-cli-pager \
  --query 'ClusterInfoList[*].{name:ClusterName,arn:ClusterArn,type:ClusterType}' --output table
```

저장: `customer_msk_cluster_name`.

### S3 log bucket (있으면)

```bash
aws s3 ls --region ${REGION}
```

저장: `customer_log_bucket`, `customer_log_bucket_arn`.

### 보안 그룹 — 가장 중요한 사전 확인

**Lambda 가 RDS / Prometheus / MSK 에 도달**하려면 그쪽 SG 의 인바운드에 Lambda SG 허용이 필요해. 첫 apply 까지는 SG ID 를 모르므로:

**옵션 A — 사전에 wide-open**: 위 리소스들의 SG inbound 에 `<VPC CIDR>` 또는 0.0.0.0/0 으로 임시 허용. 데모 후 회수.

**옵션 B — 1차 apply 후 추가**: Lambda 가 만들어지면 그 SG ID 를 RDS/Prometheus/MSK SG inbound 에 추가. 자세히는 step 11.

샌드박스에서 Option A 가 가장 쉬움.

---

## 7. terraform.tfvars 작성

```bash
cd infra/envs/customer
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars     # vi/nano/code 등
```

수집한 값으로 채움. **PG 쪽만 필수**, 나머지는 빈값 OK:

```hcl
environment = "customer"
region      = "ap-northeast-2"

create_vpc                  = false
customer_vpc_id             = "vpc-xxxxxxxx"
customer_private_subnet_ids = ["subnet-aaaa", "subnet-bbbb"]
customer_public_subnet_ids  = ["subnet-cccc", "subnet-dddd"]

customer_pg_host       = "your-aurora-pg.xxx.ap-northeast-2.rds.amazonaws.com"
customer_pg_dbname     = "postgres"
customer_pg_secret_arn = "arn:aws:secretsmanager:..."

# 옵션 — 비워도 됨
customer_mysql_host       = ""
customer_mysql_secret_arn = ""
customer_prometheus_url   = ""
customer_msk_cluster_name = ""
customer_log_bucket       = ""

customer_aurora_cluster_id = "your-aurora-cluster"
customer_aurora_writer_id  = "your-aurora-writer"
customer_prom_instance_id  = ""
customer_mysql_db_id       = ""
```

---

## 8. backend.tf 작성

```bash
# 같은 디렉토리 (infra/envs/customer)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "dbaops-tfstate-${ACCOUNT_ID}-ap-northeast-2"
    key            = "envs/customer/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "dbaops-tfstate-lock"
    encrypt        = true
  }
}
EOF
```

---

## 9. 1차 apply — ECR repo / IAM / ALB / CloudFront 인프라

```bash
cd infra/envs/customer
terraform init
terraform apply -var=mcp_images_pushed=false -var=streamlit_image_pushed=false
```

`Plan: ~30 to add` 정도 나오면 yes 입력.

**완료까지 ~5분** (CloudFront 가 가장 느림). 끝나면 ECR repo 14 개, ALB, CloudFront distribution 이 만들어진 상태. 다만 Lambda 함수 / Streamlit task 는 아직 없음 (이미지 미push).

```bash
terraform output streamlit_url
# https://dXXXXXX.cloudfront.net  ← 아직 502 (origin 비어있음)
```

---

## 10. 컨테이너 이미지 빌드 + 푸시

```bash
cd ../../..    # repo root

bash scripts/build_mcp_images.sh        # 10 MCP Lambda 이미지
bash scripts/build_agent_image.sh       # AgentCore Runtime 이미지
bash scripts/build_streamlit_image.sh   # Streamlit UI 이미지
```

**전체 ~10분** (네트워크/도커 캐시에 따라 다름).

각 스크립트는 ARM64 멀티-아키 빌드를 하므로 본인 PC 가 다른 아키여도 buildx 가 자동 처리.

---

## 11. ⚠️ Lambda SG → 분석 대상 SG 인바운드 추가 (Option B 사용 시)

Step 6 에서 Option B 골랐으면 여기서 처리. (Option A — wide-open 이면 skip)

`lambda_mcp_image` module 이 Lambda 마다 자기 SG 를 만들 가능성이 있어 — 한 번에 모두 확인:

```bash
# 모든 MCP Lambda 의 SG ID 수집
for fn in $(aws lambda list-functions --region ap-northeast-2 --no-cli-pager \
              --query 'Functions[?starts_with(FunctionName,`dbaops-customer-`)].FunctionName' --output text); do
  sg=$(aws lambda get-function-configuration --function-name "$fn" --region ap-northeast-2 --no-cli-pager \
         --query 'VpcConfig.SecurityGroupIds[0]' --output text)
  echo "$fn  →  $sg"
done | sort -u
```

출력의 unique SG ID 리스트를 모음. 보통 1개 (모든 Lambda 가 default Lambda SG 공유) 지만 module 설정에 따라 다를 수 있음.

이제 분석 대상 SG inbound 에 위 SG 모두 허용:
- 분석 대상 RDS PG 의 SG → inbound 5432 from `<lambda-sg>` 추가
- 분석 대상 RDS MySQL → inbound 3306 from `<lambda-sg>`
- Prometheus EC2 → inbound 9090 from `<lambda-sg>`
- MSK cluster → inbound 9098 from `<lambda-sg>` (IAM SASL)

콘솔에서 "Edit inbound rules" 또는 CLI:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id <target-sg> \
  --protocol tcp --port 5432 --source-group <lambda-sg> \
  --region ap-northeast-2
```

---

## 12. 2차 apply — MCP Lambda 함수 생성

```bash
cd infra/envs/customer
terraform apply -var=mcp_images_pushed=true -var=streamlit_image_pushed=false
```

`Plan: 10 to add` 정도. 10개 Lambda 가 만들어지고 ECR 이미지를 pull 해 ready 상태가 됨 (~3분).

---

## 13. AgentCore Gateway / Runtime 등록

terraform 으로는 못 만드는 영역 (AWS Bedrock AgentCore preview API). Python 스크립트로.

**먼저 INFRA_* 환경변수를 export** — register 스크립트가 AgentCore Runtime 의 environmentVariables 로 set 하는 값. agent prompt 의 `<infra_identifiers>` 섹션을 채움. step 7 의 `customer_*_id` 와 같은 값:

```bash
cd ../../..    # repo root
pip install boto3   # 처음 1회만

export ENV=customer
export INFRA_PROM_INSTANCE_ID="i-xxxxxxxx"          # Prometheus EC2
export INFRA_AURORA_CLUSTER_ID="your-aurora-cluster"
export INFRA_AURORA_WRITER_ID="your-aurora-writer"
export INFRA_AURORA_READER_ID=""                     # 옵션
export INFRA_MYSQL_DB_ID=""                          # 옵션
export INFRA_MSK_CLUSTER_NAME="your-msk-cluster"     # 옵션
export INFRA_LOG_BUCKET="your-log-bucket"            # 옵션

python scripts/register_gateway_targets.py
```

빈값으로 둬도 동작 — agent 가 LLM 한테 "" 보여주고 사용자가 도구 결과로 발견하게 됨. UX 를 위해 채우는 게 좋음.

스크립트가 하는 일:
1. Cognito user pool domain 생성 (없으면)
2. Gateway 생성 (이미 있으면 update)
3. 10 Lambda 를 Gateway target 으로 등록 (각 tool_io.json 의 schema 그대로)
4. AgentCore Runtime 생성 (이미 있으면 update) — INFRA_* env 가 Runtime 환경변수로 들어감

**출력 끝부분의 `agentRuntimeArn` 값을 메모**. 다음 step 에서 사용.

확인:
```bash
aws bedrock-agentcore-control list-agent-runtimes --region ap-northeast-2 --no-cli-pager \
  --query 'agentRuntimes[?agentRuntimeName==`dbaops_customer`].{name:agentRuntimeName,arn:agentRuntimeArn,status:status}'
```

`status: READY` 떨어질 때까지 ~30초 대기.

---

## 14. 3차 apply — Streamlit ECS service 띄우기

```bash
cd infra/envs/customer

RUNTIME_ARN=$(aws bedrock-agentcore-control list-agent-runtimes \
  --region ap-northeast-2 --no-cli-pager --output json \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(next(r['agentRuntimeArn'] for r in d['agentRuntimes'] if r['agentRuntimeName']=='dbaops_customer'))")

terraform apply \
  -var=mcp_images_pushed=true \
  -var=streamlit_image_pushed=true \
  -var="agentcore_runtime_arn=${RUNTIME_ARN}"
```

ECS service 1개 + task 1개 가 뜸 (~2분).

```bash
# 상태 확인
aws ecs describe-services \
  --cluster dbaops-customer \
  --services dbaops-customer-streamlit \
  --region ap-northeast-2 --no-cli-pager \
  --query 'services[0].{desired:desiredCount,running:runningCount,events:events[0].message}'
```

`running: 1` 이고 events 가 `(service ...) has reached a steady state` 면 OK.

---

## 15. 접속 URL 확인 + 동작 검증

```bash
terraform output streamlit_url
# → https://dXXXXX.cloudfront.net
```

브라우저로 접속. **첫 로딩 ~30초** (CloudFront 가 origin 첫 cache miss 처리).

확인:
- [ ] 4개 탭 (`🖥️ OS·인프라` `🗄️ DB 성능` `📜 로그` `🧠 단일 에이전트`) 보임
- [ ] `🗄️ DB 성능` 탭 → "PG 활성 세션 보여줘" 같은 질문 입력
- [ ] 도메인 에이전트가 도구 호출 → 응답 받음
- [ ] 검증 카드 (passed) + 리포트 카드 (markdown + 차트) 표시

> **`🧪 시나리오 라이브 모니터` 탭은 PoC 시연용 자원 (ECS scenario generator) 이 customer 환경에 없어 동작하지 않아. 무시하세요.** 분석은 4개 탭으로만.

---

## 16. 트러블슈팅

| 증상 | 확인 / 해결 |
|---|---|
| **CloudFront 502** | `aws ecs describe-services ...` 로 task running 인지. ALB target health 도 (콘솔 → EC2 → Target Groups) |
| Streamlit task 가 STOPPED | `aws logs tail /ecs/dbaops-customer-streamlit --since 10m` 로 컨테이너 로그 확인. `AGENTCORE_RUNTIME_ARN` 미설정이 흔한 원인 — step 14 의 `-var=agentcore_runtime_arn=` 다시 |
| 응답에 "타임아웃" / "도구 호출 실패" | Lambda 가 RDS 등에 못 닿는 것. step 11 의 SG inbound 추가 |
| `register_gateway_targets.py` 가 권한 에러 | `bedrock-agentcore-control:*` IAM 액션 누락. `docs/CUSTOMER_ONBOARDING.md` 의 `BedrockAgentCore` Sid 적용 |
| Bedrock 호출이 `AccessDeniedException` | IAM policy 의 `bedrock:InvokeModel` / `bedrock:InvokeModelWithResponseStream` 액션 부여 확인. region 도 ap-northeast-2 인지 |
| 이미지 빌드 실패 (linux/arm64 unsupported) | `docker buildx ls` 로 ARM64 builder 확인. Docker Desktop 4.x+ 또는 Linux 의 qemu-user-static 필요 |
| Lambda 가 `Image Not Found` | 1차 apply 가 ECR repo 만 만들고 step 10 빌드 안 했을 때. step 10 을 확실히 |
| `community-postgres` Lambda 가 `KeyError: 'username'` | 고객 secret 이 `{"user":"..."}` 같이 다른 키명. RDS 의 `master_user_secret` 자동 발급 secret 으로 교체하거나 `{"username":"..","password":".."}` 형식으로 재생성 |
| `awslabs-aws-doc` 호출이 timeout | private subnet 에 NAT 없음. step 0 의 NAT 점검 — customer VPC 에 NAT 추가 또는 `create_vpc=true` 로 신규 VPC 사용 |
| `register_gateway_targets.py` 가 `ModuleNotFoundError: boto3` | `pip install boto3` 후 재실행 |
| `terraform apply` 가 `error: ... already exists` (Cognito domain 등) | 이전 시도가 실패해 자원이 남음. 콘솔에서 manual 삭제 후 재시도 |
| Aurora reader/writer 식별자가 prompt 에 안 보임 | step 7 의 `customer_aurora_writer_id` 등 채웠는지. 빈값이면 LLM 이 사용자에게 물어봄 — 동작은 하지만 UX 나쁨 |

---

## 17. 비용 예측

샌드박스용으로 24시간 켜둘 때 (서울 리전, 2026 Q2 기준 추정):

| 자원 | 월 비용 |
|---|---|
| ALB (Streamlit) | ~$16 |
| CloudFront (저트래픽) | ~$1 |
| ECS Fargate Spot 1 task (0.5 vCPU / 1 GB) | ~$3 |
| Lambda 10개 (호출당, 데모 트래픽) | ~$1 |
| AgentCore Runtime (preview) | ?? — 별도 책정 (호출당) |
| Bedrock Opus 4.7 호출 | 호출당 — 데모 1회 ~$0.05~0.20 |
| ECR storage 14 repo | ~$1 |
| **합계 (인프라)** | **~$22/월** + Bedrock 호출 비용 |

데모 끝나면 step 18 destroy 로 거의 0 으로 회수.

---

## 18. 데모 종료 시 destroy

### 옵션 A — 일시 중단 (재개 가능)

```bash
# Streamlit task 만 0 으로
aws ecs update-service --cluster dbaops-customer --service dbaops-customer-streamlit \
  --desired-count 0 --region ap-northeast-2

# CloudFront disable
aws cloudfront list-distributions --region ap-northeast-2 --no-cli-pager \
  --query 'DistributionList.Items[?Comment==`DBAOps-Agent Streamlit demo`].Id'
# → 그 ID 의 distribution 을 콘솔 또는 CLI 로 disabled
```

### 옵션 B — 완전 삭제

```bash
cd infra/envs/customer
RUNTIME_ARN=$(...)

# 1) Streamlit service 먼저 destroy
terraform destroy \
  -target=module.streamlit \
  -var=mcp_images_pushed=true \
  -var=streamlit_image_pushed=true \
  -var="agentcore_runtime_arn=${RUNTIME_ARN}"

# 2) AgentCore Runtime / Gateway — 별도 (terraform 외부)
aws bedrock-agentcore-control delete-agent-runtime \
  --agent-runtime-id <id> --region ap-northeast-2

aws bedrock-agentcore-control delete-gateway \
  --gateway-identifier <id> --region ap-northeast-2

# 3) 나머지 전체 destroy
terraform destroy \
  -var=mcp_images_pushed=true \
  -var=streamlit_image_pushed=true \
  -var="agentcore_runtime_arn=${RUNTIME_ARN}"

# 4) ECR repo 안의 이미지 강제 삭제 (force_delete=true 라 자동)

# 5) state 까지 지우려면
aws s3 rb s3://dbaops-tfstate-${ACCOUNT_ID}-ap-northeast-2 --force --region ap-northeast-2
aws dynamodb delete-table --table-name dbaops-tfstate-lock --region ap-northeast-2
```

---

## 19. 다음 단계

- [docs/SERVICE_GUIDE.md](SERVICE_GUIDE.md) — 시스템 아키텍처 자세히
- [docs/EXTERNAL_RESOURCES.md](EXTERNAL_RESOURCES.md) — 외부 리소스 매핑 깊게
- [docs/CUSTOMER_ONBOARDING.md](CUSTOMER_ONBOARDING.md) — IAM 권한 요청서

질문이나 막힘이 있으면 issue 로.
