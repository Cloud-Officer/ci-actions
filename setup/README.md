# GitHub Action: Setup

This action performs setup of many common tools all at once. Please see the individual actions for more information.

* [checkout](https://github.com/marketplace/actions/checkout)
* [ssh-agent](https://github.com/marketplace/actions/webfactory-ssh-agent)
* [configure-aws-credentials](https://github.com/marketplace/actions/configure-aws-credentials-action-for-github-actions)
* [setup-php](https://github.com/marketplace/actions/setup-php-action)
* [setup-python](https://github.com/marketplace/actions/setup-python)
* [setup-ruby](https://github.com/marketplace/actions/setup-ruby-jruby-and-truffleruby)
* [setup-xcode](https://github.com/marketplace/actions/setup-xcode-version)
* [setup-elasticsearch](https://github.com/marketplace/actions/run-elasticsearch-with-plugins)
* [setup-mongodb](https://github.com/marketplace/actions/mongodb-in-github-actions)
* [setup-mysql](https://github.com/marketplace/actions/actions-setup-mysql)
* [setup-rabbitmq](https://github.com/marketplace/actions/rabbitmq-in-github-actions)
* [setup-redis](https://github.com/marketplace/actions/actions-setup-redis)

Take note that when you enable the setup action for a language, the corresponding [cache](https://github.com/marketplace/actions/cache) action(s) will also be automatically enabled.

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

```yml
inputs:
  github-token:
    description: 'github token'
    required: false
    default: ${{ github.token }}
  fetch-depth:
    description: 'Number of commits to fetch. 0 indicates all history for all branches and tags.'
    default: 1
  ssh-key:
    description: 'ssh key'
    required: false
  aws-region:
    description: AWS Region, e.g. us-east-2
    required: false
  aws-role-to-assume:
    description: The Amazon Resource Name (ARN) of the role to assume. Use the provided credentials to assume an IAM role and configure the Actions environment with the assumed role credentials rather than with the provided credentials.
    required: false
  aws-access-key-id:
    description: AWS Access Key ID. Provide this key if you want to assume a role using access keys rather than a web identity token.
    required: false
  aws-secret-access-key:
    description: AWS Secret Access Key. Required if aws-access-key-id is provided.
    required: false
  aws-session-token:
    description: AWS Session Token.
    required: false
  aws-web-identity-token-file:
    description: Use the web identity token file from the provided file system path in order to assume an IAM role using a web identity, e.g. from within an Amazon EKS worker node.
    required: false
  aws-role-chaining:
    description: Use existing credentials from the environment to assume a new role, rather than providing credentials as input.
    required: false
  aws-audience:
    description: The audience to use for the OIDC provider
    required: false
    default: sts.amazonaws.com
  aws-http-proxy:
    description: Proxy to use for the AWS SDK agent
    required: false
  aws-mask-aws-account-id:
    description: Whether to mask the AWS account ID for these credentials as a secret value. By default the account ID will not be masked
    required: false
  aws-role-duration-seconds:
    description: Role duration in seconds. Default is one hour.
    required: false
  aws-role-external-id:
    description: The external ID of the role to assume.
    required: false
  aws-role-session-name:
    description: "Role session name (default: GitHubActions)"
    required: false
  aws-role-skip-session-tagging:
    description: Skip session tagging during role assumption
    required: false
  aws-inline-session-policy:
    description: Define an inline session policy to use when assuming a role
    required: false
  aws-managed-session-policies:
    description: Define a list of managed session policies to use when assuming a role
    required: false
  aws-output-credentials:
    description: Whether to set credentials as step output
    required: false
  aws-unset-current-credentials:
    description: Whether to unset the existing credentials in your runner. May be useful if you run this action multiple times in the same job
    required: false
  aws-disable-retry:
    description: Whether to disable the retry and backoff mechanism when the assume role call fails. By default the retry mechanism is enabled
    required: false
  aws-retry-max-attempts:
    description: The maximum number of attempts it will attempt to retry the assume role call. By default it will retry 12 times
    required: false
  aws-special-characters-workaround:
    description: Some environments do not support special characters in AWS_SECRET_ACCESS_KEY. This option will retry fetching credentials until the secret access key does not contain special characters. This option overrides disable-retry and retry-max-attempts. This option is disabled by default
    required: false
  go-version:
    description: 'The Go version to download (if necessary) and use. Supports semver spec and ranges. Be sure to enclose this option in single quotation marks.'
    required: false
    default: 'none'
  go-version-file:
    description: 'Path to the go.mod or go.work file.'
    required: false
  go-check-latest:
    description: 'Set this option to true if you want the action to always check for the latest available version that satisfies the version spec'
    required: false
    default: false
  go-token:
    description: Used to pull Go distributions from go-versions. Since there's a default, this is typically not supplied by the user. When running this action on github.com, the default value is sufficient. When running on GHES, you can pass a personal access token for github.com if you are experiencing rate limiting.
    required: false
    default: ${{ github.server_url == 'https://github.com' && github.token || '' }}
  go-cache:
    description: Used to specify whether caching is needed. Set to true, if you'd like to enable caching.
    required: false
    default: true
  go-cache-dependency-path:
    description: 'Used to specify the path to a dependency file - go.sum'
    required: false
  go-architecture:
    description: 'Target architecture for Go to use. Examples: x86, x64. Will use system architecture by default.'
    required: false
  java-version:
    description: 'The Java version to set up. Takes a whole or semver Java version. See examples of supported syntax in README file'
    required: false
    default: 'none'
  java-version-file:
    description: 'The path to the `.java-version` file. See examples of supported syntax in README file'
    required: false
  java-distribution:
    description: 'Java distribution. See the list of supported distributions in README file'
    required: true
    default: 'temurin'
  java-package:
    description: 'The package type (jdk, jre, jdk+fx, jre+fx)'
    required: false
    default: 'jdk'
  java-architecture:
    description: "The architecture of the package (defaults to the action runner's architecture)"
    required: false
  java-jdkFile:
    description: 'Path to where the compressed JDK is located'
    required: false
  java-check-latest:
    description: 'Set this option if you want the action to check for the latest available version that satisfies the version spec'
    required: false
    default: false
  java-server-id:
    description: 'ID of the distributionManagement repository in the pom.xml file. Default is `github`'
    required: false
    default: 'github'
  java-server-username:
    description: 'Environment variable name for the username for authentication to the Apache Maven repository. Default is $GITHUB_ACTOR'
    required: false
    default: 'GITHUB_ACTOR'
  java-server-password:
    description: 'Environment variable name for password or token for authentication to the Apache Maven repository. Default is $GITHUB_TOKEN'
    required: false
    default: 'GITHUB_TOKEN'
  java-settings-path:
    description: 'Path to where the settings.xml file will be written. Default is ~/.m2.'
    required: false
  java-overwrite-settings:
    description: 'Overwrite the settings.xml file if it exists. Default is "true".'
    required: false
    default: true
  java-gpg-private-key:
    description: 'GPG private key to import. Default is empty string.'
    required: false
  java-gpg-passphrase:
    description: 'Environment variable name for the GPG private key passphrase. Default is $GPG_PASSPHRASE.'
    required: false
  java-cache:
    description: 'Name of the build platform to cache dependencies. It can be "maven", "gradle" or "sbt".'
    required: false
  java-cache-dependency-path:
    description: 'The path to a dependency file: pom.xml, build.gradle, build.sbt, etc. This option can be used with the `cache` option. If this option is omitted, the action searches for the dependency file in the entire repository. This option supports wildcards and a list of file names for caching multiple dependencies.'
    required: false
  java-job-status:
    description: 'Workaround to pass job status to post job step. This variable is not intended for manual setting'
    required: false
    default: ${{ job.status }}
  java-token:
    description: The token used to authenticate when fetching version manifests hosted on github.com, such as for the Microsoft Build of OpenJDK. When running this action on github.com, the default value is sufficient. When running on GHES, you can pass a personal access token for github.com if you are experiencing rate limiting.
    required: false
    default: ${{ github.server_url == 'https://github.com' && github.token || '' }}
  java-mvn-toolchain-id:
    description: 'Name of Maven Toolchain ID if the default name of "${distribution}_${java-version}" is not wanted. See examples of supported syntax in Advanced Usage file'
    required: false
  java-mvn-toolchain-vendor:
    description: 'Name of Maven Toolchain Vendor if the default name of "${distribution}" is not wanted. See examples of supported syntax in Advanced Usage file'
    required: false
  node-version:
    description: 'Version Spec of the version to use. Examples: 12.x, 10.15.1, >=10.15.0.'
    required: false
    default: 'none'
  node-version-file:
    description: 'File containing the version Spec of the version to use.  Examples: package.json, .nvmrc, .node-version, .tool-versions.'
    required: false
  node-architecture:
    description: 'Target architecture for Node to use. Examples: x86, x64. Will use system architecture by default.'
    required: false
  node-check-latest:
    description: 'Set this option if you want the action to check for the latest available version that satisfies the version spec.'
    required: false
    default: false
  node-registry-url:
    description: 'Optional registry to set up for auth. Will set the registry in a project level .npmrc and .yarnrc file, and set up auth to read in from env.NODE_AUTH_TOKEN.'
    required: false
  node-scope:
    description: 'Optional scope for authenticating against scoped registries. Will fall back to the repository owner when using the GitHub Packages registry (https://npm.pkg.github.com/).'
    required: false
  node-token:
    description: Used to pull node distributions from node-versions. Since there's a default, this is typically not supplied by the user. When running this action on github.com, the default value is sufficient. When running on GHES, you can pass a personal access token for github.com if you are experiencing rate limiting.
    required: false
    default: ${{ github.server_url == 'https://github.com' && github.token || '' }}
  node-cache:
    description: 'Used to specify a package manager for caching in the default directory. Supported values: npm, yarn, pnpm.'
    required: false
  node-cache-dependency-path:
    description: 'Used to specify the path to a dependency file: package-lock.json, yarn.lock, etc. Supports wildcards or a list of file names for caching multiple dependencies.'
    required: false
  php-version:
    description: 'Setup PHP version.'
    required: false
    default: 'none'
  php-version-file:
    description: 'Setup PHP version from a file.'
    required: false
  php-extensions:
    description: 'Setup PHP extensions'
    required: false
  php-ini-file:
    description: 'Set base ini file'
    required: false
    default: 'production'
  php-ini-values:
    description: 'Add values to php.ini'
    required: false
  php-coverage:
    description: 'Setup code coverage driver'
    required: false
  php-tools:
    description: 'Setup popular tools globally'
    required: false
    default: 'composer'
  python-version:
    description: "Version range or exact version of a Python version to use, using SemVer's version range syntax."
    required: false
    default: 'none'
  python-version-file:
    description: "File containing the Python version to use. Example: .python-version"
    required: false
  python-cache:
    description: 'Used to specify a package manager for caching in the default directory. Supported values: pip, pipenv.'
    required: false
    default: 'pip'
  python-architecture:
    description: 'The target architecture (x86, x64) of the Python interpreter.'
    required: false
    default: 'x64'
  python-check-latest:
    description: "Set this option if you want the action to check for the latest available version that satisfies the version spec."
    required: false
    default: false
  python-token:
    description: Used to pull python distributions from actions/python-versions. Since there's a default, this is typically not supplied by the user.
    required: false
    default: ${{ github.server_url == 'https://github.com' && github.token || '' }}
  python-cache-dependency-path:
    description: 'Used to specify the path to dependency files. Supports wildcards or a list of file names for caching multiple dependencies.'
    required: false
  python-update-environment:
    description: "Set this option if you want the action to update environment variables."
    required: false
    default: true
  python-allow-prereleases:
    description: "When 'true', a version range passed to 'python-version' input will match prerelease versions if no GA versions are found. Only 'x.y' version range is supported for CPython."
    required: false
    default: false
  ruby-version:
    description: 'Engine and version to use, see the syntax in the README. Reads from .ruby-version or .tool-versions if unset.'
    required: false
    default: 'none'
  ruby-rubygems:
    description: 'The version of RubyGems to use. Either default, latest, or a version number'
    required: false
    default: 'default'
  ruby-bundler:
    description: 'The version of Bundler to install. Either none, latest, Gemfile.lock, or a version number'
    required: false
    default: 'default'
  ruby-bundler-cache:
    description: 'Run "bundle install", and cache the result automatically. Either true or false'
    required: false
    default: 'false'
  ruby-working-directory:
    description: 'The working directory to use for resolving paths for .ruby-version, .tool-versions and Gemfile.lock'
    required: false
    default: '.'
  ruby-cache-version:
    description: 'Arbitrary string that will be added to the cache key of the bundler cache'
    required: false
    default: '0'
  ruby-self-hosted:
    description: |
      Consider the runner as a self-hosted runner, which means not using prebuilt Ruby binaries which only work
      on GitHub-hosted runners or self-hosted runners with a very similar image to the ones used by GitHub runners.
      The default is to detect this automatically based on the OS, OS version and architecture.
    required: false
  ruby-windows-toolchain:
    description: |
      This input allows to override the default toolchain setup on Windows.
      The default setting ('default') installs a toolchain based on the selected Ruby.
      Specifically, it installs MSYS2 if not already there and installs mingw/ucrt/mswin build tools and packages.
      It also sets environment variables using 'ridk' or 'vcvars64.bat' based on the selected Ruby.
      At present, the only other setting than 'default' is 'none', which only adds Ruby to PATH.
      No build tools or packages are installed, nor are any ENV setting changed to activate them.
    required: false
  android-sdk-version:
    description: 'sdk version'
    required: false
    default: 'none'
  android-build-tools-version:
    description: 'build tools version'
    required: false
    default: '33.0.2'
  android-ndk-version:
    description: 'ndk version'
    required: false
  android-cmake-version:
    description: 'cmake version'
    required: false
  android-cache-disabled:
    description: 'disabled cache'
    required: false
    default: 'false'
  android-cache-key:
    description: 'cache key'
    required: false
    default: ''
  android-generate-job-summary:
    description: 'display job summary'
    required: false
    default: 'true'
  android-job-status:
    description: 'Workaround to pass job status to post job step. This variable is not intended for manual setting'
    required: false
    default: ${{ job.status }}
  xcode-version:
    description: 'Version of Xcode to use'
    required: false
    default: 'none'
  elasticsearch-version:
    description: 'The version of Elasticsearch'
    default: 'none'
    required: false
  elasticsearch-plugins:
    description: 'Elasticsearch plugin strings'
    required: false
    default: ''
  mongodb-version:
    description: 'MongoDB version to use'
    default: 'none'
    required: false
  mongodb-replica-set:
    description: 'MongoDB replica set name (no replica set by default)'
    required: false
    default: ''
  mongodb-port:
    description: 'MongoDB port to use (default 27017)'
    required: false
    default: 27017
  mongodb-db:
    description: 'MongoDB db to create (default: none)'
    required: false
    default: ''
  mongodb-username:
    description: 'MongoDB root username (default: none)'
    required: false
    default: ''
  mongodb-password:
    description: 'MongoDB root password (default: none)'
    required: false
    default: ''
  mysql-version:
    description: 'The version of MySQL and MariaDB'
    required: false
    default: 'none'
  mysql-distribution:
    description: 'The distribution. valid values are mysql or mariadb'
    required: false
    default: 'mysql'
  mysql-auto-start:
    description: 'Start MySQL server if it is true'
    required: false
    default: 'true'
  mysql-my-cnf:
    description: 'my.cnf settings for mysqld'
    required: false
    default: ''
  mysql-root-password:
    description: 'password for the root user'
    required: false
  mysql-user:
    description: 'name of a new user'
    required: false
  mysql-password:
    description: 'password for the new user'
    required: false
  rabbitmq-version:
    description: 'RabbitMQ version to use'
    required: false
    default: 'none'
  rabbitmq-ports:
    description: 'Port mappings in a [host]:[container] format, delimited by spaces (example: "1883:1883 8883:8883")'
    required: false
    default: '1883:1883'
  rabbitmq-certificates:
    description: 'Absolute path to a directory containing certificate files which can be referenced in the config (the folder is mounted under `/rabbitmq-certs`)'
    required: false
    default: ''
  rabbitmq-config:
    description: 'Absolute path to the `rabbitmq.conf` configuration file to use'
    required: false
    default: ''
  rabbitmq-definitions:
    description: 'Absolute path to the `definitions.json` definition file to use (requires using a `x.y.z-management` image version or enabling the `rabbitmq_management` plugin)'
    required: false
    default: ''
  rabbitmq-plugins:
    description: 'A comma separated list of RabbitMQ plugins which should be enabled'
    required: false
    default: ''
  rabbitmq-container-name:
    description: 'The name of the spawned Docker container (can be used as hostname when accessed from other containers)'
    required: false
    default: 'rabbitmq'
  redis-distribution:
    description: 'the distribution of redis'
    required: false
    default: 'redis'
  redis-version:
    description: 'the version of redis'
    required: false
    default: 'none'
  redis-port:
    description: 'the port of redis-sever'
    required: true
    default: '6379'
  redis-tls-port:
    description: 'the tls port of redis-sever'
    required: false
    default: '0'
  redis-auto-start:
    description: 'enable to auto-start redis-sever'
    required: true
    default: 'true'
  redis-conf:
    description: 'extra configurations for redis.conf'
    required: false
  apt-packages:
    description: 'additional apt packages to install'
    required: false
    default: 'none'
```

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
        uses: cloud-officer/ci-actions/setup@master
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
