#!/usr/bin/env bash

set -e

INSTALL_SRC=${INSTALL_SRC:-https://raw.githubusercontent.com/brian-dlee/s3pypkg/master/install-s3pypkg.sh}

## OPTIONS
BUCKET=
PYTHON=
PUBLISH=
OVERWRITE=
SET_DEFAULTS=
FILE=
AWS_PROFILE=
PIP_ARGS=

# https://gist.github.com/masukomi/e587aa6fd4f042496871
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

function get_version_path {
    local bucket=$1
    local name=$2
    local requested_version=$3
    
    echo "Reading available packages from s3://$bucket/$name" >&2
    local objects=($(aws s3 ls --recursive "s3://$bucket/$name/" | awk '{ print $4 }' | sort -r --version-sort))
    for o in ${objects[@]}; do
        echo " - $o" >&2
    done
    echo "" >&2

    if [[ $requested_version == "latest" && ${#objects[@]} -gt 0 ]]; then
        echo "s3://$bucket/${objects[0]}"
    else
        for o in $objects; do
            case $o in
                $name/$name-$version.tar.gz) echo "s3://$bucket/$o"; return 0;;
            esac
        done
    fi
}

function install {
    local python=$1
    local bucket=$2
    local name=$3
    local version=$4
    local pip_args=$5
    local path=$(get_version_path $bucket $name $version)

    if [[ -z $path ]]; then
        if [[ $version == "latest" ]]; then
            echo "No versions of $name are available in $bucket." >&2
            exit 1
        else
            echo "Unable to find version $version of $name in $bucket." >&2
            exit 1
        fi
    fi

    tmp=/tmp/$(date +%s)
    mkdir "$tmp"
    trap "rm -rf \"\$tmp\"" EXIT
    aws s3 cp "$path" "$tmp/$(basename $path)"
    "$python" -m pip $pip_args install "$tmp/$(basename $path)"
}

function publish {
    local bucket=$1
    local path=$2
    local overwrite=$3

    basename=$(basename $path)
    parts=($(IFS='-' parts=("$basename") && echo ${parts[@]}))
    version=${parts[-1]/.tar.gz/}
    name=${basename/-$version.tar.gz/}

    if [[ $(aws s3 ls "s3://$bucket/$name/$name-$version.tar.gz" | wc -l) -gt 0 && -z $overwrite ]]; then
        echo "Refusing to publish: enable overwrite of s3://$bucket/$name/$name-$version.tar.gz by supplying --overwrite" >&2
        return 1
    fi
    aws s3 cp "$path" "s3://$bucket/$name/$name-$version.tar.gz"
}

function self_update {
    local current_install_path=$(cd "$(dirname $0)" && pwd)
    local tmp=$(cd "${TMPDIR:-/tmp}" && pwd)/$(date +%s)

    mkdir $tmp
    trap "rm -rf \$tmp >/dev/null 2>&1" EXIT

    curl -H 'Cache-Control: no-cache' -L "$INSTALL_SRC" | INSTALL_PREFIX=$tmp bash
    
    local code=${PIPESTATUS[1]}
    local destination="$tmp/$(ls "$tmp" | head)"

    if [[ $code -eq 0 && -e "$destination" ]]; then
        mv -v "$destination" "$0"
        return 0
    fi

    return $code
}

function help {
cat <<EOF
Install python packages stored in AWS S3

Automatically creates and stores configuration data containing a default S3 bucket and default python interpreter in ~/.s3pypkg.yml.
The first time --bucket, --python, and --aws-profile are supplied they will be stored for future use.

Usage: s3pypkg [OPTIONS] <PKG_OR_ARCHIVE> [<PKG_OR_ARCHIVE>...]

OPTIONS:
    -b|--bucket <S3_BUCKET_NAME>      Retrieve packages from the provided S3 Bucket
    -p|--python <PYTHON_INTERPRETER>  Use the provided Python executable when installing the python package - must have pip installed
    -u|--publish                      Publish the provided compiled python package (.tar.gz) file(s) to S3
    -f|--file <FILE>                  Read PKG_OR_ARCHIVE from file
    -d|--set-defaults                 Use the currently provided args to reset the defaults in the configuration file
    -o|--overwrite                    Overwrite an existing package in S3
    -U|--self-update                  Install that latest version of s3pypkg and exit
    -P|--pip-args <PIP_ARGS>          String of arguments to be passed to pip during installation
    -a|--aws-profile  <AWS_PROFILE>   AWS profile identifier to use when invoking the AWS CLI
    -h|--help
    
ARGUMENTS:
    PKG_OR_ARCHIVE:  
        If installing (default), the package identifier. Of the form: <name>, <name>@latest, or <name>@<version>
            name:     Allowed symbols include alphanumeric, -, and _
            version:  Basic semantic version e.g. 0.0.0; the wildcard symbol * is supported and when wildcard is supplied the highest matching version will be selected
        If publishing (--publish), the path to a compiled python package (.tar.gz) file

EOF
}

if [[ ! -e ~/.s3pypkg.yml ]]; then
    touch ~/.s3pypkg.yml
fi

eval $(parse_yaml ~/.s3pypkg.yml S3PYPKG_CONF_)
PYTHON=$S3PYPKG_CONF_default_python
BUCKET=$S3PYPKG_CONF_default_s3_bucket
AWS_PROFILE=$S3PYPKG_CONF_default_aws_profile

args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--python) shift; PYTHON=$1;;
        -b|--bucket) shift; BUCKET=$1;;
        -d|--set-default) SET_DEFAULTS=1;;
        -u|--publish) PUBLISH=1;;
        -o|--overwrite) OVERWRITE=1;;
        -f|--file) shift; FILE=$1;;
        -U|--self-update) self_update; exit $?;;
        -P|--pip-args) shift; PIP_ARGS=$1;;
        -a|--aws-profile) shift; AWS_PROFILE=$1;;
        -h|--help) help; exit;;
        -*) echo "Unkown option supplied: $1" >&2; exit 1;;
        *) args+=($1);;
    esac
    shift
done

if [[ ${#args[@]} -eq 0 && -z $FILE ]]; then
   help;
   exit 1;
fi

if [[ -n $AWS_PROFILE ]]; then
    if [[ -z $S3PYPKG_CONF_default_aws_profile || -n $SET_DEFAULTS ]]; then
        echo "Setting $AWS_PROFILE as default AWS profile in ~/.s3pypkg.yml"
        S3PYPKG_CONF_default_aws_profile=$AWS_PROFILE
    fi
    export AWS_PROFILE=$AWS_PROFILE
fi

if [[ -n $PYTHON && (-z $S3PYPKG_CONF_default_python || -n $SET_DEFAULTS) ]]; then
    echo "Setting $PYTHON as default python interpreter in ~/.s3pypkg.yml"
    S3PYPKG_CONF_default_python=$PYTHON
fi

if [[ -z $BUCKET ]]; then
    echo "No bucket configured or provided. Supply --bucket <S3_BUCKET_NAME>." >&2
    exit 1
fi

if [[ -z $S3PYPKG_CONF_default_s3_bucket || -n $SET_DEFAULTS ]]; then
    echo "Setting $BUCKET as default bucket in ~/.s3pypkg.yml"
    S3PYPKG_CONF_default_s3_bucket=$BUCKET
fi
    
cat >~/.s3pypkg.yml <<EOF
default:
  python: $S3PYPKG_CONF_default_python
  s3_bucket: $S3PYPKG_CONF_default_s3_bucket
  aws_profile: $S3PYPKG_CONF_default_aws_profile

EOF

if [[ -n $FILE ]]; then
    if [[ ! -e $FILE ]]; then
        echo "File not found: $FILE" >&2
        exit 1
    fi
    if [[ -n $PUBLISH ]]; then
        echo "The option --publish is incompatible with --file" >&2
        exit 1
    fi
    if [[ ${#args[@]} -gt 0 ]]; then
        echo "Ignoring command line arguments since --file was provided" >&2
    fi
    args=($(cat $FILE))
fi

for arg in "${args[@]}"; do
    if [[ -z $PUBLISH ]]; then
        if [[ $(grep -E '^[-_A-Za-z0-9]+(@([0-9]+\.([0-9]+|\*)\.([0-9]+|\*)|latest))?$' >/dev/null <<<$arg | wc -l) -gt 0 ]]; then
            echo "Cannot install: $arg is not correctly formatted" >&2
            exit 1
        fi
        parts=($(IFS='@' parts=("$arg") && echo ${parts[@]}))
        if [[ -z ${parts[0]} ]]; then
            echo "Cannot install: failed to parse $arg" >&2
            exit 1
        fi
        install "${PYTHON:-python}" "$BUCKET" "${parts[0]}" "${parts[1]:-latest}" "$PIP_ARGS"
    else
        if [[ $(grep -E '^[-_A-Za-z0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz$' >/dev/null <<<$(basename "$arg") | wc -l) -gt 0 ]]; then
            echo "Refusing to publish: $arg should be a path to a compiled/gzipped Python package." >&2
            exit 1
        fi
        if [[ ! -e "$arg" ]]; then
            echo "Cannot publish: $arg not found." >&2
            exit 1
        fi
        publish "$BUCKET" "$arg" "$OVERWRITE"
    fi
done
