<!-- pipeline-config: managed by /pipeline-init -->
## Pipeline configuration

- default_branch: main
- pr_target_branch: main
- test_command: cd terraform && terraform validate
- lint_command:
- format_command: cd terraform && terraform fmt -check -recursive
- build_command:
- venv_path:
- changelog: keep-a-changelog
<!-- /pipeline-config -->
