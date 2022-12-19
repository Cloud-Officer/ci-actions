# GitHub Action: Setup

This action performs setup of many common tools all at once. Please see the individual actions for more information.

* [checkout](https://github.com/marketplace/actions/checkout)
* [ssh-agent](https://github.com/marketplace/actions/webfactory-ssh-agent)
* [configure-aws-credentials](https://github.com/marketplace/actions/configure-aws-credentials-action-for-github-actions)
* [setup-php](https://github.com/marketplace/actions/setup-php-action)
* [setup-python](https://github.com/marketplace/actions/setup-python)
* [setup-ruby](https://github.com/marketplace/actions/setup-ruby-jruby-and-truffleruby)
* [setup-xcode](https://github.com/marketplace/actions/setup-xcode-version)
* [setup-mongodb](https://github.com/marketplace/actions/mongodb-in-github-actions)
* [setup-mysql](https://github.com/marketplace/actions/actions-setup-mysql)
* [setup-redis](https://github.com/marketplace/actions/actions-setup-redis)

Take note that when you enable the setup action for a language, the
corresponding [cache](https://github.com/marketplace/actions/cache) action(s) will also be automatically enabled.

## Inputs

```yml
inputs:
  ssh-key:
    description: 'ssh key'
    required: false
  aws-access-key-id:
    description: 'aws access key id'
    required: false
  aws-secret-access-key:
    description: 'aws secret access key'
    required: false
  aws-region:
    description: 'aws region'
    required: false
  go-version:
    description: 'The Go version to download (if necessary) and use. Supports semver spec and ranges'
    required: false
    default: 'none'
  go-check-latest:
    description: 'Set this option to true if you want the action to always check for the latest available version that satisfies the version spec'
    required: false
    default: false
  go-token:
    description: 'Used to pull node distributions from go-versions'
    required: false
    default: ${{ github.token }}
  php-version:
    description: 'Setup PHP version.'
    required: false
    default: 'none'
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
  python-cache:
    description: 'Used to specify a package manager for caching in the default directory. Supported values: pip, pipenv.'
    required: false
    default: 'pip'
  python-architecture:
    description: 'The target architecture (x86, x64) of the Python interpreter.'
    required: false
    default: 'x64'
  python-token:
    description: Used to pull python distributions from actions/python-versions. Since there's a default, this is typically not supplied by the user.
    required: false
    default: ${{ github.token }}
  python-cache-dependency-path:
    description: 'Used to specify the path to dependency files. Supports wildcards or a list of file names for caching multiple dependencies.'
    required: false
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
  xcode-version:
    description: 'Version of Xcode to use'
    required: false
    default: 'none'
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
  redis-version:
    description: 'the version of redis'
    required: true
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
