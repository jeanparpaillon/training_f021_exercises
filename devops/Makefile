PYTHON := $(shell which python3)
VENV := .venv

IMAGE = noble-server-cloudimg-amd64.img
LAB_IMAGE = geerlingguy/docker-ubuntu2404-ansible
LAB_CONTAINERS = master worker1 worker2

all: $(IMAGE)

ansible-lab:
	for container in $(LAB_CONTAINERS); do \
		docker run -d --name $$container $(LAB_IMAGE) sleep infinity; \
	done

clean-ansible-lab:
	for container in $(LAB_CONTAINERS); do \
		docker kill $$container || true; \
		docker rm $$container || true; \
	done

setup-env: | $(VENV)

$(VENV):
	@echo "🚀 Setting up environment..."
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements.txt
	@echo "✅ Done! Activate with: source $(VENV)/bin/activate"

activate:
	@echo "source $(VENV)/bin/activate"

venv-clean:
	rm -rf $(VENV)
	find . -type d -name "__pycache__" -exec rm -rf {} +

$(IMAGE):
	wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

.PHONY: all destroy clean inventory setup setup-env activate venv-clean
.PHONY: tf-init tf-plan tf-apply tf-output tf-destroy tf-console
.PHONY: ansible-inventory ansible-galaxy ansible-setup ansible-clean ansible-playbook ansible-verify
.PHONY: molecule-test molecule-converge molecule-verify molecule-reset
