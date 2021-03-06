#!/bin/bash
#
# Dubster. Runs unittests on dub packages against latest dmd compiler's
# Copyright (C) 2016  Sebastiaan Koppe
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
set -e

if [ "$#" -ne 3 ]; then
    echo "Illegal number of arguments"
    echo "Arguments:"
    echo "  package-name version compiler-path"
    echo ""
    echo "e.g. unit_threaded 0.6.24 /gen/a23ae1f3e"
    exit 1;
fi

PACKAGE=$1
VERSION=$2
COMPILER=$3

# ln -s /gen/dub-cache /root/.dub/packages
dub fetch $PACKAGE --version=$VERSION

_term() {
	echo "Caught SIGTERM signal!"
	kill -TERM "$child" 2>/dev/null
}
trap _term SIGTERM

dub test --compiler=$COMPILER $PACKAGE &

child=$!
echo "$child"
wait "$child"