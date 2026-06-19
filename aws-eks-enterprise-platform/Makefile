###############################################################################
# Makefile — common dev-loop commands
###############################################################################

ENV ?= dev

.PHONY: init plan apply destroy validate fmt lint policy bootstrap

bootstrap:
	cd terraform/bootstrap && terraform init && terraform apply -auto-approve

init:
	cd terraform/environments/$(ENV) && \
	terraform init -backend-config=backend.hcl

validate:
	terraform fmt -check -recursive terraform/
	cd terraform/environments/$(ENV) && \
	terraform init -backend=false && \
	terraform validate

lint:
	tflint --recursive terraform/

plan:
	cd terraform/environments/$(ENV) && \
	terraform plan -out=tfplan.bin

apply:
	cd terraform/environments/$(ENV) && \
	terraform apply tfplan.bin

destroy:
	cd terraform/environments/$(ENV) && \
	terraform destroy

policy:
	cd terraform/environments/$(ENV) && \
	terraform plan -out=tfplan.bin && \
	terraform show -json tfplan.bin > tfplan.json && \
	conftest test --policy ../../policies tfplan.json && \
	rm tfplan.bin tfplan.json

fmt:
	terraform fmt -recursive terraform/
