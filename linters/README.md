# Linter GitHub Actions

A collection of Linter GitHub Actions.

* [actionlint](actionlint/README.md) is a static checker for GitHub Actions workflow files
* [bandit](bandit/README.md) is a security linter from PyCQA
* [cfnlint](cfnlint/README.md) is a linter for AWS CloudFormation templates that validates syntax, resource properties, and best practices
* [checkov](checkov/README.md) is an Infrastructure-as-Code security scanner for Terraform, CloudFormation, Kubernetes, and Dockerfiles
* [eslint](eslint/README.md) is a tool for identifying and reporting on patterns found in ECMAScript/JavaScript code
* [flake8](flake8/README.md) is a wrapper around PyFlakes, pycodestyle and Ned Batchelder's McCabe script
* [golangci](golangci/README.md) is a fast Go linters runner
* [hadolint](hadolint/README.md) is a smarter Dockerfile linter that helps you build best practice Docker images
* [ktlint](ktlint/README.md) is an anti-bikeshedding Kotlin linter with built-in formatter
* [markdownlint](markdownlint/README.md) is a style checker and lint tool for Markdown/CommonMark files
* [phpcs](phpcs/README.md) the PHP Coding Standards Fixer (PHP CS Fixer) tool fixes your code to follow standards
* [phpstan](phpstan/README.md) PHPStan scans your whole codebase and looks for both obvious & tricky bugs
* [pmd](pmd/README.md) is a source code analyzer
* [protolint](protolint/README.md) is a pluggable linter and fixer to enforce Protocol Buffer style and conventions
* [rubocop](rubocop/README.md) is a Ruby static code analyzer and code formatter
* [semgrep](semgrep/README.md) is a static analysis security scanner that finds bugs and enforces code standards
* [shellcheck](shellcheck/README.md) is a tool that gives warnings and suggestions for bash/sh shell scripts
* [swiftlint](swiftlint/README.md) is a tool to enforce Swift style and conventions
* [trivy](trivy/README.md) is a container and Infrastructure-as-Code vulnerability scanner
* [yamllint](yamllint/README.md) is a linter for YAML files

---

## Maintenance Guidelines

All linter actions follow a **common structure** to ensure consistency. When adding or updating linters, follow these guidelines.

### Common Structure

Every linter action must have these sections in order:

```yaml
---
name: 'LinterName'
description: 'Execute lintername'

inputs:
  # 1. REQUIRED COMMON INPUTS (do not modify)
  linters:
    description: 'List of all enabled linters'
    required: true
  ssh-key:
    description: 'ssh key'
    required: true
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}

  # 2. LINTER-SPECIFIC INPUTS (optional, add as needed)
  # ...

runs:
  using: "composite"
  steps:
    # 3. CHECK STEP (required, only change LINTER_NAME)
    - id: check
      shell: bash
      env:
        GITHUB_TOKEN: ${{ inputs.github-token }}
        LINTERS: ${{ inputs.linters }}
      run: if echo "${LINTERS}" | grep LINTER_NAME &> /dev/null; then echo "continue=true" >> "${GITHUB_OUTPUT}"; else echo "continue=false" >> "${GITHUB_OUTPUT}"; fi

    # 4. CHECKOUT STEP (required, do not modify)
    - name: Checkout
      uses: actions/checkout@v6
      if: ${{ steps.check.outputs.continue == 'true' }}
      with:
        token: ${{ inputs.github-token }}
        ssh-key: ${{ inputs.ssh-key }}
        persist-credentials: false
        lfs: true
        submodules: recursive

    # 5. SETUP STEPS (optional, linter-specific)
    # ...

    # 6. LINTER EXECUTION STEP (required, linter-specific)
    # ...
```

### Checklist: Adding a New Linter

* [ ] Create directory `linters/<lintername>/`
* [ ] Copy structure from an existing simple linter (e.g., `bandit/action.yml`)
* [ ] Update `name` and `description`
* [ ] Update `LINTER_NAME` in check step (must match detection in `variables/variables.sh`)
* [ ] Add linter detection to `variables/variables.sh` if not already present
* [ ] Keep common inputs unchanged (`linters`, `ssh-key`, `github-token`)
* [ ] Keep checkout step unchanged
* [ ] Add linter-specific setup steps if needed
* [ ] Add linter execution step with `if: ${{ steps.check.outputs.continue == 'true' }}`
* [ ] Create `README.md` following existing patterns
* [ ] Add entry to this file's linter list
* [ ] Update `docs/architecture.md` software units section

### Checklist: Updating Common Sections

When updating the checkout action version or common inputs, **all 20 linter actions must be updated**:

* [ ] actionlint/action.yml
* [ ] bandit/action.yml
* [ ] cfnlint/action.yml
* [ ] checkov/action.yml
* [ ] eslint/action.yml
* [ ] flake8/action.yml
* [ ] golangci/action.yml
* [ ] hadolint/action.yml
* [ ] ktlint/action.yml
* [ ] markdownlint/action.yml
* [ ] phpcs/action.yml
* [ ] phpstan/action.yml
* [ ] pmd/action.yml
* [ ] protolint/action.yml
* [ ] rubocop/action.yml
* [ ] semgrep/action.yml
* [ ] shellcheck/action.yml
* [ ] swiftlint/action.yml
* [ ] trivy/action.yml
* [ ] yamllint/action.yml

**Tip:** Use find and sed for bulk updates:

```bash
# Example: Update checkout action version
find linters -name "action.yml" -exec sed -i '' 's/actions\/checkout@v5/actions\/checkout@v6/g' {} \;
```

### Common Reviewdog Settings

Most linters use reviewdog with these standard settings:

```yaml
with:
  fail_level: any
  filter_mode: nofilter
  github_token: ${{ inputs.github-token }}
  level: info
  reporter: github-pr-review
```

### Linter Detection

Linters are auto-detected in `variables/variables.sh` based on config file presence:

| Linter       | Detection File                   |
|--------------|----------------------------------|
| ACTIONLINT   | `.github/workflows/`             |
| BANDIT       | `.bandit`                        |
| CFNLINT      | `.cfnlintrc`                     |
| CHECKOV      | `.checkov.yaml`                  |
| ESLINT       | `.eslintrc.json`                 |
| FLAKE8       | `.flake8`                        |
| GOLANGCI     | `.golangci.yml`                  |
| HADOLINT     | `.hadolint.yaml`                 |
| KTLINT       | `.editorconfig` (Kotlin)         |
| MARKDOWNLINT | `.markdownlint.yml`              |
| PHPCS        | `.php-cs-fixer.dist.php`         |
| PHPSTAN      | `phpstan.neon`                   |
| PMD          | `.pmd.xml`                       |
| PROTOLINT    | `.protolint.yaml`                |
| RUBOCOP      | `.rubocop.yml`                   |
| SEMGREP      | `.semgrepignore`                 |
| SHELLCHECK   | `.shellcheckrc`                  |
| SWIFTLINT    | `.swiftlint.yml`                 |
| TRIVY        | `.trivyignore`                   |
| YAMLLINT     | `.yamllint.yml`                  |
