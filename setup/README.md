# GitHub Action: Setup

This action performs setup of many common tools all at once. Please see the individual actions for more information.

* [checkout](<https://github.com/marketplace/actions/checkout>)
* [ssh-agent](<https://github.com/marketplace/actions/webfactory-ssh-agent>)
* [configure-aws-credentials](<https://github.com/marketplace/actions/configure-aws-credentials-action-for-github-actions>)
* [setup-php](<https://github.com/marketplace/actions/setup-php-action>)
* [setup-python](<https://github.com/marketplace/actions/setup-python>)
* [setup-ruby](<https://github.com/marketplace/actions/setup-ruby-jruby-and-truffleruby>)
* [setup-xcode](<https://github.com/marketplace/actions/setup-xcode-version>)
* [setup-elasticsearch](<https://github.com/marketplace/actions/run-elasticsearch-with-plugins>)
* [setup-mongodb](<https://github.com/marketplace/actions/mongodb-in-github-actions>)
* [setup-mysql](<https://github.com/marketplace/actions/actions-setup-mysql>)
* [setup-rabbitmq](<https://github.com/marketplace/actions/rabbitmq-in-github-actions>)
* [setup-redis](<https://github.com/marketplace/actions/actions-setup-redis>)

Take note that when you enable the setup action for a language, the corresponding [cache](<https://github.com/marketplace/actions/cache>) action(s) will also be automatically enabled.

## Auto-detection of Language Versions

This action automatically detects language version files in your repository and installs the corresponding languages without requiring explicit version inputs:

| Language | Version File              |
|----------|---------------------------|
| Go       | `.go-version`             |
| Java     | `.java-version`           |
| Node     | `.nvmrc`, `.node-version` |
| PHP      | `.php-version`            |
| Python   | `.python-version`         |
| Ruby     | `.ruby-version`           |

If a version file is present, the language will be installed using the version specified in the file. Explicit version inputs (e.g.,
`ruby-version: '3.2'`) will override auto-detection.

## Inputs

`setup` is a single composite action that orchestrates 123 inputs across many tools. Pass only the inputs for the tools you need; everything else is skipped. Inputs are grouped by tool below.

### Core

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `github-token` | no | `${{ github.token }}` | github token |
| `fetch-depth` | no | `1` | Number of commits to fetch. 0 indicates all history for all branches and tags. |
| `ssh-key` | no | — | ssh key |

### Languages & toolchains

#### Go

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `go-version` | no | `none` | The Go version to download (if necessary) and use. Supports semver spec and ranges. Be sure to enclose this option in single quotation marks. |
| `go-version-file` | no | — | Path to the go.mod or go.work file. |
| `go-check-latest` | no | `False` | Set this option to true if you want the action to always check for the latest available version that satisfies the version spec |
| `go-token` | no | `${{ github.server_url == '<https://github.com'> && github.token \|\| '' }}` | Used to pull Go distributions from go-versions. Since there's a default, this is typically not supplied by the user. When running this action on github.com, the default value is sufficient. When running on GHES, you can pass a personal access token for github.com if you are experiencing rate limiting. |
| `go-cache` | no | `True` | Used to specify whether caching is needed. Set to true, if you'd like to enable caching. |
| `go-cache-dependency-path` | no | — | Used to specify the path to a dependency file - go.sum |
| `go-architecture` | no | — | Target architecture for Go to use. Examples: x86, x64. Will use system architecture by default. |

#### Java

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `java-version` | no | `none` | The Java version to set up. Takes a whole or semver Java version. See examples of supported syntax in README file |
| `java-version-file` | no | — | The path to the `.java-version` file. See examples of supported syntax in README file |
| `java-distribution` | yes | `temurin` | Java distribution. See the list of supported distributions in README file |
| `java-package` | no | `jdk` | The package type (jdk, jre, jdk+fx, jre+fx) |
| `java-architecture` | no | — | The architecture of the package (defaults to the action runner's architecture) |
| `java-jdkFile` | no | — | Path to where the compressed JDK is located |
| `java-check-latest` | no | `False` | Set this option if you want the action to check for the latest available version that satisfies the version spec |
| `java-server-id` | no | `github` | ID of the distributionManagement repository in the pom.xml file. Default is `github` |
| `java-server-username` | no | `GITHUB_ACTOR` | Environment variable name for the username for authentication to the Apache Maven repository. Default is $GITHUB_ACTOR |
| `java-server-password` | no | `GITHUB_TOKEN` | Environment variable name for password or token for authentication to the Apache Maven repository. Default is $GITHUB_TOKEN |
| `java-settings-path` | no | — | Path to where the settings.xml file will be written. Default is ~/.m2. |
| `java-overwrite-settings` | no | `True` | Overwrite the settings.xml file if it exists. Default is "true". |
| `java-gpg-private-key` | no | — | GPG private key to import. Default is empty string. |
| `java-gpg-passphrase` | no | — | Environment variable name for the GPG private key passphrase. Default is $GPG_PASSPHRASE. |
| `java-cache` | no | — | Name of the build platform to cache dependencies. It can be "maven", "gradle" or "sbt". |
| `java-cache-dependency-path` | no | — | The path to a dependency file: pom.xml, build.gradle, build.sbt, etc. This option can be used with the `cache` option. If this option is omitted, the action searches for the dependency file in the entire repository. This option supports wildcards and a list of file names for caching multiple dependencies. |
| `java-job-status` | no | `${{ job.status }}` | Workaround to pass job status to post job step. This variable is not intended for manual setting |
| `java-token` | no | `${{ github.server_url == '<https://github.com'> && github.token \|\| '' }}` | The token used to authenticate when fetching version manifests hosted on github.com, such as for the Microsoft Build of OpenJDK. When running this action on github.com, the default value is sufficient. When running on GHES, you can pass a personal access token for github.com if you are experiencing rate limiting. |
| `java-mvn-toolchain-id` | no | — | Name of Maven Toolchain ID if the default name of "${distribution}_${java-version}" is not wanted. See examples of supported syntax in Advanced Usage file |
| `java-mvn-toolchain-vendor` | no | — | Name of Maven Toolchain Vendor if the default name of "${distribution}" is not wanted. See examples of supported syntax in Advanced Usage file |

#### Node.js

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `node-version` | no | `none` | Version Spec of the version to use. Examples: 12.x, 10.15.1, >=10.15.0. |
| `node-version-file` | no | — | File containing the version Spec of the version to use.  Examples: package.json, .nvmrc, .node-version, .tool-versions. |
| `node-architecture` | no | — | Target architecture for Node to use. Examples: x86, x64. Will use system architecture by default. |
| `node-check-latest` | no | `False` | Set this option if you want the action to check for the latest available version that satisfies the version spec. |
| `node-registry-url` | no | — | Optional registry to set up for auth. Will set the registry in a project level .npmrc and .yarnrc file, and set up auth to read in from env.NODE_AUTH_TOKEN. |
| `node-scope` | no | — | Optional scope for authenticating against scoped registries. Will fall back to the repository owner when using the GitHub Packages registry (<https://npm.pkg.github.com/>). |
| `node-token` | no | `${{ github.server_url == '<https://github.com'> && github.token \|\| '' }}` | Used to pull node distributions from node-versions. Since there's a default, this is typically not supplied by the user. When running this action on github.com, the default value is sufficient. When running on GHES, you can pass a personal access token for github.com if you are experiencing rate limiting. |
| `node-cache` | no | — | Used to specify a package manager for caching in the default directory. Supported values: npm, yarn, pnpm. |
| `node-cache-dependency-path` | no | — | Used to specify the path to a dependency file: package-lock.json, yarn.lock, etc. Supports wildcards or a list of file names for caching multiple dependencies. |

#### PHP

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `php-version` | no | `none` | Setup PHP version. |
| `php-version-file` | no | — | Setup PHP version from a file. |
| `php-extensions` | no | — | Setup PHP extensions |
| `php-ini-file` | no | `production` | Set base ini file |
| `php-ini-values` | no | — | Add values to php.ini |
| `php-coverage` | no | — | Setup code coverage driver |
| `php-tools` | no | `composer` | Setup popular tools globally |

#### Python

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `python-version` | no | `none` | Version range or exact version of a Python version to use, using SemVer's version range syntax. |
| `python-version-file` | no | — | File containing the Python version to use. Example: .python-version |
| `python-cache` | no | `pip` | Used to specify a package manager for caching in the default directory. Supported values: pip, pipenv. |
| `python-architecture` | no | — | The target architecture (x86, x64) of the Python interpreter. |
| `python-check-latest` | no | `False` | Set this option if you want the action to check for the latest available version that satisfies the version spec. |
| `python-token` | no | `${{ github.server_url == '<https://github.com'> && github.token \|\| '' }}` | Used to pull python distributions from actions/python-versions. Since there's a default, this is typically not supplied by the user. |
| `python-cache-dependency-path` | no | — | Used to specify the path to dependency files. Supports wildcards or a list of file names for caching multiple dependencies. |
| `python-update-environment` | no | `True` | Set this option if you want the action to update environment variables. |
| `python-allow-prereleases` | no | `False` | When 'true', a version range passed to 'python-version' input will match prerelease versions if no GA versions are found. Only 'x.y' version range is supported for CPython. |

#### Ruby

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `ruby-version` | no | `none` | Engine and version to use, see the syntax in the README. Reads from .ruby-version or .tool-versions if unset. |
| `ruby-rubygems` | no | `default` | The version of RubyGems to use. Either default, latest, or a version number |
| `ruby-bundler` | no | `default` | The version of Bundler to install. Either none, latest, Gemfile.lock, or a version number |
| `ruby-bundler-cache` | no | `false` | Run "bundle install", and cache the result automatically. Either true or false |
| `ruby-working-directory` | no | `.` | The working directory to use for resolving paths for .ruby-version, .tool-versions and Gemfile.lock |
| `ruby-cache-version` | no | `0` | Arbitrary string that will be added to the cache key of the bundler cache |
| `ruby-self-hosted` | no | — | Consider the runner as a self-hosted runner, which means not using prebuilt Ruby binaries which only work on GitHub-hosted runners or self-hosted runners with a very similar image to the ones used by GitHub runners. The default is to detect this automatically based on the OS, OS version and architecture. |
| `ruby-windows-toolchain` | no | — | This input allows to override the default toolchain setup on Windows. The default setting ('default') installs a toolchain based on the selected Ruby. Specifically, it installs MSYS2 if not already there and installs mingw/ucrt/mswin build tools and packages. It also sets environment variables using 'ridk' or 'vcvars64.bat' based on the selected Ruby. At present, the only other setting than 'default' is 'none', which only adds Ruby to PATH. No build tools or packages are installed, nor are any ENV setting changed to activate them. |

### Mobile / Apple

#### Android

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `android-sdk-version` | no | `none` | sdk version |
| `android-build-tools-version` | no | `33.0.2` | build tools version |
| `android-ndk-version` | no | — | ndk version |
| `android-cmake-version` | no | — | cmake version |
| `android-command-line-tools-version` | no | — | command line tools version |
| `android-cache-disabled` | no | `false` | disabled cache |
| `android-cache-key` | no | — | cache key |
| `android-generate-job-summary` | no | `true` | display job summary |
| `android-job-status` | no | `${{ job.status }}` | Workaround to pass job status to post job step. This variable is not intended for manual setting |

#### Xcode

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `xcode-version` | no | `none` | Version of Xcode to use |

### Cloud

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `aws-region` | no | — | AWS Region, e.g. us-east-2 |
| `aws-role-to-assume` | no | — | The Amazon Resource Name (ARN) of the role to assume. Use the provided credentials to assume an IAM role and configure the Actions environment with the assumed role credentials rather than with the provided credentials. |
| `aws-access-key-id` | no | — | AWS Access Key ID. Provide this key if you want to assume a role using access keys rather than a web identity token. |
| `aws-secret-access-key` | no | — | AWS Secret Access Key. Required if aws-access-key-id is provided. |
| `aws-session-token` | no | — | AWS Session Token. |
| `aws-web-identity-token-file` | no | — | Use the web identity token file from the provided file system path in order to assume an IAM role using a web identity, e.g. from within an Amazon EKS worker node. |
| `aws-role-chaining` | no | — | Use existing credentials from the environment to assume a new role, rather than providing credentials as input. |
| `aws-audience` | no | `sts.amazonaws.com` | The audience to use for the OIDC provider |
| `aws-http-proxy` | no | — | Proxy to use for the AWS SDK agent |
| `aws-mask-aws-account-id` | no | — | Whether to mask the AWS account ID for these credentials as a secret value. By default the account ID will not be masked |
| `aws-role-duration-seconds` | no | — | Role duration in seconds. Default is one hour. |
| `aws-role-external-id` | no | — | The external ID of the role to assume. |
| `aws-role-session-name` | no | — | Role session name (default: GitHubActions) |
| `aws-role-skip-session-tagging` | no | — | Skip session tagging during role assumption |
| `aws-inline-session-policy` | no | — | Define an inline session policy to use when assuming a role |
| `aws-managed-session-policies` | no | — | Define a list of managed session policies to use when assuming a role |
| `aws-output-credentials` | no | — | Whether to set credentials as step output |
| `aws-unset-current-credentials` | no | — | Whether to unset the existing credentials in your runner. May be useful if you run this action multiple times in the same job |
| `aws-disable-retry` | no | — | Whether to disable the retry and backoff mechanism when the assume role call fails. By default the retry mechanism is enabled |
| `aws-retry-max-attempts` | no | — | The maximum number of attempts it will attempt to retry the assume role call. By default it will retry 12 times |
| `aws-special-characters-workaround` | no | — | Some environments do not support special characters in AWS_SECRET_ACCESS_KEY. This option will retry fetching credentials until the secret access key does not contain special characters. This option overrides disable-retry and retry-max-attempts. This option is disabled by default |

### Services

#### Elasticsearch

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `elasticsearch-version` | no | `none` | The version of Elasticsearch |
| `elasticsearch-plugins` | no | — | Elasticsearch plugin strings |

#### MongoDB

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `mongodb-version` | no | `none` | MongoDB version to use |
| `mongodb-replica-set` | no | — | MongoDB replica set name (no replica set by default) |
| `mongodb-port` | no | `27017` | MongoDB port to use (default 27017) |
| `mongodb-db` | no | — | MongoDB db to create (default: none) |
| `mongodb-username` | no | — | MongoDB root username (default: none) |
| `mongodb-password` | no | — | MongoDB root password (default: none) |

#### MySQL

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `mysql-version` | no | `none` | The version of MySQL and MariaDB |
| `mysql-distribution` | no | `mysql` | The distribution. valid values are mysql or mariadb |
| `mysql-auto-start` | no | `true` | Start MySQL server if it is true |
| `mysql-my-cnf` | no | — | my.cnf settings for mysqld |
| `mysql-root-password` | no | — | password for the root user |
| `mysql-user` | no | — | name of a new user |
| `mysql-password` | no | — | password for the new user |

#### RabbitMQ

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `rabbitmq-version` | no | `none` | RabbitMQ version to use |
| `rabbitmq-ports` | no | `1883:1883` | Port mappings in a [host]:[container] format, delimited by spaces (example: "1883:1883 8883:8883") |
| `rabbitmq-certificates` | no | — | Absolute path to a directory containing certificate files which can be referenced in the config (the folder is mounted under `/rabbitmq-certs`) |
| `rabbitmq-config` | no | — | Absolute path to the `rabbitmq.conf` configuration file to use |
| `rabbitmq-definitions` | no | — | Absolute path to the `definitions.json` definition file to use (requires using a `x.y.z-management` image version or enabling the `rabbitmq_management` plugin) |
| `rabbitmq-plugins` | no | — | A comma separated list of RabbitMQ plugins which should be enabled |
| `rabbitmq-container-name` | no | `rabbitmq` | The name of the spawned Docker container (can be used as hostname when accessed from other containers) |

#### Redis

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `redis-distribution` | no | `redis` | the distribution of redis |
| `redis-version` | no | `none` | the version of redis |
| `redis-port` | yes | `6379` | the port of redis-sever |
| `redis-tls-port` | no | `0` | the tls port of redis-sever |
| `redis-auto-start` | yes | `true` | enable to auto-start redis-sever |
| `redis-conf` | no | — | extra configurations for redis.conf |

### Misc

| Input | Required | Default | Description |
| ----- | -------- | ------- | ----------- |
| `apt-packages` | no | `none` | additional apt packages to install |

## Outputs

| Output | Description |
| ------ | ----------- |
| `tuist-cache-hit` | Cache hit for Tuist |

## Example usage

```yml
name: Build
'on':
  pull_request:
    types:
      - opened
      - edited
      - reopened
      - synchronize
  push:
  release:
    types:
      - created
env:
  APT-PACKAGES: ffmpeg
  MONGODB-VERSION: '4.0'
  MYSQL-VERSION: '8.0'
  PHP-COVERAGE: pcov
  PHP-EXTENSIONS: mongodb-1.7.4
  PHP-TOOLS: composer
  PHP-VERSION: '8.1'
  REDIS-VERSION: latest
jobs:
  php_unit_tests:
    name: PHP Unit Tests
    runs-on: ubuntu-latest
    steps:
      - name: Setup
        uses: cloud-officer/ci-actions/setup@v2
        with:
          php-version: "${{env.PHP-VERSION}}"
          php-extensions: "${{env.PHP-EXTENSIONS}}"
          php-coverage: "${{env.PHP-COVERAGE}}"
          php-tools: "${{env.PHP-TOOLS}}"
          mongodb-version: "${{env.MONGODB-VERSION}}"
          mysql-version: "${{env.MYSQL-VERSION}}"
          redis-version: "${{env.REDIS-VERSION}}"
          apt-packages: "${{env.APT-PACKAGES}}"
          ssh-key: "${{secrets.SSH_KEY}}"
          aws-access-key-id: "${{secrets.AWS_ACCESS_KEY_ID}}"
          aws-secret-access-key: "${{secrets.AWS_SECRET_ACCESS_KEY}}"
          aws-region: "${{secrets.AWS_DEFAULT_REGION}}"
```
