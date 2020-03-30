## s3pypkg

A small bash script to install/publish python packages to S3. 
It uses pip for installation so dependency management is intact, but this is unsufficient for including packages
as dependencies in other projects.

I use this to distribute private standalone python packages or command line tools easily with the security of the
AWS CLI.

### Installation

```bash
curl -L https://github.com/brian-dlee/s3pypkg/blob/master/install-s3pypkg.sh | bash
# or
curl -L https://github.com/brian-dlee/s3pypkg/blob/master/install-s3pypkg.sh | INSTALL_PREFIX=/home/auserhasnoname/.local/bin bash
```
