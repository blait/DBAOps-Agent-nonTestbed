# 외부 자원 — 고객이 제공해야 할 것

agent 가 분석할 대상은 고객 자기 것. 이 표대로 endpoint·식별자를 확보해 `terraform.tfvars` 에 채운다.

## 필수 vs 옵션

| 자원 | 필수? | terraform 변수 | 채울 곳 |
|---|---|---|---|
| **VPC** | 필수 | `customer_vpc_id`, `customer_private_subnet_ids`, `customer_public_subnet_ids` | RDS/Prometheus 가 있는 VPC. private subnet 에서 private resource 도달 가능해야. public subnet 은 ALB/Streamlit 용 (NAT 통해 ECR pull). |
| **PostgreSQL endpoint** | 필수 | `customer_pg_host`, `customer_pg_dbname`, `customer_pg_secret_arn` | Aurora 또는 일반 PG. SG 에 Lambda SG 의 5432 인바운드 허용 |
| **PG secret** | 필수 | `customer_pg_secret_arn` | `{"username":"...","password":"..."}` JSON. RDS master_user_secret 자동 발급 secret 사용 가능 |
| **MySQL endpoint** | 옵션 | `customer_mysql_host`, `customer_mysql_dbname`, `customer_mysql_secret_arn` | 없으면 빈 값. SG 에 Lambda SG 의 3306 허용 |
| **Prometheus URL** | 옵션 | `customer_prometheus_url` | `http://<host>:9090`. SG 에 Lambda SG 의 9090 허용 |
| **MSK cluster** | 옵션 | `customer_msk_cluster_name`, `customer_kafka_default_topic`, `customer_kafka_default_cg` | CloudWatch dim "Cluster Name" 값. IAM SASL auth 만 지원 |
| **S3 log bucket** | 옵션 | `customer_log_bucket`, `customer_log_bucket_arn` | gz/log 파일 적재된 bucket. agent 의 `s3_list_logs` 가 prefix 로 검색 |

## Agent prompt 식별자 — 별도

prompt 의 `<infra_identifiers>` 섹션이 자동으로 채워진다. RDS/EC2 콘솔에서 복사:

| 변수 | 의미 | 콘솔에서 |
|---|---|---|
| `customer_prom_instance_id`  | Prometheus EC2 InstanceId | EC2 → instance ID |
| `customer_aurora_cluster_id` | Aurora cluster identifier | RDS → Cluster identifier |
| `customer_aurora_writer_id`  | Aurora writer DBInstanceIdentifier | RDS → primary instance |
| `customer_aurora_reader_id`  | reader (있으면) | RDS → reader instance |
| `customer_mysql_db_id`       | RDS MySQL DBInstanceIdentifier | RDS → instance |

빈값이어도 동작 — agent 가 "id 비었음" 인지하고 사용자에게 묻거나 도구로 발견.

## 네트워크 / SG 점검표

배포 전에 클라우드 팀과 다음 확인:

- [ ] 위 VPC 에 NAT 가 있어 ECR pull 가능
- [ ] Lambda 가 도달해야 하는 RDS / Prometheus / MSK SG 에 **새로 생성될 MCP Lambda SG (terraform 이 만듦)** 의 인바운드 허용
  - 첫 apply 후 SG ID 가 outputs 에 노출 안 되니 Lambda 자원에서 직접 확인 후 수동 추가 (또는 customer 측에서 미리 wide-open)
- [ ] Streamlit ALB 의 SG 가 CloudFront prefix list 만 허용 (default 동작 — 추가 작업 X)

## Lambda 환경변수 매핑 (참고)

terraform 이 자동으로 채우는 매핑 — 직접 수정 불필요:

| Lambda | env var | 값 |
|---|---|---|
| community-postgres | `PG_HOST`, `PG_DBNAME`, `PG_SECRET_ARN`, `PG_PORT` | customer_pg_* |
| community-mysql | `MYSQL_HOST`, `MYSQL_DB`, `MYSQL_SECRET_ARN`, `MYSQL_PORT` | customer_mysql_* |
| community-prometheus | `PROMETHEUS_URL` | customer_prometheus_url |
| msk-metrics | `KAFKA_CLUSTER_NAME`, `KAFKA_DEFAULT_TOPIC`, `KAFKA_DEFAULT_CG` | customer_msk_*, customer_kafka_* |
| s3-log-fetch / aws-api / rds-pi / awslabs-* | (도구 호출 인자로 받음) | — |

## AgentCore Runtime 환경변수 (register 스크립트가 채움)

`scripts/register_gateway_targets.py` 가 다음을 set:

- `BEDROCK_MODEL_ID`, `BEDROCK_REGION`
- `GATEWAY_ENDPOINT`, `COGNITO_*`
- `INFRA_*` — `terraform.tfvars` 의 `customer_*_id` 값. 환경변수 `INFRA_PROM_INSTANCE_ID` 등으로도 override 가능.

→ `terraform.tfvars` 의 `customer_aurora_writer_id` 같은 값이 register 스크립트로 흘러가 Runtime env 가 됨.
