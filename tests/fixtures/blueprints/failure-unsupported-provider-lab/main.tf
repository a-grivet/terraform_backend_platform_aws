# Blueprint: failure-unsupported-provider-lab
#
# Role: Intentionally broken Terraform blueprint — declares a provider
#       (hashicorp/random) that is not present in the runner's offline provider
#       mirror, causing terraform init to fail. The choice of hashicorp/random
#       is arbitrary; any provider outside the supported baseline would produce
#       the same result.
#
# Purpose: Tests the negative path of the validation flow. Verifies that the
#          validation Step Functions state machine correctly catches a terraform
#          init failure, marks the upload intent as VALIDATION_FAILED in
#          DynamoDB, and does not progress to the READY state.
#          This blueprint must never be used with a live internet connection
#          because the provider would then download successfully and the test
#          would pass incorrectly.
#
# CI usage: not yet wired to a dedicated CI job — tested manually or via a
#           future smoke_test_validation_failure_dev job.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_pet" "example" {
  length = 2
}

output "generated_name" {
  value = random_pet.example.id
}
