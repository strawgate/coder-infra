.PHONY: plan apply destroy connect ssh stop start fmt validate login smoke-test

# --- Control plane ---

plan:
	cd control-plane && terraform plan

apply:
	cd control-plane && terraform apply

destroy:
	cd control-plane && terraform destroy

fmt:
	terraform fmt -recursive

validate:
	cd control-plane && terraform validate

# --- Convenience ---

connect:
	@./scripts/connect.sh

login:
	@./scripts/login.sh

ssh:
	@./scripts/ssh.sh

stop:
	@./scripts/stop.sh

start:
	@./scripts/start.sh

smoke-test:
	@./scripts/smoke-test.sh

# --- First-time setup ---

init:
	cd control-plane && terraform init -backend-config="bucket=$(TF_STATE_BUCKET)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. cp control-plane/terraform.tfvars.example control-plane/terraform.tfvars"
	@echo "  2. Edit control-plane/terraform.tfvars with your project ID and email"
	@echo "  3. make apply"
	@echo "  4. make connect"
	@echo "  5. Open http://localhost:3000 and create your admin account"

# --- CI bootstrap ---

bootstrap-ci:
	@./scripts/bootstrap-ci.sh $(GCP_PROJECT_ID) $(GITHUB_REPO)

# Migrate local state to remote GCS backend
migrate-state:
	cd control-plane && terraform init -migrate-state -backend-config="bucket=$(TF_STATE_BUCKET)"
