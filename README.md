# DBAOps-Agent

> DB / 인프라 분석 자동화 에이전트 — LangGraph + AWS Bedrock AgentCore + MCP.

자연어로 "최근 1시간 EC2 CPU peak 보여줘" 라고 물으면 → AI 분석가가 도구를 직접 골라 호출 → 검증 단계로 거짓말·인용 누락을 거른 다음 → 차트 포함 markdown 리포트로 답한다.

이 repo 는 **고객 자기 인프라(자기 PG/MySQL/Prometheus/MSK/S3) 위에 agent 시스템만 얹는** 배포본이다. test bed (Aurora/MySQL/MSK 데모용 cluster + 시나리오 generator) 는 포함 안 됨.

---

## 무엇이 들어있나

| 영역 | 위치 |
|---|---|
| Agent (LangGraph pipeline + 단일 에이전트) | `agent/` |
| Streamlit UI (4 탭) | `ui/streamlit/` |
| 10 MCP server Lambda (4 우리 PoC + 3 awslabs + 3 community) | `mcp_tools/` |
| Terraform — VPC(옵션), IAM, AgentCore, ECS Streamlit | `infra/modules/`, `infra/envs/customer/` |
| 빌드 / 등록 스크립트 | `scripts/` |
| 서비스 가이드 | `docs/SERVICE_GUIDE.md` |

**처음 배포한다면 → [docs/QUICKSTART.md](docs/QUICKSTART.md) 19단계 step-by-step 가이드** 를 따라가세요.

자세한 아키텍처는 [docs/SERVICE_GUIDE.md](docs/SERVICE_GUIDE.md) 참조.

---

## 사전 요구사항

- AWS account (단일 계정, 기본 리전 `ap-northeast-2`)
- 고객이 보유한 다음 중 최소 1개 (없으면 빈값으로 두면 됨):
  - PostgreSQL endpoint + Secrets Manager secret (필수)
  - MySQL endpoint + secret (옵션)
  - Prometheus URL (in-VPC, 옵션)
  - MSK cluster name + topic + consumer group (옵션)
  - S3 log bucket (옵션)
- **Lambda 가 위 자원에 도달 가능한 VPC/SG** (고객 책임)
- 로컬:
  - AWS CLI v2
  - Terraform 1.7+
  - Docker buildx (linux/arm64 지원)
  - Python 3.12+

IAM 권한 요청서 — [docs/CUSTOMER_ONBOARDING.md](docs/CUSTOMER_ONBOARDING.md) 의 JSON 그대로 클라우드 팀에 제출.

---

## 5단계 배포 (요약)

> **처음 배포라면 [QUICKSTART.md](docs/QUICKSTART.md) 의 19단계 가이드를 그대로 따라가세요**. 이 README 의 5단계는 이미 한 번 해본 사람을 위한 요약.

### 1. 변수 채우기

```bash
cd infra/envs/customer
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars   # customer_pg_host, customer_vpc_id 등 채움
cp backend.tf.example backend.tf
$EDITOR backend.tf         # 본인 계정의 state bucket / lock table
```

### 2. 1차 apply (ECR repo + VPC/IAM/AgentCore role + ALB/CloudFront)

```bash
terraform init
terraform apply -var=mcp_images_pushed=false -var=streamlit_image_pushed=false
```

### 3. 컨테이너 이미지 빌드 + ECR push

```bash
cd ../../..
bash scripts/build_mcp_images.sh        # 10 MCP Lambda
bash scripts/build_agent_image.sh       # AgentCore Runtime
bash scripts/build_streamlit_image.sh   # UI
```

### 4. 2차 apply (MCP Lambda 생성) + AgentCore 등록

```bash
cd infra/envs/customer
terraform apply -var=mcp_images_pushed=true -var=streamlit_image_pushed=false

cd ../../..
ENV=customer python scripts/register_gateway_targets.py   # Gateway target 10개 + Runtime 등록
```

스크립트 출력 끝부분의 `agentRuntimeArn` 값을 메모해 둠.

### 5. 3차 apply (Streamlit ECS service 생성)

```bash
cd infra/envs/customer
terraform apply \
  -var=mcp_images_pushed=true \
  -var=streamlit_image_pushed=true \
  -var=agentcore_runtime_arn=arn:aws:bedrock-agentcore:ap-northeast-2:<account>:runtime/dbaops_customer-XXXXX

terraform output streamlit_url
# → https://dXXXXX.cloudfront.net
```

이 URL 로 접속하면 4 탭 UI 가 동작.

---

## 동작 확인

1. `🖥️ OS·인프라 메트릭` 탭 — "EC2 prometheus 최근 1시간 CPU peak" 같은 질문
2. `🗄️ DB 성능 메트릭` 탭 — "PG 활성 세션과 락 상태" 같은 질문
3. `📜 로그 분석` 탭 — "최근 deadlock 로그" 같은 질문
4. `🧠 단일 에이전트` 탭 — 모든 도구 풀 평탄화 모드 (비교용)

응답에 도구 인용·차트가 포함된다.

---

## 변경 후 재배포

| 변경 | 다시 해야 할 것 |
|---|---|
| `agent/`, `prompts/` | `bash scripts/build_agent_image.sh` + `aws bedrock-agentcore-control update-agent-runtime` |
| `mcp_tools/<dir>/handler.py` | 해당 Dockerfile 빌드 + `aws lambda update-function-code` |
| `mcp_tools/<dir>/tool_io.json` | `ENV=customer python scripts/register_gateway_targets.py` |
| Terraform | `terraform apply` |
| `ui/streamlit/` | `bash scripts/build_streamlit_image.sh` + ECS service force-new-deployment |

---

## 문서

- **[docs/QUICKSTART.md](docs/QUICKSTART.md)** — **처음 배포 시 따라할 19단계 가이드 (필독)**
- [docs/SERVICE_GUIDE.md](docs/SERVICE_GUIDE.md) — 아키텍처 / 그래프 / MCP / AgentCore 구성 (코드 기반)
- [docs/CUSTOMER_ONBOARDING.md](docs/CUSTOMER_ONBOARDING.md) — IAM 권한 요청서 + 외부 자원 매핑
- [docs/EXTERNAL_RESOURCES.md](docs/EXTERNAL_RESOURCES.md) — 고객이 제공해야 할 자원·env 매핑 표

---

## 라이선스 / 출처

- 우리 코드: 사내 사용
- 외부 MCP: pab1it0/prometheus-mcp-server, crystaldba/postgres-mcp, benborla/mcp-server-mysql, awslabs.cloudwatch-mcp-server, awslabs.aws-documentation-mcp-server, awslabs.aws-api-mcp-server (각 라이선스 따름)
