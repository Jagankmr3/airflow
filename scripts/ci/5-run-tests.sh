#!/usr/bin/env bash

#
#  Licensed to the Apache Software Foundation (ASF) under one
#  or more contributor license agreements.  See the NOTICE file
#  distributed with this work for additional information
#  regarding copyright ownership.  The ASF licenses this file
#  to you under the Apache License, Version 2.0 (the
#  "License"); you may not use this file except in compliance
#  with the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing,
#  software distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#  KIND, either express or implied.  See the License for the
#  specific language governing permissions and limitations
#  under the License.

set -o verbose
set -e

if [ -z "$HADOOP_HOME" ]; then
    echo "HADOOP_HOME not set - abort" >&2
    exit 1
fi

echo "Using ${HADOOP_DISTRO} distribution of Hadoop from ${HADOOP_HOME}"

pwd

echo "Using travis airflow.cfg"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cp -f ${DIR}/airflow_travis.cfg ~/unittests.cfg

ROOTDIR="$(dirname $(dirname $DIR))"
export AIRFLOW__CORE__DAGS_FOLDER="$ROOTDIR/tests/dags"

# add test/contrib to PYTHONPATH
export PYTHONPATH=${PYTHONPATH:-$ROOTDIR/tests/test_utils}

echo Backend: $AIRFLOW__CORE__SQL_ALCHEMY_CONN

# environment
export AIRFLOW_HOME=${AIRFLOW_HOME:=~}
export AIRFLOW__CORE__UNIT_TEST_MODE=True

# any argument received is overriding the default nose execution arguments:
nose_args=$@

# Generate the `airflow` executable if needed
which airflow > /dev/null || python setup.py develop

# For impersonation tests on Travis, make airflow accessible to other users via the global PATH
# (which contains /usr/local/bin)
sudo ln -sf "${VIRTUAL_ENV}/bin/airflow" /usr/local/bin/

# Fix codecov build path
if [ ! -h /home/travis/build/apache/airflow ]; then
  sudo mkdir -p /home/travis/build/apache
  sudo ln -s ${ROOTDIR} /home/travis/build/apache/airflow
fi

if [ -z "$KUBERNETES_VERSION" ]; then
  echo "Initializing the DB"
  yes | airflow initdb
  yes | airflow resetdb
fi

if [ -z "$nose_args" ]; then
  nose_args="--with-coverage \
  --cover-erase \
  --cover-html \
  --cover-package=airflow \
  --cover-html-dir=airflow/www/static/coverage \
  --with-ignore-docstrings \
  --rednose \
  --with-timer \
  -v \
  --logging-level=INFO \
  --default-connection=True"

fi

if [ -z "$KUBERNETES_VERSION" ]; then
  # kdc init happens in setup_kdc.sh
  kinit -kt ${KRB5_KTNAME} airflow
fi

# For impersonation tests running on SQLite on Travis, make the database world readable so other
# users can update it
AIRFLOW_DB="$HOME/airflow.db"

if [ -f "${AIRFLOW_DB}" ]; then
  chmod a+rw "${AIRFLOW_DB}"
  chmod g+rwx "${AIRFLOW_HOME}"
fi

echo "Starting the unit tests with the following nose arguments: "$nose_args
nosetests $nose_args

# To run individual tests:
# nosetests tests.core:CoreTest.test_scheduler_job
