# s3pypkg

A small bash script to install packages stored in S3 or publish python packages to S3.
It uses pip for installation so dependency management is intact, but this is unsufficient for including packages
as dependencies in other projects.

A good use case for this tool is distributing private standalone python packages or command line tools 
easily with the inherent security of the AWS CLI.

## Dependencies
 * Python
 * Pip
 * AWS CLI - https://docs.aws.amazon.com/cli/index.html

## Installation

```bash
curl -L https://raw.githubusercontent.com/brian-dlee/s3pypkg/master/install-s3pypkg.sh | bash
# or
curl -L https://raw.githubusercontent.com/brian-dlee/s3pypkg/master/install-s3pypkg.sh | INSTALL_PREFIX=/home/auserhasnoname/.local/bin bash
```

## Configuration

The first time the script is ran it will generate a configuration file containing information for subsequent runs.
The configuration file generated will be at `~/.s3pypkg.yml`

## Usage

For full usage, run `s3pypkg --help`.

### Install a package

Install a package in your S3 bucket by supplying the package name with optional version separated by `@`.
```bash
s3pypkg mypkg@1.0.0
```

### Publish a package

Publish a package on your system to your S3 bucket by supplying the path to the gzipped python package. This can easily be generated with tools like [Poetry](https://python-poetry.org/) (`poetry build`) or with setuptools (`python setup.py sdist`).
```bash
s3pypkg --publish ./dist/mypkg-1.0.0.tar.gz
```

If a package already exists with the given version, you need to use the `--overwrite` option to publish.
