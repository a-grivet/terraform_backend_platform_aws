FROM alpine:3.21
ARG TERRAFORM_VERSION=1.14.7
ARG TERRAFORM_AWS_PROVIDER_VERSION=5.100.0
ARG TFLINT_VERSION=0.56.0
ARG TFLINT_AWS_RULESET_VERSION=0.40.0

RUN apk add --no-cache \
    aws-cli \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    unzip \
    zip

RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip

RUN mkdir -p "/opt/terraform-provider-mirror/registry.terraform.io/hashicorp/aws/${TERRAFORM_AWS_PROVIDER_VERSION}/linux_amd64" \
    && curl -fsSL "https://releases.hashicorp.com/terraform-provider-aws/${TERRAFORM_AWS_PROVIDER_VERSION}/terraform-provider-aws_${TERRAFORM_AWS_PROVIDER_VERSION}_linux_amd64.zip" -o /tmp/terraform-provider-aws.zip \
    && unzip /tmp/terraform-provider-aws.zip -d "/opt/terraform-provider-mirror/registry.terraform.io/hashicorp/aws/${TERRAFORM_AWS_PROVIDER_VERSION}/linux_amd64" \
    && rm /tmp/terraform-provider-aws.zip

RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" -o /tmp/tflint.zip \
    && unzip /tmp/tflint.zip -d /usr/local/bin \
    && rm /tmp/tflint.zip

RUN mkdir -p /usr/local/share/tflint-plugins \
    && curl -fsSL "https://github.com/terraform-linters/tflint-ruleset-aws/releases/download/v${TFLINT_AWS_RULESET_VERSION}/tflint-ruleset-aws_linux_amd64.zip" -o /tmp/tflint-ruleset-aws.zip \
    && unzip /tmp/tflint-ruleset-aws.zip -d /usr/local/share/tflint-plugins \
    && rm /tmp/tflint-ruleset-aws.zip

RUN mkdir -p /etc/terraform.d

WORKDIR /workspace

COPY scripts/runner/ /app/scripts/
COPY config/terraform.rc /etc/terraform.d/terraform.rc

RUN chmod +x /app/scripts/*.sh

ENV TF_CLI_CONFIG_FILE=/etc/terraform.d/terraform.rc
ENV INCA_SUPPORTED_TERRAFORM_PROVIDER=registry.terraform.io/hashicorp/aws
ENV INCA_SUPPORTED_TERRAFORM_PROVIDER_VERSION=${TERRAFORM_AWS_PROVIDER_VERSION}
ENV TFLINT_PLUGIN_DIR=/usr/local/share/tflint-plugins

ENTRYPOINT ["/bin/bash"]
