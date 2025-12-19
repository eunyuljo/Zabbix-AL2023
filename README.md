# Zabbix 7.0 Terraform Infrastructure

이 Terraform 구성은 AWS에서 Zabbix 7.0 모니터링 시스템을 자동으로 배포합니다.

## 아키텍처

- **VPC**: 전용 가상 사설망 (10.0.0.0/16)
- **서브넷**: 퍼블릭/프라이빗 서브넷 (2개 AZ)
- **EC2**: Amazon Linux 2023 (t3.medium)
- **보안**: Security Group으로 포트 제어
- **자동화**: User Data를 통한 완전 자동 설치

## 구성 요소

### 네트워크
- VPC (10.0.0.0/16)
- 퍼블릭 서브넷 2개 (10.0.1.0/24, 10.0.2.0/24)
- 프라이빗 서브넷 2개 (10.0.10.0/24, 10.0.20.0/24)
- Internet Gateway
- NAT Gateway

### 보안
- Zabbix 서버용 Security Group
  - SSH (22): 외부 접근
  - HTTP (80): 웹 인터페이스
  - HTTPS (443): 보안 웹 접근
  - Zabbix Server (10051): 에이전트 연결
  - MySQL (3306): 로컬 DB 연결
- Zabbix 에이전트용 Security Group (향후 사용)

### 애플리케이션
- Zabbix 7.0 Server
- MySQL 8.0 Community Server
- Apache HTTP Server
- PHP 8.x

### IAM 및 접근 관리
- EC2용 SSM 역할 (AmazonSSMManagedInstanceCore)
- CloudWatch Agent 권한
- Session Manager를 통한 브라우저 기반 접속 지원

## 사전 준비사항

1. **AWS CLI 설정**
   ```bash
   aws configure
   ```

2. **SSH 키페어 생성**
   ```bash
   ssh-keygen -t rsa -b 2048 -f ~/.ssh/zabbix-key
   ```

3. **Terraform 설치**
   ```bash
   # Amazon Linux 2023
   sudo yum install -y yum-utils
   sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
   sudo yum -y install terraform
   ```

4. **Session Manager Plugin 설치** (선택사항, SSM 접속용)
   ```bash
   # Amazon Linux 2023
   curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
   sudo yum install -y session-manager-plugin.rpm
   ```

## 배포 방법

1. **저장소 클론 및 디렉토리 이동**
   ```bash
   cd zabbix
   ```

2. **변수 설정**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars
   ```

3. **Terraform 초기화**
   ```bash
   terraform init
   ```

4. **배포 계획 검토**
   ```bash
   terraform plan
   ```

5. **배포 실행**
   ```bash
   terraform apply
   ```

## 설정 변수

주요 변수들을 `terraform.tfvars` 파일에서 수정할 수 있습니다:

```hcl
# 리전 설정
aws_region = "ap-northeast-2"

# 프로젝트 정보
project_name = "zabbix"
environment  = "prod"

# 인스턴스 설정
instance_type = "t3.medium"
key_pair_name = "zabbix-key"

# 네트워크 설정
vpc_cidr = "10.0.0.0/16"
allowed_cidr_blocks = ["0.0.0.0/0"]  # 보안을 위해 특정 IP로 제한 권장

# 데이터베이스 암호 (민감 정보)
mysql_root_password = "your-secure-root-password"
zabbix_db_password  = "your-secure-zabbix-password"
```

## 배포 후 접속

배포가 완료되면 다음과 같은 출력을 확인할 수 있습니다:

```bash
# Zabbix 웹 인터페이스
zabbix_web_url = "http://PUBLIC_IP/zabbix"

# SSH 접속
ssh_connection_command = "ssh -i ~/.ssh/zabbix-key.pem ec2-user@PUBLIC_IP"

# SSM Session Manager 접속 (SSH 키 불필요)
ssm_connection_command = "aws ssm start-session --target i-1234567890abcdef0"
```

## Zabbix 초기 설정

1. **웹 인터페이스 접속**
   - URL: `http://[PUBLIC_IP]/zabbix`
   - 초기 계정: `Admin` / `zabbix`

2. **보안 설정**
   - 기본 패스워드 변경
   - SSL 인증서 설정 (선택사항)
   - 관리자 계정 추가

3. **모니터링 설정**
   - 호스트 그룹 생성
   - 모니터링 대상 추가
   - 알림 설정

## 자동 설치 과정

User Data 스크립트가 다음 작업을 자동으로 수행합니다:

1. **Bootstrap**: 설치 스크립트 생성 및 실행 준비
2. **패키지 설치**: Zabbix 7.0, PHP 8.x, Apache, MySQL 8.0 설치
3. **MySQL 보안 설정**: 다중 방법으로 root 패스워드 설정
4. **데이터베이스 구성**: Zabbix 데이터베이스 생성 및 스키마 임포트
5. **서비스 구성**: Zabbix 서버, Apache, PHP-FPM 설정
6. **서비스 시작**: 모든 서비스 시작 및 활성화
7. **검증 및 완료**: 설치 상태 확인 및 완료 보고

### 🔄 **재실행 안전성**
- 마커 시스템으로 완료된 단계 자동 스킵
- Cloud-init 중복 실행 시에도 안전
- 부분 실패 시 재실행으로 자동 복구

## 모니터링 및 로그

- **설치 로그**: `/var/log/zabbix-install.log`
- **설치 정보**: `/home/ec2-user/zabbix-install-info.txt`
- **서비스 상태 확인**:
  ```bash
  sudo systemctl status zabbix-server
  sudo systemctl status zabbix-agent
  sudo systemctl status httpd
  sudo systemctl status mysqld
  ```

## 비용 최적화

- 개발/테스트 환경: `t3.small` 또는 `t3.micro` 사용
- 운영 환경: `t3.medium` 이상 권장
- 필요 시 Reserved Instance 구매로 비용 절약

## 보안 고려사항

1. **네트워크 보안**
   - `allowed_cidr_blocks`를 특정 IP 대역으로 제한
   - Private subnet에 민감한 리소스 배치

2. **데이터베이스 보안**
   - 강력한 패스워드 사용
   - 정기적인 백업 수행
   - 데이터 암호화 활성화

3. **서버 보안**
   - 정기적인 시스템 업데이트
   - 불필요한 포트 차단
   - SSH 키 기반 인증 사용

## 정리 (Clean Up)

리소스를 제거할 때:

```bash
terraform destroy
```

## 지원 및 문의

- Terraform 문서: https://registry.terraform.io/providers/hashicorp/aws/
- Zabbix 문서: https://www.zabbix.com/documentation/7.0/
- AWS 문서: https://docs.aws.amazon.com/

## 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.