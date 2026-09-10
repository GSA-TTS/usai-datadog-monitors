`Terraform Validate` CI workflow on pull requests — `terraform init -backend=false`,
`fmt -check -recursive` and `validate`, copied verbatim from `usai-github-config` so both
Terraform repos run the same gate. This repo had no CI at all, so #52, #53 and #54 all merged
with zero checks.
