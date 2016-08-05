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
FROM debian:jessie
MAINTAINER "Sebastiaan Koppe"

RUN apt-get update && \
    apt-get install -y git g++ binutils make curl && \
    curl -LO https://github.com/CyberShadow/Digger/releases/download/2.4/digger-2.4-linux-64.tgz && \
    tar -xzf digger-2.4-linux-64.tgz && \
    chown -R root:root digger-2.4-linux-64 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    mkdir -p /gen

WORKDIR /digger-2.4-linux-64

ADD digger.ini /digger-2.4-linux-64/digger.ini

ENTRYPOINT ["./digger"]