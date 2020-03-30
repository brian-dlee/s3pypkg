#!/usr/bin/env bash

set -e

## OPTIONS
BUCKET=
PYTHON=
PUBLISH=
OVERWRITE=
SET_DEFAULTS=

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
    local version=$3
    local objects=($(aws s3 ls "s3://$bucket/$name/" | awk '{ print $4 }'))

    if [[ $version == "latest" && ${#objects[@]} -gt 0 ]]; then
        echo "s3://$bucket/$name/${objects[-1]}"
    else
        for object in "${objects[@]}"; do
            if [[ $object == "$name-$version.tar.gz" ]]; then
                echo "s3://$bucket/$name/$object"
                return 0
            fi
        done
    fi
}

function install {
    local python=$1
    local bucket=$2
    local name=$3
    local version=$4
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
    "$python" -m pip install "$tmp/$(basename $path)"
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

function help {
cat <<EOF
Install python packages stored in AWS S3

Automatically creates and stores configuration data containing a default S3 bucket and default python interpreter in ~/.s3pypkg.yml.
The first time --bucket and --python are supplied they will be stored in the

Usage: s3pypkg [OPTIONS] <PKG_OR_ARCHIVE> [<PKG_OR_ARCHIVE>...]

OPTIONS:
    -b|--bucket <S3_BUCKET_NAME>      Retrieve packages from the provided S3 Bucket
    -p|--python <PYTHON_INTERPRETER>  Use the provided Python executable when installing the python package - must have pip installed
    -u|--publish                      Publish the provided compiled python package (.tar.gz) file(s) to S3
    -d|--set-defaults                 Use the currently provided args to reset the defaults in the configuration file
    -o|--overwrite                    Overwrite an existing package in S3
    -h|--help
    
ARGUMENTS:
    PKG_OR_ARCHIVE:  
        If installing (default), the package identifier. Of the form: <name>, <name>@latest, or <name>@<version>
            name:     Allowed symbols include alphanumeric, -, and _
            version:  Basic semantic version. e.g. 0.0.0
        If publishing (--publish), the path to a compiled python package (.tar.gz) file

EOF
}

if [[ ! -e ~/.s3pypkg.yml ]]; then
    touch ~/.s3pypkg.yml
fi

eval $(parse_yaml ~/.s3pypkg.yml S3PYPKG_CONF_)
PYTHON=$S3PYPKG_CONF_default_python
BUCKET=$S3PYPKG_CONF_default_s3_bucket

args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--python) shift; PYTHON=$1;;
        -b|--bucket) shift; BUCKET=$1;;
        -d|--set-default) SET_DEFAULTS=1;;
        -u|--publish) PUBLISH=1;;
        -o|--overwrite) OVERWRITE=1;;
        -h|--help) help; exit;;
        *) args+=($1);;
    esac
    shift
done

if [[ ${#args[@]} -eq 0 ]]; then
   help;
   exit 1;
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

EOF

for arg in "${args[@]}"; do
    if [[ -z $PUBLISH ]]; then
        if [[ $(grep -E '^[-_A-Za-z0-9]+(@([0-9]+\.[0-9]+\.[0-9]+|latest))?$' >/dev/null <<<$arg | wc -l) -gt 0 ]]; then
            echo "Cannot install: $arg is not correctly formatted" >&2
            exit 1
        fi
        parts=$(IFS='@' parts=("$arg") && echo ${parts[@]})
        if [[ -z ${parts[0]} ]]; then
            echo "Cannot install: failed to parse $arg" >&2
            exit 1
        fi
        install "${PYTHON:-python}" "$BUCKET" "${parts[0]}" "${parts[1]:-latest}"
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
