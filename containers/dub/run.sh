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

if [ "$#" -ne 2 ]; then
    echo "Illegal number of arguments"
    echo "Arguments:"
    echo "  package-name version"
    echo ""
    echo "e.g. unit_threaded 0.6.24"
    exit 1;
fi

PACKAGE=$1
VERSION=$2

ln -s /dub-cache /root/.dub/packages
dub fetch $PACKAGE --version=$VERSION

dub test --compiler=/compiler/bin/dmd $PACKAGE